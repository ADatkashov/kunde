package kz.kunde.partner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jwt.SignedJWT;
import java.util.UUID;
import kz.kunde.partner.PartnerService.Role;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * ADR-018 step 2: partner onboarding and profile over HTTP, including IDOR and revocation checks.
 * Synthetic numbers only; the whole test rolls back, so no partner rows remain (ADR-014 "no seeded partners" guard).
 */
@Transactional
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
class PartnerApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PartnerService service;

    @BeforeEach
    void clean() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000114', '+77000000115', '+77000000116')");
    }

    private ResultActions postJson(String path, String token, String json) throws Exception {
        var request = post(path).contentType(MediaType.APPLICATION_JSON).content(json);
        return http.perform(token == null ? request : request.header("Authorization", "Bearer " + token));
    }

    private String login(String phone) throws Exception {
        postJson("/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return postJson("/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private String refreshed(String loginBody) throws Exception {
        return postJson("/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private static String access(String body) { return JsonPath.read(body, "$.accessToken"); }

    private static UUID user(String body) throws Exception {
        return UUID.fromString(SignedJWT.parse(access(body)).getJWTClaimsSet().getSubject());
    }

    private String apply(String token, String name) throws Exception {
        return postJson("/api/v1/partner/applications", token, "{\"displayName\":\"" + name + "\"}")
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
    }

    @Test
    void applicationCreatesPendingPartnerAndOwnerAndNeedsARefreshToGetTheScope() throws Exception {
        String login = login("+77000000114");
        String created = apply(access(login), "  Synthetic Cafe  ");
        assertThat((String) JsonPath.read(created, "$.displayName")).isEqualTo("Synthetic Cafe");
        assertThat((String) JsonPath.read(created, "$.verificationStatus")).isEqualTo("PENDING_REVIEW");
        String id = JsonPath.read(created, "$.id");

        // The old token has no partner scope yet; the refreshed one does.
        http.perform(get("/api/v1/partner/partners").header("Authorization", "Bearer " + access(login)))
                .andExpect(status().isForbidden());
        String token = access(refreshed(login));
        http.perform(get("/api/v1/partner/partners").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$[0].id").value(id)).andExpect(jsonPath("$[0].role").value("OWNER"));

        // Audit: submission and owner grant are recorded; a pending partner is not public.
        assertThat(db.queryForObject("SELECT count(*) FROM marketplace.partner_verification_events WHERE partner_id = ?::uuid AND decision = 'SUBMIT'", Integer.class, id)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT count(*) FROM marketplace.partner_staff_events WHERE partner_id = ?::uuid AND event_type = 'GRANTED'", Integer.class, id)).isEqualTo(1);
        http.perform(get("/api/v1/partners/" + id)).andExpect(status().isNotFound());
    }

    @Test
    void invalidApplicationsAndAnonymousAccessAreRejected() throws Exception {
        String token = access(login("+77000000114"));
        postJson("/api/v1/partner/applications", token, "{\"displayName\":\"   \"}").andExpect(status().isBadRequest());
        postJson("/api/v1/partner/applications", token, "{}").andExpect(status().isBadRequest());
        postJson("/api/v1/partner/applications", token, "{\"displayName\":\"" + "x".repeat(121) + "\"}").andExpect(status().isBadRequest());
        postJson("/api/v1/partner/applications", null, "{\"displayName\":\"Anon\"}").andExpect(status().isUnauthorized());
        http.perform(get("/api/v1/partner/partners")).andExpect(status().isUnauthorized());
    }

    @Test
    void applicationsPerUserAreCapped() throws Exception {
        String token = access(login("+77000000114"));
        for (int i = 0; i < PartnerService.MAX_APPLICATIONS_PER_USER; i++) {
            apply(token, "Cafe " + i);
        }
        postJson("/api/v1/partner/applications", token, "{\"displayName\":\"One more\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PARTNER_APPLICATION_LIMIT"));
    }

    @Test
    void otherPartnersCannotBeReadOrChangedAndLookLikeUnknownIds() throws Exception {
        String loginA = login("+77000000114");
        String loginB = login("+77000000115");
        String idA = JsonPath.read(apply(access(loginA), "Partner A"), "$.id");
        apply(access(loginB), "Partner B");
        String tokenB = access(refreshed(loginB));

        UUID unknown = UUID.randomUUID();
        for (String target : new String[] {idA, unknown.toString()}) {
            http.perform(get("/api/v1/partner/partners/" + target).header("Authorization", "Bearer " + tokenB))
                    .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("PARTNER_NOT_FOUND"));
            http.perform(patch("/api/v1/partner/partners/" + target).header("Authorization", "Bearer " + tokenB)
                    .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\"Hijacked\",\"version\":0}"))
                    .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("PARTNER_NOT_FOUND"));
        }
        assertThat(db.queryForObject("SELECT display_name FROM marketplace.partners WHERE id = ?::uuid", String.class, idA))
                .isEqualTo("Partner A");
        // B's own list never contains A's partner.
        http.perform(get("/api/v1/partner/partners").header("Authorization", "Bearer " + tokenB))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].displayName").value("Partner B"));
    }

    @Test
    void profileUpdateRespectsRolesVersionsAndIsAudited() throws Exception {
        String loginA = login("+77000000114");
        String loginC = login("+77000000116");
        String created = apply(access(loginA), "Old Name");
        UUID id = UUID.fromString(JsonPath.read(created, "$.id"));
        UUID owner = user(loginA);
        service.grantStaff(owner, id, user(loginC), Role.OPERATOR);
        String tokenA = access(refreshed(loginA));
        String tokenC = access(refreshed(loginC));

        // Operator may read but not edit.
        http.perform(get("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenC))
                .andExpect(status().isOk()).andExpect(jsonPath("$.displayName").value("Old Name"));
        http.perform(patch("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenC)
                .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\"Nope\",\"version\":0}"))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("PARTNER_ROLE_FORBIDDEN"));

        // Owner edits with the right version; stale version conflicts; invalid names are rejected.
        http.perform(patch("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenA)
                .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\"New Name\",\"version\":0}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.displayName").value("New Name"))
                .andExpect(jsonPath("$.version").value(1));
        http.perform(patch("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenA)
                .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\"Stale\",\"version\":0}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        http.perform(patch("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenA)
                .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\" \",\"version\":1}"))
                .andExpect(status().isBadRequest());
        // The edit never changes the verification state.
        assertThat(db.queryForObject("SELECT verification_status FROM marketplace.partners WHERE id = ?", String.class, id))
                .isEqualTo("PENDING_REVIEW");
        assertThat(db.queryForList("SELECT old_value || '>' || new_value FROM marketplace.partner_profile_events WHERE partner_id = ?", String.class, id))
                .containsExactly("Old Name>New Name");
    }

    @Test
    void revokedStaffLoseAccessImmediatelyEvenWithAStillValidToken() throws Exception {
        String loginA = login("+77000000114");
        String loginC = login("+77000000116");
        UUID id = UUID.fromString(JsonPath.read(apply(access(loginA), "Revocation Cafe"), "$.id"));
        service.grantStaff(user(loginA), id, user(loginC), Role.MANAGER);
        String tokenC = access(refreshed(loginC));
        http.perform(get("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenC)).andExpect(status().isOk());

        service.revokeStaff(user(loginA), id, user(loginC));
        // Same token, still unexpired and still carrying kunde.partner: the per-request membership check refuses it.
        http.perform(get("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenC))
                .andExpect(status().isNotFound());
        http.perform(patch("/api/v1/partner/partners/" + id).header("Authorization", "Bearer " + tokenC)
                .contentType(MediaType.APPLICATION_JSON).content("{\"displayName\":\"Late\",\"version\":0}"))
                .andExpect(status().isNotFound());
        http.perform(get("/api/v1/partner/partners").header("Authorization", "Bearer " + tokenC))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
    }
}
