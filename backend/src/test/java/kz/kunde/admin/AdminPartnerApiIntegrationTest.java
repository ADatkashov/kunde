package kz.kunde.admin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jwt.SignedJWT;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.admin.AdminGrants.Scope;
import kz.kunde.partner.PartnerService;
import kz.kunde.platform.ApiException;
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
 * ADR-018 step 4: admin partner verification over HTTP, including the full pilot path (apply, approve, publish, consumer view).
 * Synthetic numbers only; the whole test rolls back, so no partner, category or offering rows remain.
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
class AdminPartnerApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PartnerService service;
    @Autowired AdminGrants grants;

    @BeforeEach
    void clean() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000114', '+77000000115', '+77000000116')");
    }

    private ResultActions send(String path, String token, String json) throws Exception {
        var request = post(path).contentType(MediaType.APPLICATION_JSON).content(json);
        return http.perform(token == null ? request : request.header("Authorization", "Bearer " + token));
    }

    private ResultActions fetch(String path, String token) throws Exception {
        return http.perform(get(path).header("Authorization", "Bearer " + token));
    }

    private String login(String phone) throws Exception {
        send("/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return send("/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private String refreshed(String loginBody) throws Exception {
        return JsonPath.read(send("/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(), "$.accessToken");
    }

    private static UUID user(String loginBody) throws Exception {
        return UUID.fromString(SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    private UUID apply(String loginBody, String name) throws Exception {
        String token = JsonPath.read(loginBody, "$.accessToken");
        return UUID.fromString(JsonPath.read(send("/api/v1/partner/applications", token, "{\"displayName\":\"" + name + "\"}")
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id"));
    }

    /** Owner-provisioned DEV admin: an out-of-band grant row, then a refresh so the token carries kunde.admin. */
    private String adminToken(String loginBody, String permission) throws Exception {
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, ?, 'synthetic DEV admin')", user(loginBody), permission);
        return refreshed(loginBody);
    }

    private String decide(UUID partner, String decision, String reason, long version) {
        return "{\"decision\":\"" + decision + "\"," + (reason == null ? "" : "\"reason\":\"" + reason + "\",") + "\"version\":" + version + "}";
    }

    @Test
    void fullPilotPathApplyApprovePublishAndConsumerSeesIt() throws Exception {
        String loginA = login("+77000000114");
        String loginAdmin = login("+77000000115");
        UUID partner = apply(loginA, "Pilot Cafe");
        String tokenA = refreshed(loginA);
        String admin = adminToken(loginAdmin, "PARTNER_VERIFICATION");
        UUID category = db.queryForObject("""
                INSERT INTO marketplace.categories (code, name_ru, name_kk, status, published_at)
                VALUES ('pilot-' || substr(gen_random_uuid()::text, 1, 8), 'Еда', 'Тағам', 'PUBLISHED', now()) RETURNING id""", UUID.class);
        String offering = JsonPath.read(send("/api/v1/partner/partners/" + partner + "/offerings", tokenA,
                "{\"categoryId\":\"" + category + "\",\"kind\":\"PRODUCT\",\"nameRu\":\"Плов\",\"nameKk\":\"Палау\",\"priceMinor\":350000,\"availability\":\"AVAILABLE\"}")
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id");

        // The admin queue lists the pending partner without any personal data.
        String queue = fetch("/api/v1/admin/partners?status=PENDING_REVIEW", admin).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(partner.toString())).andReturn().getResponse().getContentAsString();
        assertThat(queue).doesNotContain("+7700").doesNotContain("phone");

        // Before approval nothing is public and publishing is refused.
        http.perform(get("/api/v1/partners/" + partner)).andExpect(status().isNotFound());
        send("/api/v1/partner/partners/" + partner + "/offerings/" + offering + "/publish", tokenA, "{\"version\":0}").andExpect(status().isConflict());

        send("/api/v1/admin/partners/" + partner + "/decision", admin, decide(partner, "APPROVE", null, 0))
                .andExpect(status().isOk()).andExpect(jsonPath("$.verificationStatus").value("APPROVED")).andExpect(jsonPath("$.version").value(1));
        http.perform(get("/api/v1/partners/" + partner)).andExpect(status().isOk()).andExpect(jsonPath("$.displayName").value("Pilot Cafe"));
        send("/api/v1/partner/partners/" + partner + "/offerings/" + offering + "/publish", tokenA, "{\"version\":0}").andExpect(status().isOk());
        http.perform(get("/api/v1/categories/" + category + "/offerings")).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].nameRu").value("Плов")).andExpect(jsonPath("$[0].priceMinor").value(350000))
                .andExpect(jsonPath("$[0].partnerName").value("Pilot Cafe"));

        // Suspension hides the published offering again without touching it; the history records every decision.
        send("/api/v1/admin/partners/" + partner + "/decision", admin, decide(partner, "SUSPEND", "synthetic check", 1)).andExpect(status().isOk());
        http.perform(get("/api/v1/categories/" + category + "/offerings")).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        fetch("/api/v1/admin/partners/" + partner, admin).andExpect(status().isOk())
                .andExpect(jsonPath("$.history.length()").value(3))
                .andExpect(jsonPath("$.history[1].decision").value("APPROVE")).andExpect(jsonPath("$.history[2].reason").value("synthetic check"));
    }

    @Test
    void adminScopeAndAGrantAreBothRequiredAndRevocationIsImmediate() throws Exception {
        String loginA = login("+77000000114");
        String loginAdmin = login("+77000000115");
        apply(loginA, "Gate Cafe");
        fetch("/api/v1/admin/partners", JsonPath.read(loginA, "$.accessToken")).andExpect(status().isForbidden());
        fetch("/api/v1/admin/partners", refreshed(loginA)).andExpect(status().isForbidden());
        http.perform(get("/api/v1/admin/partners")).andExpect(status().isUnauthorized());

        // A grant for another permission is not enough for partner verification.
        String wrongGrant = adminToken(loginAdmin, "ADMIN_GRANTS");
        fetch("/api/v1/admin/partners", wrongGrant).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ADMIN_FORBIDDEN"));

        // (A second user: reusing the first refresh token would be a replay and revoke that session.)
        String loginC = login("+77000000116");
        String admin = adminToken(loginC, "PARTNER_VERIFICATION");
        fetch("/api/v1/admin/partners", admin).andExpect(status().isOk());
        db.update("UPDATE identity.admin_grants SET revoked_at = now(), revoked_by_user_id = ? WHERE user_id = ? AND permission = 'PARTNER_VERIFICATION'",
                user(loginC), user(loginC));
        // Same token, still unexpired and still carrying kunde.admin: the per-request grant check refuses it.
        fetch("/api/v1/admin/partners", admin).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ADMIN_FORBIDDEN"));
    }

    @Test
    void capabilitiesReportOnlyCurrentGrantsOfTheAuthenticatedEmployee() throws Exception {
        String path = "/api/v1/admin/me/capabilities";
        http.perform(get(path)).andExpect(status().isUnauthorized());
        String employee = login("+77000000114");
        fetch(path, JsonPath.read(employee, "$.accessToken")).andExpect(status().isForbidden());

        String anotherEmployee = login("+77000000115");
        adminToken(anotherEmployee, "PARTNER_VERIFICATION");
        String token = adminToken(employee, "DELIVERY_OPERATIONS");
        fetch(path, token).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.permissions.length()").value(1))
                .andExpect(jsonPath("$.permissions[0]").value("DELIVERY_OPERATIONS"));

        UUID employeeId = user(employee);
        db.update("UPDATE identity.admin_grants SET revoked_at = now(), revoked_by_user_id = ? WHERE user_id = ?",
                employeeId, employeeId);
        fetch(path, token).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ADMIN_FORBIDDEN"));
    }

    @Test
    void directoryRequiresCurrentPlatformAccessManagerPermission() throws Exception {
        String path = "/api/v1/admin/employees";
        String ordinary = login("+77000000114");
        String reviewer = login("+77000000115");
        String manager = login("+77000000116");
        fetch(path, JsonPath.read(ordinary, "$.accessToken")).andExpect(status().isForbidden());
        String reviewerToken = adminToken(reviewer, "PARTNER_VERIFICATION");
        String managerToken = adminToken(manager, "ADMIN_GRANTS");
        fetch(path, reviewerToken).andExpect(status().isForbidden());
        fetch(path + "?limit=101", managerToken).andExpect(status().isBadRequest());

        var page = fetch(path + "?limit=1", managerToken).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.employees.length()").value(1))
                .andReturn().getResponse().getContentAsString();
        String cursor = JsonPath.read(page, "$.next");
        var last = fetch(path + "?limit=1&after=" + cursor, managerToken).andExpect(status().isOk())
                .andExpect(jsonPath("$.employees.length()").value(1))
                .andReturn().getResponse().getContentAsString();
        assertThat((String) JsonPath.read(last, "$.employees[0].id")).isNotEqualTo(cursor);
        var directory = fetch(path + "?limit=100", managerToken).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        List<String> employeeIds = JsonPath.read(directory, "$.employees[*].id");
        assertThat(employeeIds).contains(user(reviewer).toString(), user(manager).toString())
                .doesNotContain(user(ordinary).toString());

        UUID managerId = user(manager);
        db.update("update identity.admin_grants set revoked_at = now(), revoked_by_user_id = ? where user_id = ?",
                managerId, managerId);
        fetch(path, managerToken).andExpect(status().isForbidden());
    }

    @Test
    void scopedAssignmentsRequireAllResourceAttributesAndRevokeImmediately() throws Exception {
        String employeeLogin = login("+77000000114");
        String ownerLogin = login("+77000000115");
        UUID employee = user(employeeLogin);
        UUID owner = user(ownerLogin);
        UUID organization = apply(ownerLogin, "Scope Cafe");
        UUID otherOrganization = apply(login("+77000000116"), "Other Scope Cafe");
        UUID resource = UUID.randomUUID();
        db.update("INSERT INTO identity.admin_roles (code) VALUES ('delivery-operator')");
        db.update("""
                INSERT INTO identity.admin_role_permissions (role_code, permission)
                VALUES ('delivery-operator', 'DELIVERY_OPERATIONS')""");
        UUID assignment = db.queryForObject("""
                INSERT INTO identity.admin_role_assignments
                    (user_id, role_code, product_code, region_code, organization_id, resource_id, assigned_by)
                VALUES (?, 'delivery-operator', 'DELIVERY', 'ALMATY', ?, ?, ?)
                RETURNING id""", UUID.class, employee, organization, resource, owner);

        String token = refreshed(employeeLogin);
        String path = "/api/v1/admin/me/capabilities";
        fetch(path, token).andExpect(status().isOk()).andExpect(jsonPath("$.permissions").isEmpty());
        var correct = new Scope("DELIVERY", "ALMATY", organization, resource);
        grants.require(employee, Permission.DELIVERY_OPERATIONS, correct);

        for (var wrong : new Scope[] {
                new Scope("RIDES", "ALMATY", organization, resource),
                new Scope("DELIVERY", "ASTANA", organization, resource),
                new Scope("DELIVERY", "ALMATY", otherOrganization, resource),
                new Scope("DELIVERY", "ALMATY", organization, UUID.randomUUID()),
                new Scope("DELIVERY", "ALMATY", organization, null)
        }) {
            assertThatThrownBy(() -> grants.require(employee, Permission.DELIVERY_OPERATIONS, wrong))
                    .isInstanceOf(ApiException.class);
        }
        assertThatThrownBy(() -> grants.require(employee, Permission.DELIVERY_OPERATIONS))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> grants.require(employee, Permission.ADMIN_GRANTS, correct))
                .isInstanceOf(ApiException.class);
        db.update("UPDATE identity.admin_role_assignments SET revoked_at = now(), revoked_by = ? WHERE id = ?", owner, assignment);
        fetch(path, token).andExpect(status().isForbidden());
        assertThatThrownBy(() -> grants.require(employee, Permission.DELIVERY_OPERATIONS, correct))
                .isInstanceOf(ApiException.class);

        db.update("""
                INSERT INTO identity.admin_role_assignments
                    (user_id, role_code, assigned_by, assigned_at, expires_at)
                VALUES (?, 'delivery-operator', ?, now() - interval '2 hours', now() - interval '1 hour')""", employee, owner);
        fetch(path, token).andExpect(status().isForbidden());
    }

    @Test
    void decisionsAreVersionedValidatedAndAdminsCannotReviewTheirOwnPartner() throws Exception {
        String loginA = login("+77000000114");
        String loginAdmin = login("+77000000115");
        UUID partner = apply(loginA, "Decision Cafe");
        String admin = adminToken(loginAdmin, "PARTNER_VERIFICATION");
        String path = "/api/v1/admin/partners/" + partner + "/decision";

        send(path, admin, decide(partner, "REJECT", null, 0)).andExpect(status().isBadRequest());
        send(path, admin, "{\"decision\":\"EXPLODE\",\"version\":0}").andExpect(status().isBadRequest());
        send(path, admin, "{\"decision\":\"APPROVE\"}").andExpect(status().isBadRequest());
        send(path, admin, decide(partner, "RESUBMIT", null, 0)).andExpect(status().isForbidden());
        send(path, admin, decide(partner, "APPROVE", null, 5)).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        send(path, admin, decide(partner, "APPROVE", null, 0)).andExpect(status().isOk());
        send(path, admin, decide(partner, "APPROVE", null, 1)).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("INVALID_VERIFICATION_TRANSITION"));
        fetch("/api/v1/admin/partners?status=NOPE", admin).andExpect(status().isBadRequest());
        fetch("/api/v1/admin/partners?status=APPROVED", admin).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1));
        fetch("/api/v1/admin/partners?status=REJECTED", admin).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        UUID unknown = UUID.randomUUID();
        send("/api/v1/admin/partners/" + unknown + "/decision", admin, decide(unknown, "APPROVE", null, 0)).andExpect(status().isNotFound());
        fetch("/api/v1/admin/partners/" + unknown, admin).andExpect(status().isNotFound());

        // An administrator who is also staff of the partner may not decide on it.
        String loginC = login("+77000000116");
        UUID other = apply(loginC, "Conflict Cafe");
        String adminC = adminToken(loginC, "PARTNER_VERIFICATION");
        send("/api/v1/admin/partners/" + other + "/decision", adminC, decide(other, "APPROVE", null, 0))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("REVIEWER_FORBIDDEN"));
    }
}
