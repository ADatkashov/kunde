package kz.kunde.rides;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.environment=test", "app.identity.consumer-enabled=true", "app.auth.phone.enabled=true",
        "app.rides.enabled=true", "app.rides.consumer-enabled=true"
})
@AutoConfigureMockMvc
@Transactional
class RideOperationsIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired RideRequestService rides;
    @Autowired MockMvc http;

    @DynamicPropertySource
    static void authSecret(DynamicPropertyRegistry registry) {
        String entropy = UUID.randomUUID().toString() + UUID.randomUUID();
        registry.add("app.auth.phone.secret", () -> entropy);
    }

    @Test
    void linksOnlyOwnedRidesAndResolvesThroughTheOperationsGrant() throws Exception {
        UUID rider = session("complaint-rider");
        session("complaint-stranger");
        UUID admin = session("complaint-operator");
        UUID quote = db.queryForObject("""
                insert into transactions.ride_fare_quotes (user_id, ride_class, tariff_version, estimate_kzt,
                    distance_meters, duration_seconds, pickup_latitude, pickup_longitude, destination_latitude,
                    destination_longitude, expires_at)
                values (?, 'ECONOMY', 'test', 800, 1000, 180, 43.2, 77, 43.25, 77.1, now() + interval '2 minutes')
                returning id
                """, UUID.class, rider);
        UUID ride = rides.create(rider, quote, UUID.randomUUID().toString()).ride().id();
        String payload = "{\"category\":\"GENERAL\",\"message\":\"Synthetic report\",\"rideId\":\"" + ride + "\"}";
        String key = UUID.randomUUID().toString();
        http.perform(post("/api/v1/me/support/cases").with(client("complaint-stranger", false))
                        .contentType(MediaType.APPLICATION_JSON).header("Idempotency-Key", key).content(payload))
                .andExpect(status().isNotFound());
        String result = http.perform(post("/api/v1/me/support/cases").with(client("complaint-rider", false))
                        .contentType(MediaType.APPLICATION_JSON).header("Idempotency-Key", key).content(payload))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String complaint = JsonPath.read(result, "$.id");
        String resolve = "/api/v1/admin/rides/complaints/" + complaint + "/resolve";
        http.perform(post(resolve).with(client("complaint-operator", true))).andExpect(status().isForbidden());

        db.update("insert into identity.admin_grants (user_id, permission, reason) values (?, 'RIDE_OPERATIONS', 'test')", admin);
        http.perform(get("/api/v1/admin/rides/trips").with(client("complaint-operator", true)))
                .andExpect(status().isOk());
        http.perform(post(resolve).with(client("complaint-operator", true)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("RESOLVED"));
        http.perform(post(resolve).with(client("complaint-operator", true))).andExpect(status().isOk());
        http.perform(get("/api/v1/admin/rides/complaints/" + complaint + "/audit").with(client("complaint-operator", true)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[1].actorId").value(admin.toString()));
    }

    private UUID session(String subject) {
        UUID id = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        db.update("insert into identity.external_bindings (issuer, subject, user_id) values ('https://identity.example.test', ?, ?)",
                subject, id);
        db.update("insert into profile.consumer_profiles (user_id) values (?)", id);
        return id;
    }

    private static RequestPostProcessor client(String subject, boolean administrator) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer")
                .claim("scope", administrator ? "kunde.consumer kunde.admin" : "kunde.consumer"));
    }
}
