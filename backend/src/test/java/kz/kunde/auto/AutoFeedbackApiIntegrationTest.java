package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingDemoSeeder;
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

/** Complaints and reviews over HTTP against PostgreSQL: ownership, one open complaint per subject, resolution by an administrator, ratings. */
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000701,+77000000702,+77000000703",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class AutoFeedbackApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    String alice;
    String bob;
    String admin;
    UUID aliceId;
    UUID adminId;
    UUID venue;
    UUID booking;

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        var request = (method.equals("GET") ? get(path) : post(path)).contentType(MediaType.APPLICATION_JSON);
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

    @BeforeEach
    void setUp() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 LIKE '+7700000070%'");
        try (var in = new ClassPathResource("auto/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
        String a = loginBody("+77000000701");
        alice = JsonPath.read(a, "$.accessToken");
        aliceId = subject(a);
        bob = JsonPath.read(loginBody("+77000000702"), "$.accessToken");
        String ad = loginBody("+77000000703");
        adminId = subject(ad);
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'AUTO_OPERATIONS', 'synthetic DEV admin')", adminId);
        admin = JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null, "{\"refreshToken\":\"" + JsonPath.read(ad, "$.refreshToken") + "\"}")), "$.accessToken");
        venue = db.queryForObject("select id from marketplace.booking_venues where slug = 'auto-demo-sto'", UUID.class);
        UUID car = db.queryForObject("insert into transactions.customer_vehicles (user_id, make, model, production_year) values (?, 'Kia', 'Rio', 2015) returning id", UUID.class, aliceId);
        booking = insertBooking(aliceId, car, "COMPLETED");
    }

    int seq;

    /** Each seeded booking gets its own hour so the one-post exclusion constraint is never hit. */
    private UUID insertBooking(UUID user, UUID car, String status) {
        int hoursAgo = 3 + 2 * (seq++);
        return db.queryForObject("""
                insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name, master_name, duration_minutes,
                    starts_at, ends_at, price_minor, idempotency_key, category, vehicle_id, vehicle_label, status)
                select ?, v.id, s.id, m.id, v.name, v.address_text, s.name, m.name, 45, now() - make_interval(hours => ?), now() - make_interval(hours => ?) + interval '45 minutes', s.price_minor,
                       'seed-' || gen_random_uuid(), 'AUTO', ?, 'Kia Rio 2015', ?
                from marketplace.booking_venues v join marketplace.booking_services s on s.venue_id = v.id join marketplace.booking_masters m on m.venue_id = v.id
                where v.id = ? limit 1 returning id
                """, UUID.class, user, hoursAgo, hoursAgo, car, status, venue);
    }

    @Test
    void complaintsAreOwnedDeduplicatedAndResolvedByAnAdministrator() throws Exception {
        String ok = "{\"bookingId\":\"" + booking + "\",\"kind\":\"QUALITY\",\"description\":\"Масло долили не то\"}";
        send("POST", "/api/v1/auto/complaints", null, ok).andExpect(status().isUnauthorized());
        send("POST", "/api/v1/auto/complaints", bob, ok).andExpect(status().isNotFound()); // someone else's booking
        send("POST", "/api/v1/auto/complaints", alice, "{\"bookingId\":\"" + booking + "\",\"kind\":\"RUDE\",\"description\":\"Грубость\"}").andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/complaints", alice, "{\"bookingId\":\"" + booking + "\",\"kind\":\"QUALITY\",\"description\":\"x\"}").andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/complaints", alice, "{\"kind\":\"QUALITY\",\"description\":\"Нет объекта жалобы\"}").andExpect(status().isBadRequest());
        String created = body(send("POST", "/api/v1/auto/complaints", alice, ok).andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("OPEN")));
        String id = JsonPath.read(created, "$.id");
        send("POST", "/api/v1/auto/complaints", alice, ok).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("COMPLAINT_ALREADY_OPEN"));
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/complaints", alice, null)), "$")).hasSize(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/complaints", bob, null)), "$")).isEmpty();
        // administrator queue: no customer identity in the payload
        send("GET", "/api/v1/admin/auto/complaints", alice, null).andExpect(status().isForbidden());
        String queue = body(send("GET", "/api/v1/admin/auto/complaints", admin, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(queue, "$")).hasSize(1);
        assertThat(queue).doesNotContain(aliceId.toString()).doesNotContain("userId");
        send("POST", "/api/v1/admin/auto/complaints/" + id + "/resolve", admin, "{\"resolution\":\"\"}").andExpect(status().isBadRequest());
        send("POST", "/api/v1/admin/auto/complaints/" + id + "/resolve", alice, "{\"resolution\":\"ok\"}").andExpect(status().isForbidden());
        send("POST", "/api/v1/admin/auto/complaints/" + id + "/resolve", admin, "{\"resolution\":\"Связались с СТО, масло заменено\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("RESOLVED"));
        send("POST", "/api/v1/admin/auto/complaints/" + id + "/resolve", admin, "{\"resolution\":\"Повтор\"}").andExpect(status().isOk()); // idempotent
        assertThat(db.queryForObject("select count(*) from marketplace.auto_admin_events where action = 'COMPLAINT_RESOLVED'", Integer.class)).isEqualTo(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/admin/auto/complaints", admin, null)), "$")).isEmpty();
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/admin/auto/complaints?includeResolved=true", admin, null)), "$")).hasSize(1);
        // after resolution a new complaint about the same booking is allowed
        send("POST", "/api/v1/auto/complaints", alice, ok).andExpect(status().isCreated());
        // an administrator cannot resolve a complaint they filed themselves
        UUID adminCar = db.queryForObject("insert into transactions.customer_vehicles (user_id, make, model, production_year) values (?, 'Lada', 'Vesta', 2019) returning id", UUID.class, adminId);
        UUID adminBooking = insertBooking(adminId, adminCar, "COMPLETED");
        String own = JsonPath.read(body(send("POST", "/api/v1/auto/complaints", admin, "{\"bookingId\":\"" + adminBooking + "\",\"kind\":\"PRICE\",\"description\":\"Цена выше названной\"}")
                .andExpect(status().isCreated())), "$.id");
        send("POST", "/api/v1/admin/auto/complaints/" + own + "/resolve", admin, "{\"resolution\":\"сам себе\"}").andExpect(status().isForbidden());
    }

    @Test
    void reviewsNeedACompletedOwnBookingAreSingleAndFeedTheVenueRating() throws Exception {
        String r = "{\"rating\":5,\"text\":\"Быстро и аккуратно\"}";
        send("GET", "/api/v1/auto/bookings/" + booking + "/review", alice, null).andExpect(status().isNotFound());
        send("POST", "/api/v1/auto/bookings/" + booking + "/review", bob, r).andExpect(status().isNotFound());
        send("POST", "/api/v1/auto/bookings/" + booking + "/review", alice, "{\"rating\":6}").andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/bookings/" + booking + "/review", alice, "{\"rating\":0}").andExpect(status().isBadRequest());
        UUID car2 = db.queryForObject("insert into transactions.customer_vehicles (user_id, make, model, production_year) values (?, 'BMW', 'X5', 2020) returning id", UUID.class, aliceId);
        UUID pending = insertBooking(aliceId, car2, "CONFIRMED");
        send("POST", "/api/v1/auto/bookings/" + pending + "/review", alice, r).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("REVIEW_NOT_ALLOWED"));
        send("POST", "/api/v1/auto/bookings/" + booking + "/review", alice, r).andExpect(status().isCreated()).andExpect(jsonPath("$.rating").value(5));
        send("POST", "/api/v1/auto/bookings/" + booking + "/review", alice, "{\"rating\":1}").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("REVIEW_EXISTS"));
        send("GET", "/api/v1/auto/bookings/" + booking + "/review", alice, null).andExpect(status().isOk()).andExpect(jsonPath("$.text").value("Быстро и аккуратно"));
        String venues = body(send("GET", "/api/v1/auto/venues", null, null).andExpect(status().isOk()));
        assertThat((List<Double>) JsonPath.read(venues, "$[?(@.id=='" + venue + "')].rating")).containsExactly(5.0);
        assertThat((List<Integer>) JsonPath.read(venues, "$[?(@.id=='" + venue + "')].reviews")).containsExactly(1);
    }

    @Test
    void adminSeesAutoVenuesAndCategoryTypes() throws Exception {
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/admin/auto/venues", admin, null).andExpect(status().isOk())), "$")).hasSize(2);
        String cats = body(send("GET", "/api/v1/admin/auto/categories", admin, null).andExpect(status().isOk()));
        assertThat((List<Boolean>) JsonPath.read(cats, "$[?(@.code=='ROADSIDE')].mobile")).containsExactly(true);
        send("GET", "/api/v1/admin/auto/venues", alice, null).andExpect(status().isForbidden());
    }
}
