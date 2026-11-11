package kz.kunde;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.http.MediaType;

@SpringBootTest(properties = {
        "app.identity.consumer-enabled=true",
        "app.security.oidc.issuer-uri=https://identity.example.test",
        "app.security.oidc.audience=kunde-api"
})
@AutoConfigureMockMvc
class ConsumerIdentityIntegrationTest {
    @Autowired ConsumerIdentityService identity;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc http;
    @MockitoBean JwtDecoder issuerJwtDecoder;

    private Jwt jwt(String subject) {
        return Jwt.withTokenValue("fixture").header("alg", "RS256").issuer("https://identity.example.test")
                .subject(subject).issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(300))
                .audience(List.of("kunde-api")).claim("typ", "Bearer").claim("azp", "kunde-consumer")
                .claim("scope", "openid kunde.consumer").build();
    }

    @Test
    void concurrentFirstLoginHasOneAccountBindingAndAudit() throws Exception {
        Jwt principal = jwt(UUID.randomUUID().toString());
        try (var executor = Executors.newFixedThreadPool(8)) {
            CountDownLatch ready = new CountDownLatch(8);
            CountDownLatch start = new CountDownLatch(1);
            var futures = new ArrayList<Future<UUID>>();
            for (int i = 0; i < 8; i++) {
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    if (!start.await(10, TimeUnit.SECONDS)) throw new IllegalStateException("Start timed out");
                    return identity.get(principal).id();
                }));
            }
            assertThat(ready.await(10, TimeUnit.SECONDS)).isTrue();
            start.countDown();
            Set<UUID> ids = new HashSet<>();
            for (var future : futures) ids.add(future.get(20, TimeUnit.SECONDS));
            assertThat(ids).hasSize(1);
            UUID user = ids.iterator().next();
            assertThat(user.toString()).isNotEqualTo(principal.getSubject());
            assertThat(db.queryForObject("SELECT count(*) FROM identity.external_bindings WHERE user_id = ?", Integer.class, user)).isEqualTo(1);
            assertThat(db.queryForObject("SELECT count(*) FROM identity.account_events WHERE user_id = ?", Integer.class, user)).isEqualTo(1);
        }
    }

    @Test
    void databaseRejectsDuplicateBindingsAndDoesNotLinkContacts() {
        Jwt first = jwt(UUID.randomUUID().toString());
        var one = identity.get(first);
        var two = identity.get(jwt(UUID.randomUUID().toString()));
        assertThat(one.id()).isNotEqualTo(two.id());
        assertThatThrownBy(() -> db.update(
                "INSERT INTO identity.external_bindings (issuer, subject, user_id) VALUES (?, ?, ?)",
                first.getClaimAsString("iss"), first.getSubject(), two.id()))
                .isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
        assertThat(identity.get(first).id()).isEqualTo(one.id());
    }

    @Test
    void lifecycleAndOptimisticConcurrencyAreEnforced() {
        Jwt principal = jwt(UUID.randomUUID().toString());
        var profile = identity.get(principal);
        assertThat(identity.update(principal, "Synthetic", "kk", 0).version()).isEqualTo(1);
        assertThatThrownBy(() -> identity.update(principal, "Stale", "ru", 0))
                .isInstanceOf(ApiException.class).hasMessageContaining("Reload");
        db.update("UPDATE identity.users SET status = 'RESTRICTED' WHERE id = ?", profile.id());
        assertThatThrownBy(() -> identity.get(principal)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> identity.update(principal, "Blocked", "en", 1)).isInstanceOf(ApiException.class);
    }

    @Test
    void profileApiValidatesInputAndCannotSelectAnotherUser() throws Exception {
        String token = UUID.randomUUID().toString();
        Jwt principal = jwt(token);
        when(issuerJwtDecoder.decode(token)).thenReturn(principal);
        var other = identity.get(jwt(UUID.randomUUID().toString()));
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").isNotEmpty())
                .andExpect(header().string("Cache-Control", "no-store"));
        http.perform(patch("/api/v1/me").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\"Synthetic\",\"preferredLanguage\":\"en\",\"version\":0}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1));
        http.perform(patch("/api/v1/me").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\" \",\"preferredLanguage\":\"xx\",\"version\":-1}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.correlationId").isNotEmpty());
        http.perform(get("/api/v1/me/" + other.id()).header("Authorization", "Bearer " + token))
                .andExpect(status().isNotFound());
        http.perform(get("/api/v1/me/sessions").header("Authorization", "Bearer " + token))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("SESSION_MANAGEMENT_UNAVAILABLE"));
        http.perform(delete("/api/v1/me/sessions/" + other.id()).header("Authorization", "Bearer " + token))
                .andExpect(status().isServiceUnavailable());
    }

    @Test
    void missingAuthenticationIsDenied() throws Exception {
        http.perform(get("/api/v1/me")).andExpect(status().isUnauthorized());
    }
}
