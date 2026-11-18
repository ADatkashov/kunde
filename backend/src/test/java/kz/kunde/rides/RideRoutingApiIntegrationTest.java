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
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-rides-only-for-integration-tests",
        "app.rides.enabled=true",
        "app.rides.consumer-enabled=true"
})
@AutoConfigureMockMvc
class RideRoutingApiIntegrationTest {
    private static final String PREVIEW = "/api/v1/rides/route-preview";
    private static final String ROUTE = """
            {"pickup":{"latitude":43.24,"longitude":76.92},"destination":{"latitude":43.25,"longitude":76.94}}
            """;

    @Autowired
    MockMvc http;

    @Autowired
    JdbcTemplate db;

    @Test
    void rejectsAnonymousAndWrongClient() throws Exception {
        http.perform(post(PREVIEW).contentType(MediaType.APPLICATION_JSON).content(ROUTE))
                .andExpect(status().isUnauthorized());
        http.perform(post(PREVIEW).with(client("other-client")).contentType(MediaType.APPLICATION_JSON).content(ROUTE))
                .andExpect(status().isForbidden());
    }

    @Test
    void validatesCoordinatesAndReportsUnconfiguredProvider() throws Exception {
        http.perform(post(PREVIEW).with(client("kunde-consumer")).contentType(MediaType.APPLICATION_JSON)
                        .content(ROUTE.replace("43.24", "91")))
                .andExpect(status().isBadRequest());
        http.perform(post(PREVIEW).with(client("kunde-consumer")).contentType(MediaType.APPLICATION_JSON).content(ROUTE))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("RIDES_ROUTING_UNAVAILABLE"));
        http.perform(post("/api/v1/rides/address-search").with(client("kunde-consumer"))
                        .contentType(MediaType.APPLICATION_JSON).content("""
                                {"query":"Алматы","language":"ru"}
                                """))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("RIDES_ROUTING_UNAVAILABLE"));
    }

    @Test
    @Transactional
    void createsFromAnOwnedQuoteAndReturnsTheSameRideOnRetry() throws Exception {
        UUID user = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        db.update("insert into identity.external_bindings (issuer, subject, user_id) values (?, ?, ?)",
                "https://identity.example.test", "synthetic-rider", user);
        db.update("insert into profile.consumer_profiles (user_id) values (?)", user);
        UUID quote = db.queryForObject("""
                insert into transactions.ride_fare_quotes (user_id, ride_class, tariff_version, estimate_kzt,
                    distance_meters, duration_seconds, pickup_latitude, pickup_longitude,
                    destination_latitude, destination_longitude, expires_at)
                values (?, 'ECONOMY', 'test', 800.00, 3000, 360, 43.24, 76.92, 43.25, 76.94,
                    now() + interval '1 minute') returning id
                """, UUID.class, user);
        String body = "{\"quoteId\":\"" + quote + "\"}";
        var request = post("/api/v1/rides").with(client("kunde-consumer")).contentType(MediaType.APPLICATION_JSON)
                .header("Idempotency-Key", "http-test-key-0001").content(body);
        String created = http.perform(request).andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("REQUESTED")).andReturn().getResponse().getContentAsString();
        String rideId = JsonPath.read(created, "$.id");
        http.perform(request).andExpect(status().isOk()).andExpect(jsonPath("$.id").value(rideId));
        http.perform(get("/api/v1/rides").with(client("kunde-consumer")))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].id").value(rideId));
        http.perform(post("/api/v1/rides/" + rideId + "/cancel").with(client("kunde-consumer")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED_BY_CUSTOMER"));
    }

    private static RequestPostProcessor client(String clientId) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject("synthetic-rider")
                .claim("typ", "Bearer").claim("azp", clientId).claim("scope", "kunde.consumer"));
    }
}
