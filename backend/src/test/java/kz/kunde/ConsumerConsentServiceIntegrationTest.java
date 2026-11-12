package kz.kunde;

import static org.assertj.core.api.Assertions.*;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerConsentService;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.identity.consumer-enabled=true",
        "app.security.oidc.issuer-uri=https://identity.example.test",
        "app.security.oidc.audience=kunde-api"
})
class ConsumerConsentServiceIntegrationTest {
    @Autowired ConsumerIdentityService identity;
    @Autowired ConsumerConsentService consents;
    @Autowired JdbcTemplate db;

    private Jwt jwt() {
        return Jwt.withTokenValue("fixture").header("alg", "RS256")
                .issuer("https://identity.example.test").subject(UUID.randomUUID().toString())
                .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(300))
                .audience(List.of("kunde-api")).claim("typ", "Bearer")
                .claim("azp", "kunde-consumer").claim("scope", "kunde.consumer").build();
    }

    private UUID policy(boolean approved) {
        return db.queryForObject("""
                INSERT INTO profile.consent_policies
                    (purpose, policy_version, document_sha256, locale, approved_at)
                VALUES ('synthetic_consent', ?, ?, 'ru', CASE WHEN ? THEN now() ELSE NULL END)
                RETURNING id
                """, UUID.class, UUID.randomUUID().toString(), "a".repeat(64), approved);
    }

    @Test
    @Transactional
    void noImplicitConsentAndNoUnapprovedGrants() {
        Jwt jwt = jwt();
        identity.get(jwt);
        UUID unapproved = policy(false);
        assertThat(consents.list(jwt)).noneMatch(p -> p.policyId().equals(unapproved));
        assertThatThrownBy(() -> consents.change(jwt, unapproved, true))
                .isInstanceOf(ApiException.class);
    }

    @Test
    @Transactional
    void grantsAreIdempotentWithdrawalsRecordedAndOtherUsersIsolated() {
        Jwt first = jwt();
        Jwt second = jwt();
        UUID firstId = identity.get(first).id();
        identity.get(second);
        UUID approved = policy(true);
        assertThat(consents.list(first)).filteredOn(p -> p.policyId().equals(approved))
                .allMatch(p -> !p.granted());
        assertThat(consents.change(first, approved, true).granted()).isTrue();
        consents.change(first, approved, true);
        assertThat(db.queryForObject("""
                SELECT count(*) FROM profile.consent_events WHERE user_id = ? AND policy_id = ?
                """, Integer.class, firstId, approved)).isEqualTo(1);
        assertThat(consents.list(second)).filteredOn(p -> p.policyId().equals(approved))
                .allMatch(p -> !p.granted());
        assertThat(consents.change(first, approved, false).granted()).isFalse();
        assertThat(db.queryForObject("""
                SELECT count(*) FROM profile.consent_events WHERE user_id = ? AND policy_id = ?
                """, Integer.class, firstId, approved)).isEqualTo(2);
    }

    @Test
    @Transactional
    void unprovisionedOrRestrictedAccountCannotChangeConsent() {
        Jwt jwt = jwt();
        UUID approved = policy(true);
        assertThatThrownBy(() -> consents.change(jwt, approved, true))
                .isInstanceOf(ApiException.class);
        UUID user = identity.get(jwt).id();
        db.update("UPDATE identity.users SET status = 'RESTRICTED' WHERE id = ?", user);
        assertThatThrownBy(() -> consents.change(jwt, approved, true))
                .isInstanceOf(ApiException.class);
    }
}
