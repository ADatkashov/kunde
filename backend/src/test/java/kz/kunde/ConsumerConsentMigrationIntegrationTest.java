package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
class ConsumerConsentMigrationIntegrationTest {
    @Autowired JdbcTemplate db;

    @Test
    @Transactional
    void consentIsNotInferredFromAccountProvisioningOrUnapprovedPolicy() {
        assertThat(db.queryForObject(
                "select count(*) from flyway_schema_history where version = '4' and success",
                Integer.class)).isEqualTo(1);
        UUID user = db.queryForObject(
                "insert into identity.users default values returning id", UUID.class);
        assertThat(db.queryForObject(
                "select count(*) from profile.consent_events where user_id = ?",
                Integer.class, user)).isZero();

        UUID policy = db.queryForObject("""
                insert into profile.consent_policies (purpose, policy_version, document_sha256, locale)
                values ('synthetic_test', ?, ?, 'ru') returning id
                """, UUID.class, user.toString(), "a".repeat(64));
        assertThat(db.queryForObject(
                "select approved_at from profile.consent_policies where id = ?",
                (rs, row) -> rs.getObject(1), policy)).isNull();
        assertThat(db.queryForObject(
                "select count(*) from profile.consent_events where user_id = ?",
                Integer.class, user)).isZero();
    }
}
