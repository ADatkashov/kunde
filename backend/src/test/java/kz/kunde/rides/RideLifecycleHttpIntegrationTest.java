package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

/**
 * Backend end-to-end lifecycle of a Rides trip over the real HTTP layer, real PostgreSQL and real Flyway migrations:
 * Consumer and Executor are two independent identities that only interact through the API. Synthetic routing, no payments.
 * Commits are real (no test transaction) so that concurrent requests exercise the actual row locks.
 */
@SpringBootTest(properties = {
        "app.environment=test", "app.identity.consumer-enabled=true", "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-rides-lifecycle-only-for-integration-tests",
        "app.rides.enabled=true", "app.rides.synthetic-routing-enabled=true", "app.rides.consumer-enabled=true",
        "app.rides.executor-enabled=true", "app.rides.dispatch-enabled=true",
        "app.rides.pricing.tariffs.economy.version=test-v1", "app.rides.pricing.tariffs.economy.base-kzt=200",
        "app.rides.pricing.tariffs.economy.per-kilometer-kzt=80", "app.rides.pricing.tariffs.economy.per-minute-kzt=10",
        "app.rides.pricing.tariffs.economy.minimum-kzt=400", "app.rides.pricing.tariffs.economy.fixed-fee-kzt=0"
})
@AutoConfigureMockMvc
class RideLifecycleHttpIntegrationTest {
    private static final String QUOTE = """
            {"rideClass":"ECONOMY","pickup":{"latitude":43.24,"longitude":76.92},
             "destination":{"latitude":43.25,"longitude":76.94}}
            """;
    private static final String POSITION = "{\"latitude\":43.2401,\"longitude\":76.9201}";

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void isolateFromOtherTests() {
        db.update("update transactions.ride_drivers set online = false, latitude = null, longitude = null, observed_at = null");
    }

    @Test
    void fullTripFromQuoteToRatingWithSecurityAndStateChecks() throws Exception {
        String rider = newUser("rider"), stranger = newUser("stranger"), driver = newUser("driver"), operator = newUser("operator");
        approvedOnlineDriver(driver, operator);

        // Quote, server-side price, double tap on "Order" is idempotent
        String quote = JsonPath.read(call(post("/api/v1/rides/quotes"), rider, QUOTE)
                .andExpect(status().isCreated()).andExpect(jsonPath("$.estimateKzt").value(500))
                .andReturn().getResponse().getContentAsString(), "$.id");
        String key = UUID.randomUUID().toString();
        String body = "{\"quoteId\":\"" + quote + "\"}";
        String ride = JsonPath.read(call(post("/api/v1/rides").header("Idempotency-Key", key), rider, body)
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("REQUESTED"))
                .andReturn().getResponse().getContentAsString(), "$.id");
        call(post("/api/v1/rides").header("Idempotency-Key", key), rider, body)
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(ride));
        // A second ride while one is active is refused
        String quote2 = JsonPath.read(call(post("/api/v1/rides/quotes"), rider, QUOTE)
                .andReturn().getResponse().getContentAsString(), "$.id");
        call(post("/api/v1/rides").header("Idempotency-Key", UUID.randomUUID().toString()), rider, "{\"quoteId\":\"" + quote2 + "\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("RIDE_ALREADY_REQUESTED"));
        // Someone else's ride is invisible and cannot be dispatched, cancelled, rated or tracked
        for (var request : List.of(get("/api/v1/rides/" + ride), get("/api/v1/rides/" + ride + "/location"),
                post("/api/v1/rides/" + ride + "/dispatch"), post("/api/v1/rides/" + ride + "/cancel"))) {
            call(request, stranger, null).andExpect(status().isNotFound());
        }

        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SEARCHING_DRIVER"));
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(status().isNoContent());
        String offers = call(get("/api/v1/executor/rides/offers"), driver, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1)).andReturn().getResponse().getContentAsString();
        String offer = JsonPath.read(offers, "$[0].id");
        call(get("/api/v1/executor/rides/offers"), stranger, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), stranger, "{\"accept\":true}")
                .andExpect(status().isNotFound());

        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), driver, "{\"accept\":true}").andExpect(status().isNoContent());
        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), driver, "{\"accept\":true}").andExpect(status().isNoContent());
        call(get("/api/v1/rides/" + ride), rider, null).andExpect(jsonPath("$.status").value("DRIVER_ASSIGNED"))
                .andExpect(jsonPath("$.driver.name").value("Synthetic Driver")).andExpect(jsonPath("$.driver.plate").isNotEmpty())
                .andExpect(jsonPath("$.driver.vehicle").value("Synthetic Car"));

        // Live tracking is served from what the Executor app uploaded
        UUID driverId = db.queryForObject("select driver_id from transactions.rides where id = ?::uuid", UUID.class, ride);
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.point.latitude").value(43.2401));
        backdateLocation(driverId);
        call(put("/api/v1/executor/rides/location"), driver, "{\"latitude\":43.2450,\"longitude\":76.9250}").andExpect(status().isNoContent());
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(jsonPath("$.point.latitude").value(43.245));
        // GPS of another user's trip is not reachable and the trip cannot be driven by a different driver
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), stranger, "{\"step\":\"DEPART\"}").andExpect(status().isNotFound());
        // Illegal order of steps is refused without changing the state
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"COMPLETE\"}").andExpect(status().isConflict());
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"START\"}").andExpect(status().isConflict());
        call(post("/api/v1/rides/" + ride + "/rating"), rider, "{\"stars\":5}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("RIDE_NOT_RATEABLE"));
        for (String step : List.of("DEPART", "ARRIVE", "START")) {
            call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"" + step + "\"}").andExpect(status().isNoContent());
        }
        call(get("/api/v1/rides/" + ride), rider, null).andExpect(jsonPath("$.status").value("IN_PROGRESS"));
        call(post("/api/v1/rides/" + ride + "/cancel"), rider, null).andExpect(status().isConflict());
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"COMPLETE\"}").andExpect(status().isNoContent());
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"COMPLETE\"}").andExpect(status().isNoContent());

        // Tracking stops, price is unchanged, cancel is refused, rating is one-shot
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(status().isNoContent());
        call(get("/api/v1/rides/" + ride), rider, null).andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.estimateKzt").value(500)).andExpect(jsonPath("$.driver").doesNotExist());
        call(post("/api/v1/rides/" + ride + "/cancel"), rider, null).andExpect(status().isConflict());
        call(post("/api/v1/rides/" + ride + "/rating"), stranger, "{\"stars\":1}").andExpect(status().isNotFound());
        call(post("/api/v1/rides/" + ride + "/rating"), rider, "{\"stars\":6}").andExpect(status().isBadRequest());
        call(post("/api/v1/rides/" + ride + "/rating"), rider, "{\"stars\":5,\"comment\":\"ok\"}").andExpect(status().isCreated());
        call(post("/api/v1/rides/" + ride + "/rating"), rider, "{\"stars\":5,\"comment\":\"ok\"}").andExpect(status().isOk());
        call(post("/api/v1/rides/" + ride + "/rating"), rider, "{\"stars\":2}").andExpect(status().isConflict());
        call(get("/api/v1/rides"), rider, null).andExpect(jsonPath("$[0].status").value("COMPLETED"));
        call(get("/api/v1/executor/rides/trips"), driver, null).andExpect(jsonPath("$[0].status").value("COMPLETED"))
                .andExpect(jsonPath("$[0].pickup").doesNotExist());
        assertThat(db.queryForList("select status from transactions.ride_events where ride_id = ?::uuid order by id", String.class, ride))
                .containsExactly("REQUESTED", "SEARCHING_DRIVER", "DRIVER_ASSIGNED", "DRIVER_ARRIVING", "DRIVER_ARRIVED",
                        "IN_PROGRESS", "COMPLETED");

        // Admin: no grant -> 403; with grant -> sees the trip; unauthenticated -> 401
        call(get("/api/v1/admin/rides/trips"), operator, null).andExpect(status().isForbidden());
        db.update("insert into identity.admin_grants (user_id, permission, reason) values (?, 'RIDE_OPERATIONS', 'test')", userId(operator));
        call(get("/api/v1/admin/rides/trips"), operator, null).andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id=='" + ride + "')].status").value("COMPLETED"));
        call(get("/api/v1/admin/rides/summary"), operator, null).andExpect(status().isOk());
        call(get("/api/v1/admin/rides/trips"), rider, null).andExpect(status().isForbidden());
        http.perform(get("/api/v1/rides")).andExpect(status().isUnauthorized());
        http.perform(get("/api/v1/executor/rides/trips")).andExpect(status().isUnauthorized());
    }

    @Test
    void executorInputValidationAndGpsRateLimit() throws Exception {
        String driver = newUser("gps-driver"), operator = newUser("gps-operator");
        approvedOnlineDriver(driver, operator);
        for (String bad : List.of("{\"latitude\":91,\"longitude\":76.9}", "{\"latitude\":43.2,\"longitude\":181}",
                "{\"latitude\":-90.5,\"longitude\":0}", "{\"latitude\":null,\"longitude\":76.9}", "{}")) {
            call(put("/api/v1/executor/rides/location"), driver, bad).andExpect(status().isBadRequest());
        }
        call(put("/api/v1/executor/rides/location"), driver, POSITION).andExpect(status().isTooManyRequests());
        call(put("/api/v1/executor/rides/availability"), driver, "{\"online\":false}").andExpect(status().isOk());
        call(put("/api/v1/executor/rides/location"), driver, POSITION).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("RIDE_DRIVER_OFFLINE"));
        String unapproved = newUser("pending-driver");
        call(post("/api/v1/executor/rides/profile"), unapproved, "{\"displayName\":\"Pending\"}").andExpect(status().isOk());
        call(put("/api/v1/executor/rides/availability"), unapproved, "{\"online\":true}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("RIDE_DRIVER_NOT_APPROVED"));
        call(post("/api/v1/executor/rides/trips/" + UUID.randomUUID() + "/progress"), driver, "{\"step\":\"FLY\"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void rejectionThenNoDriverAvailableAndLateAcceptIsRefused() throws Exception {
        String rider = newUser("nd-rider"), driver = newUser("nd-driver"), operator = newUser("nd-operator");
        approvedOnlineDriver(driver, operator);
        String ride = requestedRide(rider);
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null).andExpect(jsonPath("$.status").value("SEARCHING_DRIVER"));
        String offer = JsonPath.read(call(get("/api/v1/executor/rides/offers"), driver, null).andReturn().getResponse().getContentAsString(), "$[0].id");
        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), driver, "{\"accept\":false}").andExpect(status().isNoContent());
        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), driver, "{\"accept\":true}").andExpect(status().isConflict());
        // the only driver already declined: no new offer; after the search window the ride ends with NO_DRIVER_AVAILABLE
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null).andExpect(jsonPath("$.status").value("SEARCHING_DRIVER"));
        call(get("/api/v1/executor/rides/offers"), driver, null).andExpect(jsonPath("$.length()").value(0));
        db.update("update transactions.rides set search_started_at = now() - interval '3 minutes' where id = ?::uuid", ride);
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null).andExpect(jsonPath("$.status").value("NO_DRIVER_AVAILABLE"));
        // the customer can immediately order again
        requestedRide(rider);
    }

    @Test
    void cancelDuringSearchWithdrawsTheOffer() throws Exception {
        String rider = newUser("cs-rider"), driver = newUser("cs-driver"), operator = newUser("cs-operator");
        approvedOnlineDriver(driver, operator);
        String ride = requestedRide(rider);
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null);
        String offer = JsonPath.read(call(get("/api/v1/executor/rides/offers"), driver, null).andReturn().getResponse().getContentAsString(), "$[0].id");
        call(post("/api/v1/rides/" + ride + "/cancel"), rider, null).andExpect(jsonPath("$.status").value("CANCELLED_BY_CUSTOMER"));
        call(post("/api/v1/rides/" + ride + "/cancel"), rider, null).andExpect(status().isOk());
        call(get("/api/v1/executor/rides/offers"), driver, null).andExpect(jsonPath("$.length()").value(0));
        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), driver, "{\"accept\":true}").andExpect(status().isConflict());
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null).andExpect(jsonPath("$.status").value("CANCELLED_BY_CUSTOMER"));
        assertThat(db.queryForObject("select driver_id from transactions.rides where id = ?::uuid", UUID.class, ride)).isNull();
    }

    @Test
    void onlyTheOfferHolderIsAssignedWhenDriversRaceForOneRide() throws Exception {
        String rider = newUser("race-rider"), one = newUser("race-one"), two = newUser("race-two"), operator = newUser("race-operator");
        approvedOnlineDriver(one, operator);
        approvedOnlineDriver(two, operator);
        String ride = requestedRide(rider);
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null);
        // The schema allows one live offer per ride (partial unique index), so a second live offer cannot even be inserted
        UUID offer = db.queryForObject("select id from transactions.ride_offers where ride_id = ?::uuid and state = 'PENDING'", UUID.class, ride);
        UUID holder = db.queryForObject("select driver_id from transactions.ride_offers where id = ?", UUID.class, offer);
        String owner = holder.equals(userId(one)) ? one : two;
        String intruder = owner.equals(one) ? two : one;
        org.assertj.core.api.Assertions.assertThatThrownBy(() -> db.update(
                "insert into transactions.ride_offers (ride_id, driver_id, expires_at) values (?::uuid, ?, now() + interval '25 seconds')",
                ride, userId(intruder))).hasMessageContaining("ride_offers_pending_ride");
        // Owner (twice, double tap) and a driver who does not hold the offer all accept at the same instant
        var ready = new CountDownLatch(1);
        try (var workers = Executors.newFixedThreadPool(3)) {
            var a = workers.submit(() -> accept(ready, owner, offer));
            var b = workers.submit(() -> accept(ready, owner, offer));
            var c = workers.submit(() -> accept(ready, intruder, offer));
            ready.countDown();
            assertThat(List.of(a.get(15, TimeUnit.SECONDS), b.get(15, TimeUnit.SECONDS))).containsOnly(204);
            assertThat(c.get(15, TimeUnit.SECONDS)).isEqualTo(404);
        }
        assertThat(db.queryForObject("select count(*) from transactions.rides where id = ?::uuid and status = 'DRIVER_ASSIGNED' and driver_id is not null", Long.class, ride)).isEqualTo(1L);
        assertThat(db.queryForList("select status from transactions.ride_events where ride_id = ?::uuid and status = 'DRIVER_ASSIGNED'", String.class, ride)).hasSize(1);
    }

    @Test
    void goingOfflineMidTripRemovesLiveLocationButKeepsTheTrip() throws Exception {
        String rider = newUser("off-rider"), driver = newUser("off-driver"), operator = newUser("off-operator");
        approvedOnlineDriver(driver, operator);
        String ride = requestedRide(rider);
        call(post("/api/v1/rides/" + ride + "/dispatch"), rider, null);
        String offer = JsonPath.read(call(get("/api/v1/executor/rides/offers"), driver, null).andReturn().getResponse().getContentAsString(), "$[0].id");
        call(post("/api/v1/executor/rides/offers/" + offer + "/response"), driver, "{\"accept\":true}").andExpect(status().isNoContent());
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(status().isOk());
        call(put("/api/v1/executor/rides/availability"), driver, "{\"online\":false}").andExpect(status().isOk());
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(status().isNoContent());
        call(get("/api/v1/rides/" + ride), rider, null).andExpect(jsonPath("$.status").value("DRIVER_ASSIGNED"));
        // a stale GPS fix (older than 2 minutes) is never shown as live
        db.update("update transactions.ride_drivers set online = true, latitude = 43.24, longitude = 76.92, observed_at = now() - interval '5 minutes' where user_id = ?", userId(driver));
        call(get("/api/v1/rides/" + ride + "/location"), rider, null).andExpect(status().isNoContent());
        // the driver can still cancel an assigned trip, once
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"CANCEL\"}").andExpect(status().isNoContent());
        call(get("/api/v1/rides/" + ride), rider, null).andExpect(jsonPath("$.status").value("CANCELLED_BY_DRIVER"));
        call(post("/api/v1/executor/rides/trips/" + ride + "/progress"), driver, "{\"step\":\"START\"}").andExpect(status().isConflict());
    }

    private int accept(CountDownLatch ready, String subject, UUID offer) throws Exception {
        ready.await(5, TimeUnit.SECONDS);
        return call(post("/api/v1/executor/rides/offers/" + offer + "/response"), subject, "{\"accept\":true}")
                .andReturn().getResponse().getStatus();
    }

    private String requestedRide(String rider) throws Exception {
        String quote = JsonPath.read(call(post("/api/v1/rides/quotes"), rider, QUOTE).andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(), "$.id");
        return JsonPath.read(call(post("/api/v1/rides").header("Idempotency-Key", UUID.randomUUID().toString()), rider,
                "{\"quoteId\":\"" + quote + "\"}").andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id");
    }

    private void approvedOnlineDriver(String driver, String operator) throws Exception {
        call(post("/api/v1/executor/rides/profile"), driver, "{\"displayName\":\"Synthetic Driver\"}").andExpect(status().isOk());
        String plate = "T" + UUID.randomUUID().toString().replace("-", "").substring(0, 8);
        String vehicle = JsonPath.read(call(post("/api/v1/executor/rides/vehicle"), driver,
                "{\"description\":\"Synthetic Car\",\"plate\":\"" + plate + "\",\"rideClass\":\"ECONOMY\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(), "$.vehicle.id");
        UUID driverId = userId(driver);
        String decision = "{\"decision\":\"APPROVED\"%s}";
        if (db.queryForObject("select count(*) from identity.admin_grants where user_id = ? and permission = 'RIDE_VERIFICATION'", Long.class, userId(operator)) == 0) {
            call(post("/api/v1/admin/rides/drivers/" + driverId + "/decision"), operator, decision.formatted("")).andExpect(status().isForbidden());
        }
        db.update("insert into identity.admin_grants (user_id, permission, reason) values (?, 'RIDE_VERIFICATION', 'test') on conflict do nothing", userId(operator));
        call(post("/api/v1/admin/rides/drivers/" + driverId + "/decision"), operator, decision.formatted("")).andExpect(status().isOk());
        call(post("/api/v1/admin/rides/drivers/" + driverId + "/decision"), operator, decision.formatted(",\"vehicleId\":\"" + vehicle + "\""))
                .andExpect(status().isOk()).andExpect(jsonPath("$.vehicle.status").value("APPROVED"));
        call(put("/api/v1/executor/rides/availability"), driver, "{\"online\":true}").andExpect(status().isOk()).andExpect(jsonPath("$.online").value(true));
        call(put("/api/v1/executor/rides/location"), driver, POSITION).andExpect(status().isNoContent());
    }

    private void backdateLocation(UUID driver) {
        db.update("update transactions.ride_drivers set observed_at = now() - interval '10 seconds' where user_id = ?", driver);
    }

    private ResultActions call(org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder request, String subject, String json)
            throws Exception {
        request.with(token(subject));
        if (json != null) {
            request.contentType(MediaType.APPLICATION_JSON).content(json);
        }
        return http.perform(request);
    }

    private final java.util.Map<String, UUID> users = new java.util.concurrent.ConcurrentHashMap<>();

    private String newUser(String label) {
        String subject = label + "-" + UUID.randomUUID();
        UUID id = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        db.update("insert into identity.external_bindings (issuer, subject, user_id) values ('https://identity.example.test', ?, ?)", subject, id);
        db.update("insert into profile.consumer_profiles (user_id) values (?)", id);
        users.put(subject, id);
        return subject;
    }

    private UUID userId(String subject) {
        return users.get(subject);
    }

    private static RequestPostProcessor token(String subject) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer kunde.admin"));
    }
}
