package kz.kunde.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jwt.SignedJWT;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

/** ADR-018: partner/admin token scopes derive from database state only; synthetic numbers only. */
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000101,+77000000102,+77000000103,+77000000104,+77000000105,"
                + "+77000000106,+77000000107,+77000000108,+77000000109,+77000000110,+77000000111,"
                + "+77000000112,+77000000113,+77000000114,+77000000115,+77000000116",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class RoleScopeIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void clean() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000112', '+77000000113')");
    }

    /** The partner row is committed (the login endpoints run in their own transactions); remove it so the "no seeded partners" guard stays valid. */
    @AfterEach
    void removePartners() {
        db.update("DELETE FROM marketplace.partner_staff WHERE partner_id IN (SELECT id FROM marketplace.partners WHERE display_name = 'Scope Test Partner')");
        db.update("DELETE FROM marketplace.partners WHERE display_name = 'Scope Test Partner'");
    }

    private String body(String path, String json) throws Exception {
        return http.perform(post(path).contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private String login(String phone) throws Exception {
        http.perform(post("/api/v1/auth/otp/request").contentType(MediaType.APPLICATION_JSON)
                .content("{\"phone\":\"" + phone + "\"}")).andExpect(status().isAccepted());
        return body("/api/v1/auth/otp/verify", "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}");
    }

    private String refresh(String loginBody) throws Exception {
        return body("/api/v1/auth/token/refresh",
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}");
    }

    private static String scope(String tokens) throws Exception {
        return SignedJWT.parse(JsonPath.read(tokens, "$.accessToken")).getJWTClaimsSet().getStringClaim("scope");
    }

    private static UUID subject(String tokens) throws Exception {
        return UUID.fromString(SignedJWT.parse(JsonPath.read(tokens, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    @Test
    void publicLoginIsConsumerOnlyAndPartnerScopeFollowsActiveStaffMembership() throws Exception {
        String first = login("+77000000112");
        assertThat(scope(first)).isEqualTo("kunde.consumer");
        UUID user = subject(first);

        UUID partner = db.queryForObject("""
                INSERT INTO marketplace.partners (display_name, verification_status, created_by_user_id)
                VALUES ('Scope Test Partner', 'PENDING_REVIEW', ?) RETURNING id""", UUID.class, user);
        db.update("INSERT INTO marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) VALUES (?, ?, 'OWNER', ?)",
                partner, user, user);
        String withPartner = refresh(first);
        assertThat(scope(withPartner)).isEqualTo("kunde.consumer kunde.partner");

        db.update("UPDATE marketplace.partner_staff SET status = 'REVOKED', revoked_at = now(), revoked_by_user_id = ? WHERE partner_id = ? AND user_id = ?",
                user, partner, user);
        assertThat(scope(refresh(withPartner))).isEqualTo("kunde.consumer");
    }

    @Test
    void adminScopeNeedsAnUnrevokedGrantAndIsRemovedOnRevocation() throws Exception {
        String first = login("+77000000113");
        assertThat(scope(first)).doesNotContain("kunde.admin");
        UUID user = subject(first);

        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'PARTNER_VERIFICATION', 'synthetic DEV admin')", user);
        String admin = refresh(first);
        assertThat(scope(admin)).isEqualTo("kunde.consumer kunde.admin");

        // One active grant per permission; unknown permissions and blank reasons are rejected by the database.
        assertThatThrownBy(() -> db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'PARTNER_VERIFICATION', 'dup')", user))
                .hasMessageContaining("admin_grants_active_uq");
        assertThatThrownBy(() -> db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'ROOT', 'x')", user))
                .hasMessageContaining("admin_grants_permission_check");
        assertThatThrownBy(() -> db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'ADMIN_GRANTS', ' ')", user))
                .hasMessageContaining("admin_grants_reason_check");

        db.update("UPDATE identity.admin_grants SET revoked_at = now(), revoked_by_user_id = ? WHERE user_id = ?", user, user);
        assertThat(scope(refresh(admin))).isEqualTo("kunde.consumer");
    }
}
