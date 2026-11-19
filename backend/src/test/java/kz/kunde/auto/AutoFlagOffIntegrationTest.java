package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import kz.kunde.booking.BookingDemoSeeder;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

/** Feature flag off (default): no new quote/booking, empty catalog, capability false; a booking created earlier can still be cancelled. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000511",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class AutoFlagOffIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @Test
    void newBookingsAreRefusedButExistingOnesCanBeCancelled() throws Exception {
        try (var in = new ClassPathResource("auto/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
        http.perform(get("/api/v1/capabilities")).andExpect(status().isOk()).andExpect(jsonPath("$.autoEnabled").value(false));
        http.perform(get("/api/v1/auto/venues")).andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        http.perform(get("/api/v1/auto/categories")).andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        http.perform(post("/api/v1/auth/otp/request").contentType(MediaType.APPLICATION_JSON).content("{\"phone\":\"+77000000511\"}")).andExpect(status().isAccepted());
        String token = JsonPath.read(http.perform(post("/api/v1/auth/otp/verify").contentType(MediaType.APPLICATION_JSON)
                .content("{\"phone\":\"+77000000511\",\"code\":\"123456\"}")).andReturn().getResponse().getContentAsString(), "$.accessToken");
        http.perform(post("/api/v1/auto/quotes").header("Authorization", "Bearer " + token).contentType(MediaType.APPLICATION_JSON)
                .content("{\"venueId\":\"" + UUID.randomUUID() + "\",\"serviceId\":\"" + UUID.randomUUID() + "\",\"vehicleId\":\"" + UUID.randomUUID()
                        + "\",\"startsAt\":\"2030-01-01T10:00:00+05:00\"}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("AUTO_DISABLED"));
        http.perform(post("/api/v1/auto/bookings").header("Authorization", "Bearer " + token).header("Idempotency-Key", "flag-off-key-0000001")
                .contentType(MediaType.APPLICATION_JSON).content("{\"quoteId\":\"" + UUID.randomUUID() + "\"}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("AUTO_DISABLED"));
        // a booking made while the flag was on stays manageable
        UUID user = UUID.fromString(com.nimbusds.jwt.SignedJWT.parse(token).getJWTClaimsSet().getSubject());
        UUID car = db.queryForObject("insert into transactions.customer_vehicles (user_id, make, model, production_year) values (?, 'Kia', 'Rio', 2015) returning id", UUID.class, user);
        UUID booking = db.queryForObject("""
                insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name, master_name,
                    duration_minutes, starts_at, ends_at, price_minor, idempotency_key, category, vehicle_id, vehicle_label)
                select ?, v.id, s.id, m.id, v.name, v.address_text, s.name, m.name, 30, now() + interval '3 days', now() + interval '3 days 30 minutes', s.price_minor,
                       'seeded-before-flag-off', 'AUTO', ?, 'Kia Rio 2015'
                from marketplace.booking_venues v join marketplace.booking_services s on s.venue_id = v.id join marketplace.booking_masters m on m.venue_id = v.id
                where v.slug = 'auto-demo-wash' limit 1 returning id
                """, UUID.class, user, car);
        http.perform(post("/api/v1/auto/bookings/" + booking + "/cancel").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        assertThat(db.queryForObject("select status from transactions.bookings where id = ?", String.class, booking)).isEqualTo("CANCELLED");
    }
}
