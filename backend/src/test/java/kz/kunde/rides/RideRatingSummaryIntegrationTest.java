package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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
        "app.rides.enabled=true", "app.rides.consumer-enabled=true", "app.rides.partner-enabled=true"
})
@AutoConfigureMockMvc
@Transactional
class RideRatingSummaryIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired MockMvc http;
    @Autowired RideFleetService fleets;
    @Autowired RideOperationsService operations;

    @DynamicPropertySource
    static void authSecret(DynamicPropertyRegistry registry) {
        String entropy = UUID.randomUUID().toString() + UUID.randomUUID();
        registry.add("app.auth.phone.secret", () -> entropy);
    }

    @Test
    void ratesACompletedRideOnceAndExposesReputationFaresAndSummary() throws Exception {
        UUID rider = session("rating-rider");
        session("rating-stranger");
        UUID operator = session("rating-operator");
        UUID driver = driver();
        var before = operations.summary();
        UUID completed = ride(rider, driver, "MINIVAN", "1250.00", "COMPLETED");
        UUID waiting = ride(session("rating-waiting"), null, "ECONOMY", "500.00", "REQUESTED");
        String rate = "/api/v1/rides/" + completed + "/rating";
        String body = "{\"stars\":5,\"comment\":\"  Great ride  \"}";

        // Only the owner can rate, and only a completed ride that had a driver.
        http.perform(post(rate).with(client("rating-stranger", false)).contentType(MediaType.APPLICATION_JSON)
                .content(body)).andExpect(status().isNotFound());
        http.perform(post("/api/v1/rides/" + waiting + "/rating").with(client("rating-waiting", false))
                .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("RIDE_NOT_RATEABLE"));
        http.perform(post(rate).with(client("rating-rider", false)).contentType(MediaType.APPLICATION_JSON)
                .content("{\"stars\":6}")).andExpect(status().isBadRequest());

        // First write wins; an identical repeat is idempotent; a different one is rejected.
        http.perform(post(rate).with(client("rating-rider", false)).contentType(MediaType.APPLICATION_JSON)
                .content(body)).andExpect(status().isCreated())
                .andExpect(jsonPath("$.stars").value(5)).andExpect(jsonPath("$.comment").value("Great ride"));
        http.perform(post(rate).with(client("rating-rider", false)).contentType(MediaType.APPLICATION_JSON)
                .content(body)).andExpect(status().isOk());
        http.perform(post(rate).with(client("rating-rider", false)).contentType(MediaType.APPLICATION_JSON)
                .content("{\"stars\":1}")).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("RIDE_ALREADY_RATED"));
        assertThat(db.queryForObject("select count(*) from transactions.ride_ratings", Long.class)).isEqualTo(1L);

        // The customer sees their own rating on the ride.
        http.perform(get("/api/v1/rides/" + completed).with(client("rating-rider", false)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.rating.stars").value(5))
                .andExpect(jsonPath("$.rideClass").value("MINIVAN"));

        // Operations see fares and the class per trip and a summary over all rides.
        db.update("insert into identity.admin_grants (user_id, permission, reason) values (?, 'RIDE_OPERATIONS', 'test')",
                operator);
        http.perform(get("/api/v1/admin/rides/trips").with(client("rating-operator", true)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id=='" + completed + "')].fareKzt").value(1250.00))
                .andExpect(jsonPath("$[?(@.id=='" + completed + "')].rideClass").value("MINIVAN"));
        http.perform(get("/api/v1/admin/rides/summary").with(client("rating-operator", true)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currency").value("KZT"))
                .andExpect(jsonPath("$.perDay.length()").value(7))
                .andExpect(jsonPath("$.byClass[?(@.rideClass=='MINIVAN')].rides").isNotEmpty());
        // Other suites may leave rides behind, so assert what this test added.
        var after = operations.summary();
        assertThat(after.total() - before.total()).isEqualTo(2);
        assertThat(after.active() - before.active()).isEqualTo(1);
        assertThat(after.completed() - before.completed()).isEqualTo(1);
        assertThat(after.completedFareKzt().subtract(before.completedFareKzt())).isEqualByComparingTo("1250.00");
        assertThat(after.perDay()).hasSize(7);
        assertThat(after.perDay().get(6).rides() - before.perDay().get(6).rides()).isEqualTo(2);
        http.perform(get("/api/v1/admin/rides/summary").with(client("rating-rider", false)))
                .andExpect(status().isForbidden());
    }

    @Test
    void fleetCarriesFareRatingAndTheSummaryCountsItsCompletedRide() {
        var before = operations.summary();
        UUID owner = user();
        UUID fleet = db.queryForObject("""
                insert into marketplace.partners (display_name, verification_status, created_by_user_id)
                values ('Synthetic fleet', 'APPROVED', ?) returning id
                """, UUID.class, owner);
        db.update("""
                insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id)
                values (?, ?, 'OWNER', ?)
                """, fleet, owner, owner);
        fleets.apply(owner, fleet);
        UUID reviewer = user();
        fleets.review(reviewer, fleet, RideDriverService.Decision.APPROVED);
        UUID driver = driver();
        db.update("update transactions.ride_drivers set fleet_partner_id = ? where user_id = ?", fleet, driver);
        UUID rider = user();
        UUID first = ride(rider, driver, "COMFORT", "700.00", "COMPLETED");
        db.update("update transactions.rides set fleet_partner_id = ? where id = ?", fleet, first);
        db.update("insert into transactions.ride_ratings (ride_id, user_id, driver_id, stars) values (?, ?, ?, 4)",
                first, rider, driver);

        var after = operations.summary();
        assertThat(after.completed() - before.completed()).isEqualTo(1);
        assertThat(after.averageFareKzt()).isNotNull();

        var view = fleets.view(owner, fleet);
        assertThat(view.stats().completedFareKzt()).isEqualByComparingTo("700.00");
        assertThat(view.trips()).singleElement().satisfies(trip -> {
            assertThat(trip.fareKzt()).isEqualByComparingTo("700.00");
            assertThat(trip.rideClass()).isEqualTo(RideMatching.RideClass.COMFORT);
        });
        assertThat(view.drivers()).singleElement().satisfies(entry -> {
            assertThat(entry.rating()).isEqualByComparingTo("4.0");
            assertThat(entry.ratings()).isEqualTo(1L);
        });
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID driver() {
        UUID id = user();
        db.update("insert into transactions.ride_drivers (user_id, display_name) values (?, 'Erlan K.')", id);
        db.update("""
                insert into transactions.ride_vehicles (driver_id, description, plate, ride_class, status)
                values (?, 'Toyota Alphard', ?, 'MINIVAN', 'APPROVED')
                """, id, "M" + id.toString().substring(0, 6).toUpperCase());
        return id;
    }

    private UUID ride(UUID rider, UUID driver, String rideClass, String fare, String state) {
        UUID quote = db.queryForObject("""
                insert into transactions.ride_fare_quotes (user_id, ride_class, tariff_version, estimate_kzt,
                    distance_meters, duration_seconds, pickup_latitude, pickup_longitude, destination_latitude,
                    destination_longitude, expires_at)
                values (?, ?, 'test', ?::numeric, 1000, 180, 43.2, 77, 43.25, 77.1, now() + interval '2 minutes')
                returning id
                """, UUID.class, rider, rideClass, fare);
        return db.queryForObject("""
                insert into transactions.rides (user_id, quote_id, request_key, status, driver_id)
                values (?, ?, ?, ?, ?) returning id
                """, UUID.class, rider, quote, UUID.randomUUID().toString(), state, driver);
    }

    private UUID session(String subject) {
        UUID id = user();
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
