package kz.kunde.rides;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
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
        "app.rides.synthetic-routing-enabled=true",
        "app.rides.consumer-enabled=true",
        "app.rides.executor-enabled=true",
        "app.rides.dispatch-enabled=true",
        "app.rides.pricing.tariffs.economy.version=test-v1",
        "app.rides.pricing.tariffs.economy.base-kzt=200",
        "app.rides.pricing.tariffs.economy.per-kilometer-kzt=80",
        "app.rides.pricing.tariffs.economy.per-minute-kzt=10",
        "app.rides.pricing.tariffs.economy.minimum-kzt=400",
        "app.rides.pricing.tariffs.economy.fixed-fee-kzt=0"
})
@AutoConfigureMockMvc
@Transactional
class RideQuoteApiIntegrationTest {
    private static final String QUOTE = """
            {"rideClass":"ECONOMY","pickup":{"latitude":43.24,"longitude":76.92},
             "destination":{"latitude":43.25,"longitude":76.94}}
            """;

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @Test
    void issuesServerPricedQuoteAndOnlyOwnerCanUseIt() throws Exception {
        var response = http.perform(post("/api/v1/rides/quotes").with(customer("quote-owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.estimateKzt").value(500))
                .andExpect(jsonPath("$.tariffVersion").value("test-v1"))
                .andExpect(jsonPath("$.synthetic").value(true))
                .andReturn().getResponse().getContentAsString();
        String quoteId = JsonPath.read(response, "$.id");
        String requestKey = UUID.randomUUID().toString();
        var request = "{\"quoteId\":\"" + quoteId + "\"}";

        http.perform(post("/api/v1/rides").with(customer("another-customer"))
                        .header("Idempotency-Key", requestKey).contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isConflict());
        http.perform(post("/api/v1/rides").with(customer("quote-owner"))
                        .header("Idempotency-Key", requestKey).contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.estimateKzt").value(500));
    }

    @Test
    void rejectsUnconfiguredTariffAndUnknownRoute() throws Exception {
        http.perform(post("/api/v1/rides/quotes").with(customer("quote-owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE.replace("ECONOMY", "BUSINESS")))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("RIDE_CLASS_UNAVAILABLE"));
        http.perform(post("/api/v1/rides/quotes").with(customer("quote-owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE.replace("43.25", "42.25")))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("RIDE_ROUTE_NOT_FOUND"));
    }

    @Test
    void consumesQuoteMatchesApprovedExecutorAndCompletesRide() throws Exception {
        var driverJwt = customer("dispatch-driver");
        var passengerJwt = customer("dispatch-passenger");
        var adminJwt = jwt().jwt(token -> token.issuer("https://identity.example.test").subject("dispatch-reviewer")
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer kunde.admin"));
        var admin = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        db.update("insert into identity.external_bindings (issuer, subject, user_id) values (?, ?, ?)",
                "https://identity.example.test", "dispatch-reviewer", admin);
        db.update("insert into profile.consumer_profiles (user_id) values (?)", admin);
        db.update("""
                insert into identity.admin_grants (user_id, permission, reason) values (?, 'RIDE_VERIFICATION', 'test')
                """, admin);
        String base = "/api/v1/executor/rides";
        var driver = http.perform(post(base + "/profile").with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"Synthetic Driver\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"))
                .andReturn().getResponse().getContentAsString();
        String driverId = JsonPath.read(driver, "$.userId");
        var vehicle = http.perform(post(base + "/vehicle").with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"description\":\"Synthetic vehicle\",\"plate\":\"TEST23\",\"rideClass\":\"ECONOMY\"}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String vehicleId = JsonPath.read(vehicle, "$.vehicle.id");
        var approval = "/api/v1/admin/rides/drivers/" + driverId + "/decision";
        http.perform(post(approval).with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"decision\":\"APPROVED\"}")).andExpect(status().isForbidden());
        http.perform(post(approval).with(adminJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"decision\":\"APPROVED\"}")).andExpect(status().isOk());
        http.perform(put(base + "/availability").with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"online\":true}")).andExpect(status().isConflict());
        http.perform(post(approval).with(adminJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"decision\":\"APPROVED\",\"vehicleId\":\"" + vehicleId + "\"}")).andExpect(status().isOk());
        http.perform(put(base + "/availability").with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"online\":true}")).andExpect(status().isOk());
        http.perform(put(base + "/location").with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"latitude\":43.24,\"longitude\":76.92}")).andExpect(status().isNoContent());

        String quote = http.perform(post("/api/v1/rides/quotes").with(passengerJwt)
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String quoteId = JsonPath.read(quote, "$.id");
        String created = http.perform(post("/api/v1/rides").with(passengerJwt)
                        .contentType(MediaType.APPLICATION_JSON).header("Idempotency-Key", UUID.randomUUID().toString())
                        .content("{\"quoteId\":\"" + quoteId + "\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String rideId = JsonPath.read(created, "$.id");
        http.perform(post("/api/v1/rides/" + rideId + "/dispatch").with(passengerJwt))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SEARCHING_DRIVER"));
        String offers = http.perform(get(base + "/offers").with(driverJwt))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].rideId").value(rideId))
                .andReturn().getResponse().getContentAsString();
        String offerId = JsonPath.read(offers, "$[0].id");
        var accept = base + "/offers/" + offerId + "/response";
        http.perform(post(accept).with(passengerJwt).contentType(MediaType.APPLICATION_JSON)
                .content("{\"accept\":true}")).andExpect(status().isNotFound());
        http.perform(post(accept).with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                .content("{\"accept\":true}")).andExpect(status().isNoContent());
        http.perform(post(accept).with(driverJwt).contentType(MediaType.APPLICATION_JSON)
                .content("{\"accept\":true}")).andExpect(status().isNoContent());

        String location = "/api/v1/rides/" + rideId + "/location";
        http.perform(get(location).with(customer("stranger"))).andExpect(status().isNotFound());
        http.perform(get(location).with(passengerJwt))
                .andExpect(status().isOk()).andExpect(jsonPath("$.point.latitude").value(43.24));

        for (String step : new String[] {"DEPART", "ARRIVE", "START", "COMPLETE"}) {
            http.perform(post(base + "/trips/" + rideId + "/progress").with(driverJwt)
                    .contentType(MediaType.APPLICATION_JSON).content("{\"step\":\"" + step + "\"}"))
                    .andExpect(status().isNoContent());
        }
        http.perform(get("/api/v1/rides").with(passengerJwt))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].status").value("COMPLETED"));
        http.perform(get(location).with(passengerJwt)).andExpect(status().isNoContent());
        http.perform(get(base + "/trips").with(driverJwt))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].status").value("COMPLETED"));
    }

    @Test
    void endsSearchWithoutAnAvailableDriver() throws Exception {
        var passenger = customer("timeout-passenger");
        String quote = http.perform(post("/api/v1/rides/quotes").with(passenger)
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String quoteId = JsonPath.read(quote, "$.id");
        String created = http.perform(post("/api/v1/rides").with(passenger)
                        .contentType(MediaType.APPLICATION_JSON).header("Idempotency-Key", UUID.randomUUID().toString())
                        .content("{\"quoteId\":\"" + quoteId + "\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String ride = JsonPath.read(created, "$.id");
        var search = post("/api/v1/rides/" + ride + "/dispatch").with(passenger);
        http.perform(search).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SEARCHING_DRIVER"));
        db.update("update transactions.rides set search_started_at = statement_timestamp() - interval '3 minutes' where id = ?",
                UUID.fromString(ride));
        http.perform(search).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("NO_DRIVER_AVAILABLE"));
    }

    private static RequestPostProcessor customer(String subject) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer"));
    }

}
