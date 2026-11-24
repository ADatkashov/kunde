package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * On-site Auto jobs and the AUTO_SPECIALIST executor over HTTP against PostgreSQL: enrollment, admin approval per category,
 * availability, privacy of location, atomic accept, lifecycle with price approval, cancellation, isolation, admin audit, flag.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.auto.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000601,+77000000602,+77000000603,+77000000604,+77000000605",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class AutoJobApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    String customer;
    String other;
    String specA;
    String specB;
    String admin;
    UUID specAId;
    UUID specBId;
    String car;

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
            case "PUT" -> put(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (key != null) { request.header("Idempotency-Key", key); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk()));
    }

    private static UUID subject(String loginBody) throws Exception {
        return UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    @BeforeEach
    void setUp() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 LIKE '+7700000060%'");
        String c = loginBody("+77000000601");
        customer = JsonPath.read(c, "$.accessToken");
        other = JsonPath.read(loginBody("+77000000602"), "$.accessToken");
        String a = loginBody("+77000000603");
        specA = JsonPath.read(a, "$.accessToken");
        specAId = subject(a);
        String b = loginBody("+77000000604");
        specB = JsonPath.read(b, "$.accessToken");
        specBId = subject(b);
        String ad = loginBody("+77000000605");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'AUTO_OPERATIONS', 'synthetic DEV admin')", subject(ad));
        admin = JsonPath.read(send("POST", "/api/v1/auth/token/refresh", null, "{\"refreshToken\":\"" + JsonPath.read(ad, "$.refreshToken") + "\"}", null)
                .andReturn().getResponse().getContentAsString(), "$.accessToken");
        car = JsonPath.read(body(send("POST", "/api/v1/auto/vehicles", customer, "{\"make\":\"Toyota\",\"model\":\"Camry\",\"year\":2018}", null)), "$.id");
    }

    private void approve(String token, UUID id, String categories) throws Exception {
        send("POST", "/api/v1/admin/auto/specialists/" + id + "/decision", admin, "{\"approve\":true,\"categories\":" + categories + ",\"reason\":\"Документы проверены\"}", null)
                .andExpect(status().isOk());
        send("PUT", "/api/v1/executor/auto/availability", token, "{\"online\":true}", null).andExpect(status().isOk());
        send("PUT", "/api/v1/executor/auto/location", token, "{\"latitude\":43.2389,\"longitude\":76.8897}", null).andExpect(status().isNoContent());
    }

    private String request(String token, String vehicle, String key) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/auto/jobs", token, "{\"vehicleId\":\"" + vehicle + "\",\"category\":\"ROADSIDE\",\"description\":\"Не заводится\","
                + "\"addressText\":\"Алматы, ул. Тестовая 5\",\"latitude\":43.25,\"longitude\":76.9}", key).andExpect(status().isCreated())), "$.id");
    }

    @Test
    void enrollmentAndApprovalAreExplicitPerCategoryAndAudited() throws Exception {
        send("GET", "/api/v1/executor/auto/profile", specA, null, null).andExpect(status().isNotFound());
        send("POST", "/api/v1/executor/auto/profile", specA, "{\"name\":\"Тест Специалист\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"));
        send("POST", "/api/v1/executor/auto/profile", specA, "{\"name\":\"Тест Специалист\"}", null).andExpect(status().isOk()); // idempotent
        send("POST", "/api/v1/executor/auto/profile", specA, "{\"name\":\"Другое имя\"}", null).andExpect(status().isConflict());
        // pending cannot go online
        send("PUT", "/api/v1/executor/auto/availability", specA, "{\"online\":true}", null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SPECIALIST_NOT_APPROVED"));
        // admin rules
        send("GET", "/api/v1/admin/auto/specialists", customer, null, null).andExpect(status().isForbidden());
        send("POST", "/api/v1/admin/auto/specialists/" + specAId + "/decision", admin, "{\"approve\":true,\"categories\":[\"CAR_WASH\"],\"reason\":\"x\"}", null)
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("CATEGORY_NOT_MOBILE"));
        send("POST", "/api/v1/admin/auto/specialists/" + specAId + "/decision", admin, "{\"approve\":true,\"categories\":[],\"reason\":\"x\"}", null)
                .andExpect(status().isBadRequest());
        send("GET", "/api/v1/admin/auto/specialists", admin, null, null).andExpect(status().isOk()).andExpect(jsonPath("$[0].status").value("PENDING"));
        approve(specA, specAId, "[\"ROADSIDE\"]");
        assertThat(db.queryForObject("select count(*) from transactions.auto_specialist_reviews where specialist_id = ?", Integer.class, specAId)).isEqualTo(1);
        // blocking clears online state and permissions
        send("POST", "/api/v1/admin/auto/specialists/" + specAId + "/decision", admin, "{\"approve\":false,\"reason\":\"Жалоба\"}", null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("BLOCKED")).andExpect(jsonPath("$.online").value(false));
        assertThat(db.queryForObject("select count(*) from transactions.auto_specialist_categories where user_id = ?", Integer.class, specAId)).isZero();
        send("PUT", "/api/v1/executor/auto/availability", specA, "{\"online\":true}", null).andExpect(status().isConflict());
        // the audit trail is append-only
        org.junit.jupiter.api.Assertions.assertThrows(org.springframework.dao.DataAccessException.class,
                () -> db.update("delete from transactions.auto_specialist_reviews"));
    }

    @Test
    void selfReviewIsForbidden() throws Exception {
        String adLogin = loginBody("+77000000605");
        UUID adminId = subject(adLogin);
        db.update("insert into transactions.auto_specialists (user_id, display_name) values (?, 'Админ')", adminId);
        send("POST", "/api/v1/admin/auto/specialists/" + adminId + "/decision", admin, "{\"approve\":true,\"categories\":[\"ROADSIDE\"],\"reason\":\"x\"}", null)
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("SELF_REVIEW"));
    }

    @Test
    void roadsideJobLifecycleWithPrivacyPriceApprovalAndIsolation() throws Exception {
        send("POST", "/api/v1/executor/auto/profile", specA, "{\"name\":\"Специалист А\"}", null).andExpect(status().isOk());
        approve(specA, specAId, "[\"ROADSIDE\"]");
        String key = "job-request-key-000001";
        String job = request(customer, car, key);
        // idempotent replay, active-car guard, ownership
        assertThat((String) JsonPath.read(body(send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"description\":\"Не заводится\","
                + "\"addressText\":\"Алматы, ул. Тестовая 5\",\"latitude\":43.25,\"longitude\":76.9}", key).andExpect(status().isCreated())), "$.id")).isEqualTo(job);
        assertThat(db.queryForObject("select count(*) from transactions.auto_jobs", Integer.class)).isEqualTo(1);
        send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Другая 1\",\"latitude\":43.25,\"longitude\":76.9}",
                "job-request-key-000002").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("JOB_ALREADY_ACTIVE"));
        send("POST", "/api/v1/auto/jobs", other, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Другая 1\",\"latitude\":43.25,\"longitude\":76.9}",
                "job-request-key-000003").andExpect(status().isNotFound());
        send("GET", "/api/v1/auto/jobs/" + job, other, null, null).andExpect(status().isNotFound());
        // the specialist sees an approximate list without address or coordinates
        String open = body(send("GET", "/api/v1/executor/auto/jobs/available", specA, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(open, "$")).hasSize(1);
        assertThat(open).doesNotContain("Тестовая").doesNotContain("43.25").doesNotContain("76.9\"").contains("\"distanceKm\"");
        send("GET", "/api/v1/executor/auto/jobs/available", customer, null, null).andExpect(status().isNotFound());
        // accept: exact location only after assignment
        String accepted = body(send("POST", "/api/v1/executor/auto/jobs/" + job + "/accept", specA, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(accepted, "$.addressText")).contains("Тестовая");
        assertThat((List<String>) JsonPath.read(accepted, "$.allowedActions")).containsExactly("ARRIVE", "RELEASE");
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/accept", specA, null, null).andExpect(status().isOk()); // idempotent
        assertThat((String) JsonPath.read(body(send("GET", "/api/v1/auto/jobs/" + job, customer, null, null)), "$.specialist")).isEqualTo("Специалист А");
        // another specialist cannot touch it
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specB, "{\"action\":\"ARRIVE\"}", null).andExpect(status().isNotFound());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"START\"}", null).andExpect(status().isConflict());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"ARRIVE\"}", null).andExpect(status().isOk());
        send("POST", "/api/v1/auto/jobs/" + job + "/cancel", customer, null, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("JOB_NOT_CANCELLABLE"));
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"START\"}", null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"PROPOSE_PRICE\",\"finalPriceMinor\":2500000}", null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"COMPLETE\"}", null).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PRICE_APPROVAL_PENDING"));
        send("POST", "/api/v1/auto/jobs/" + job + "/price-decision", other, "{\"approve\":true}", null).andExpect(status().isNotFound());
        send("POST", "/api/v1/auto/jobs/" + job + "/price-decision", customer, "{\"approve\":true}", null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"COMPLETE\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        String done = body(send("GET", "/api/v1/auto/jobs/" + job, customer, null, null));
        assertThat((Integer) JsonPath.read(done, "$.finalPriceMinor")).isEqualTo(2500000);
        assertThat((Integer) JsonPath.read(done, "$.priceMinor")).isEqualTo(1500000);
        assertThat((List<String>) JsonPath.read(done, "$.timeline[*].status")).containsSubsequence("REQUESTED", "ASSIGNED", "ARRIVED", "IN_PROGRESS", "COMPLETED");
        // monitoring for the administrator
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/admin/auto/jobs?status=COMPLETED", admin, null, null).andExpect(status().isOk())), "$")).hasSize(1);
        // the finished car can be requested again
        request(customer, car, "job-request-key-000004");
    }

    @Test
    void acceptIsAtomicPermissionsAreEnforcedAndRequestsCanBeReleasedOrCancelled() throws Exception {
        send("POST", "/api/v1/executor/auto/profile", specA, "{\"name\":\"Специалист А\"}", null);
        send("POST", "/api/v1/executor/auto/profile", specB, "{\"name\":\"Специалист Б\"}", null);
        approve(specA, specAId, "[\"ROADSIDE\"]");
        // B is approved for the category list of its own: none of the mobile categories besides ROADSIDE exist, so approve B then drop the permission
        approve(specB, specBId, "[\"ROADSIDE\"]");
        String job = request(customer, car, "job-request-key-000011");
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/accept", specA, null, null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/accept", specB, null, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("JOB_TAKEN"));
        // release returns the job to the pool, the other specialist may take it
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", specA, "{\"action\":\"RELEASE\"}", null).andExpect(status().isOk());
        assertThat((String) JsonPath.read(body(send("GET", "/api/v1/auto/jobs/" + job, customer, null, null)), "$.status")).isEqualTo("REQUESTED");
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/accept", specB, null, null).andExpect(status().isOk());
        // a specialist with an active job cannot take a second one
        String car2 = JsonPath.read(body(send("POST", "/api/v1/auto/vehicles", other, "{\"make\":\"Kia\",\"model\":\"Rio\",\"year\":2012}", null)), "$.id");
        String second = request(other, car2, "job-request-key-000012");
        send("POST", "/api/v1/executor/auto/jobs/" + second + "/accept", specB, null, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SPECIALIST_BUSY"));
        // a permission removed by an administrator stops accepting
        db.update("delete from transactions.auto_specialist_categories where user_id = ?", specAId);
        send("POST", "/api/v1/executor/auto/jobs/" + second + "/accept", specA, null, null).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("CATEGORY_NOT_PERMITTED"));
        // customer cancels before arrival; the specialist is freed
        send("POST", "/api/v1/auto/jobs/" + job + "/cancel", customer, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        send("POST", "/api/v1/auto/jobs/" + job + "/cancel", customer, null, null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/auto/jobs/" + second + "/accept", specB, null, null).andExpect(status().isOk());
        // an unapproved user cannot accept at all
        send("POST", "/api/v1/executor/auto/jobs/" + second + "/accept", other, null, null).andExpect(status().isNotFound());
    }

    @Test
    void invalidRequestsAndTheFlagDisabledCategoryAreRefused() throws Exception {
        send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Тестовая 5\",\"latitude\":43.25,\"longitude\":76.9}", null)
                .andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"addressText\":\"x\",\"latitude\":43.25,\"longitude\":76.9}", "job-request-key-000021")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("ADDRESS_REQUIRED"));
        send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Тестовая 5\",\"latitude\":143.25,\"longitude\":76.9}",
                "job-request-key-000022").andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"CAR_WASH\",\"addressText\":\"Алматы, ул. Тестовая 5\",\"latitude\":43.25,\"longitude\":76.9}",
                "job-request-key-000023").andExpect(status().isConflict());
        send("PATCH", "/api/v1/admin/auto/categories/ROADSIDE", admin, "{\"enabled\":false}", null);
        db.update("update marketplace.auto_service_categories set enabled = false where code = 'ROADSIDE'");
        send("POST", "/api/v1/auto/jobs", customer, "{\"vehicleId\":\"" + car + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Тестовая 5\",\"latitude\":43.25,\"longitude\":76.9}",
                "job-request-key-000024").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("AUTO_CATEGORY_DISABLED"));
    }
}
