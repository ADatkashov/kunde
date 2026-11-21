package kz.kunde.admin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import kz.kunde.booking.BookingDemoSeeder;
import kz.kunde.platform.FeatureToggles;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/** Feature switches over HTTP against PostgreSQL: grant, environment ceiling, versioning, immediate effect, immutable journal. */
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000801,+77000000802,+77000000803,+77000000804",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FeatureTogglesApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired FeatureToggles toggles;

    String consumer;
    String admin;
    String otherAdmin;

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        var request = (switch (method) {
            case "GET" -> get(path);
            case "PUT" -> put(path);
            case "PATCH" -> patch(path);
            default -> post(path);
        }).contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}").andExpect(status().isOk()));
    }

    private static UUID subject(String loginBody) throws Exception {
        return UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    /** Owner-provisioned DEV admin: an out-of-band grant row, then a refresh so the token carries kunde.admin. */
    private String adminWith(String loginBody, String permission) throws Exception {
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, ?, 'synthetic DEV admin')", subject(loginBody), permission);
        return JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}")), "$.accessToken");
    }

    @BeforeEach
    void setUp() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 LIKE '+7700000080%'");
        consumer = JsonPath.read(loginBody("+77000000801"), "$.accessToken");
        admin = adminWith(loginBody("+77000000802"), "ADMIN_GRANTS");
        otherAdmin = adminWith(loginBody("+77000000803"), "AUTO_OPERATIONS");
        toggles.invalidate();
    }

    @AfterEach
    void tearDown() {
        toggles.invalidate(); // the transaction rolls back the switches; never leave a stale cache for the next test
    }

    @Test
    void healthSwitchBlocksPublicIntakeAndLeavesOwnHistoryAvailable() throws Exception {
        send("GET", "/api/v1/booking/health/venues", null, null).andExpect(status().isOk());
        send("GET", "/api/v1/admin/health", consumer, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/admin/health", otherAdmin, null).andExpect(status().isForbidden());
        send("PUT", "/api/v1/admin/features/HEALTH", admin,
                "{\"enabled\":false,\"reason\":\"pause synthetic intake\"}").andExpect(status().isOk());
        send("GET", "/api/v1/capabilities", null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.healthEnabled").value(false));
        send("GET", "/api/v1/booking/health/venues", null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/booking/bookings?healthOnly=true", consumer, null).andExpect(status().isOk());
    }

    @Test
    void healthOperatorCanModerateWithAuditButCannotSwitchIntake() throws Exception {
        try (var in = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
        UUID venueId = db.queryForObject(
                "select id from marketplace.booking_venues where slug = 'health-demo-clinic'", UUID.class);
        String session = loginBody("+77000000804");
        String operator = adminWith(session, "HEALTH_OPERATIONS");
        String moderation = "/api/v1/admin/health/venues/" + venueId;
        String hide = "{\"published\":false}";

        send("GET", "/api/v1/admin/health", operator, null).andExpect(status().isOk());
        send("PATCH", moderation, otherAdmin, hide).andExpect(status().isForbidden());
        send("PUT", "/api/v1/admin/features/HEALTH", operator,
                "{\"enabled\":false,\"reason\":\"insufficient scope\"}").andExpect(status().isForbidden());
        send("GET", "/api/v1/booking/venues/" + venueId, null, null).andExpect(status().isOk());
        send("PATCH", moderation, operator, hide).andExpect(status().isNoContent());
        send("PATCH", moderation, operator, hide).andExpect(status().isNoContent());
        send("GET", "/api/v1/booking/venues/" + venueId, null, null).andExpect(status().isNotFound());

        assertThat(db.queryForList("""
                select admin_user_id from marketplace.health_moderation_events
                where venue_id = ? and not published
                """, UUID.class, venueId)).containsExactly(subject(session));
    }

    @Test
    void onlyTheAdminGrantHolderCanSeeAndSwitchFeatures() throws Exception {
        send("GET", "/api/v1/admin/features", null, null).andExpect(status().isUnauthorized());
        send("GET", "/api/v1/admin/features", consumer, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/admin/features", otherAdmin, null).andExpect(status().isForbidden());
        send("PUT", "/api/v1/admin/features/AUTO", otherAdmin, "{\"enabled\":false,\"reason\":\"no grant\"}").andExpect(status().isForbidden());
        assertThat(toggles.enabled(FeatureToggles.Feature.AUTO)).isTrue();

        send("GET", "/api/v1/admin/features", admin, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(7))
                .andExpect(jsonPath("$[?(@.feature=='LEISURE')].effective").value(true))
                .andExpect(jsonPath("$[?(@.feature=='HEALTH')].effective").value(true))
                .andExpect(jsonPath("$[?(@.feature=='EDUCATION')].effective").value(true))
                .andExpect(jsonPath("$[?(@.feature=='AUTO')].effective").value(true))
                .andExpect(jsonPath("$[?(@.feature=='AUTO')].allowedByEnvironment").value(true))
                .andExpect(jsonPath("$[?(@.feature=='RIDES')].allowedByEnvironment").value(false))
                .andExpect(jsonPath("$[?(@.feature=='RIDES')].effective").value(false))
                .andExpect(jsonPath("$[?(@.feature=='DELIVERY')].effective").value(false));
    }

    @Test
    void switchingAutoOffAndOnTakesEffectAtOnceAndIsVersionedAndJournaled() throws Exception {
        send("GET", "/api/v1/capabilities", null, null).andExpect(jsonPath("$.autoEnabled").value(true));
        send("GET", "/api/v1/auto/categories", null, null).andExpect(jsonPath("$.length()").value(8));

        send("PUT", "/api/v1/admin/features/AUTO", admin, "{\"enabled\":false,\"reason\":\"плановая остановка\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.effective").value(false))
                .andExpect(jsonPath("$.enabled").value(false)).andExpect(jsonPath("$.version").value(1));
        send("GET", "/api/v1/capabilities", null, null).andExpect(jsonPath("$.autoEnabled").value(false));
        send("GET", "/api/v1/auto/categories", null, null).andExpect(jsonPath("$.length()").value(0)); // no new business while off

        // a stale version is refused, the current one is accepted
        send("PUT", "/api/v1/admin/features/auto", admin, "{\"enabled\":true,\"reason\":\"stale\",\"version\":7}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        send("PUT", "/api/v1/admin/features/AUTO", admin, "{\"enabled\":true,\"reason\":\"работы завершены\",\"version\":1}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.effective").value(true)).andExpect(jsonPath("$.version").value(2));
        send("GET", "/api/v1/capabilities", null, null).andExpect(jsonPath("$.autoEnabled").value(true));
        send("GET", "/api/v1/auto/categories", null, null).andExpect(jsonPath("$.length()").value(8));

        assertThat(db.queryForObject("select count(*) from identity.feature_toggle_events where feature = 'AUTO'", Integer.class)).isEqualTo(2);
        assertThat(db.queryForObject("select reason from identity.feature_toggle_events where feature = 'AUTO' order by id desc limit 1", String.class))
                .isEqualTo("работы завершены");
        assertThatThrownBy(() -> db.update("update identity.feature_toggle_events set reason = 'tampered'"))
                .hasMessageContaining("append-only");
    }

    @Test
    void theEnvironmentRemainsTheCeilingAndInputIsValidated() throws Exception {
        // Rides is not allowed by this environment: an administrator cannot switch it on
        send("PUT", "/api/v1/admin/features/RIDES", admin, "{\"enabled\":true,\"reason\":\"try to enable\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("FEATURE_NOT_ALLOWED_BY_ENVIRONMENT"));
        send("PUT", "/api/v1/admin/features/DELIVERY", admin, "{\"enabled\":true,\"reason\":\"try to enable\"}")
                .andExpect(status().isConflict());
        send("PUT", "/api/v1/admin/features/AUTO", admin, "{\"enabled\":false,\"reason\":\"x\"}")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("REASON_REQUIRED"));
        send("PUT", "/api/v1/admin/features/AUTO", admin, "{\"reason\":\"no flag value\"}").andExpect(status().isBadRequest());
        send("PUT", "/api/v1/admin/features/TAXI", admin, "{\"enabled\":false,\"reason\":\"unknown\"}")
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("FEATURE_NOT_FOUND"));
        assertThat(db.queryForObject("select count(*) from identity.feature_toggles", Integer.class)).isZero();
    }
}
