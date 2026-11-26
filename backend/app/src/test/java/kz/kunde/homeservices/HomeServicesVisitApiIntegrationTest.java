package kz.kunde.homeservices;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import kz.kunde.booking.BookingDemoSeeder;
import kz.kunde.food.FoodDemoSeeder;
import kz.kunde.partner.PartnerOpsDemoSeeder;
import kz.kunde.platform.FeatureToggles;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.env.Environment;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * Visits of Home Services bookings over HTTP against PostgreSQL: the master reports the way and the work in order, only the master
 * of the booking may do it, and the customer reads the progress of their own booking only. Synthetic data; the test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.food.enabled=true",
        "app.booking.enabled=true",
        "app.home-services.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000431,+77000000432,+77000000433,+77000000434",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class HomeServicesVisitApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;
    @Autowired FeatureToggles toggles;

    String owner;      // partner A owner (+77000000002), owns the cleaning venue
    String stranger;   // partner B owner (+77000000003)
    String customer;   // +77000000433
    String staff;      // +77000000431 with HOME_SERVICES_CATALOG
    String noGrant;    // +77000000432, a plain account
    String executor;   // +77000000434, linked to a master of the cleaning venue
    String executorUser;
    UUID partnerA;
    UUID partnerB;
    String service;
    String otherService;

    @BeforeEach
    void seed() throws Exception {
        toggles.invalidate();
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000431','+77000000432','+77000000433','+77000000434')");
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json", "food/flowers-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        owner = login("+77000000002");
        stranger = login("+77000000003");
        customer = login("+77000000433");
        partnerB = db.queryForObject("select id from marketplace.partners where display_name = 'Демо-партнёр Б (синтетика)'", UUID.class);
        db.update("update marketplace.booking_venues set partner_id = ? where slug = 'home-clean-demo'", partnerA);
        service = db.queryForObject("select s.id::text from marketplace.booking_services s join marketplace.booking_venues v on v.id = s.venue_id "
                + "where v.slug = 'home-clean-demo' and s.name = 'Генеральная уборка'", String.class);
        otherService = db.queryForObject("select s.id::text from marketplace.booking_services s join marketplace.booking_venues v on v.id = s.venue_id "
                + "where v.slug = 'home-clean-demo' and s.name = 'Поддерживающая уборка'", String.class);
        staff = adminWith(loginBody("+77000000431"), "HOME_SERVICES_CATALOG");
        noGrant = login("+77000000432");
        String executorLogin = loginBody("+77000000434");
        executor = JsonPath.read(executorLogin, "$.accessToken");
        executorUser = subject(executorLogin);
    }

    @AfterEach
    void tearDown() {
        toggles.invalidate();
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String loginBody(String phone) throws Exception {
        http.perform(post("/api/v1/auth/otp/request").contentType(MediaType.APPLICATION_JSON).content("{\"phone\":\"" + phone + "\"}"))
                .andExpect(status().isAccepted());
        return body(http.perform(post("/api/v1/auth/otp/verify").contentType(MediaType.APPLICATION_JSON)
                .content("{\"phone\":\"" + phone + "\",\"code\":\"123456\"}")).andExpect(status().isOk()));
    }

    private String login(String phone) throws Exception { return JsonPath.read(loginBody(phone), "$.accessToken"); }

    private static String subject(String loginBody) throws Exception {
        return com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject();
    }

    private String adminWith(String loginBody, String permission) throws Exception {
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?::uuid, ?, 'synthetic DEV admin')", subject(loginBody), permission);
        return JsonPath.read(body(http.perform(post("/api/v1/auth/token/refresh").contentType(MediaType.APPLICATION_JSON)
                .content("{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}"))), "$.accessToken");
    }

    private ResultActions call(String method, String path, String token, String json) throws Exception {
        var request = "POST".equals(method) ? post(path) : "PUT".equals(method) ? put(path) : get(path);
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }


    private String venueId() {
        return db.queryForObject("select id::text from marketplace.booking_venues where slug = 'home-clean-demo'", String.class);
    }

    private String firstSlot() throws Exception {
        for (int offset = 1; offset < 7; offset++) {
            var date = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Almaty")).plusDays(offset);
            String slots = body(call("GET", "/api/v1/booking/slots?venueId=" + venueId() + "&serviceId=" + service + "&date=" + date, null, null));
            if (!"[]".equals(slots)) { return slots; }
        }
        throw new IllegalStateException("no free slot in the next week");
    }

    /** A confirmed cleaning booking of the customer on a master who is linked to the executor account. */
    private String confirmedBooking() throws Exception {
        String slots = firstSlot();
        String json = "{\"venueId\":\"" + venueId() + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + JsonPath.read(slots, "$[0].masterId")
                + "\",\"startsAt\":\"" + JsonPath.read(slots, "$[0].startsAt") + "\",\"addressText\":\"Алматы, ул. Тестовая 1\",\"areaSqm\":50}";
        String id = JsonPath.read(body(http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + customer)
                .header("Idempotency-Key", "visit-booking-0000000001").contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())), "$.id");
        db.update("update transactions.bookings set status = 'CONFIRMED' where id = ?::uuid", id);
        db.update("update marketplace.booking_masters set user_id = ?::uuid where id = ?::uuid", executorUser, JsonPath.read(slots, "$[0].masterId"));
        return id;
    }

    private ResultActions stage(String booking, String stage, String eta, String token) throws Exception {
        return http.perform(put("/api/v1/executor/home-services/jobs/" + booking + "/stage").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content("{\"stage\":\"" + stage + "\"" + (eta == null ? "" : ",\"etaMinutes\":" + eta) + "}"));
    }

    private ResultActions act(String booking, String action, String token) throws Exception {
        return call("POST", "/api/v1/executor/home-services/jobs/" + booking + "/" + action, token, null);
    }

    @Test
    void masterWalksTheVisitInOrderAndTheCustomerSeesIt() throws Exception {
        String booking = confirmedBooking();
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0].id").value(booking))
                .andExpect(jsonPath("$[0].status").value("CONFIRMED")).andExpect(jsonPath("$[0].stage").doesNotExist());
        call("GET", "/api/v1/home-services/bookings/" + booking + "/visit", customer, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CONFIRMED")).andExpect(jsonPath("$.stage").doesNotExist());

        // Order is enforced: no arrival before leaving, no start before arrival, no finish before start.
        stage(booking, "ARRIVED", null, executor).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("JOB_STATE_INVALID"));
        act(booking, "start", executor).andExpect(status().isConflict());
        act(booking, "complete", executor).andExpect(status().isConflict());

        stage(booking, "EN_ROUTE", "25", executor).andExpect(status().isOk()).andExpect(jsonPath("$.stage").value("EN_ROUTE"))
                .andExpect(jsonPath("$.etaMinutes").value(25));
        stage(booking, "EN_ROUTE", "10", executor).andExpect(status().isOk()).andExpect(jsonPath("$.etaMinutes").value(10));
        call("GET", "/api/v1/home-services/bookings/" + booking + "/visit", customer, null).andExpect(jsonPath("$.stage").value("EN_ROUTE"))
                .andExpect(jsonPath("$.etaMinutes").value(10));
        act(booking, "start", executor).andExpect(status().isConflict());

        stage(booking, "ARRIVED", null, executor).andExpect(status().isOk()).andExpect(jsonPath("$.stage").value("ARRIVED"))
                .andExpect(jsonPath("$.etaMinutes").value(0));
        stage(booking, "EN_ROUTE", "5", executor).andExpect(status().isConflict());
        act(booking, "start", executor).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("IN_PROGRESS"));
        stage(booking, "EN_ROUTE", "5", executor).andExpect(status().isConflict());
        act(booking, "complete", executor).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(jsonPath("$.length()").value(0));

        var events = db.queryForList("select status from transactions.booking_events where booking_id = ?::uuid and actor_user_id is not null", booking);
        assertThat(events.stream().map(e -> e.get("status")).toList()).contains("IN_PROGRESS", "COMPLETED");
    }

    @Test
    void onlyTheBookingsMasterAndCustomerAreAllowed() throws Exception {
        String booking = confirmedBooking();
        // Not a master at all.
        call("GET", "/api/v1/executor/home-services/jobs", noGrant, null).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_A_MASTER"));
        // Another master's job is "not found", even for a linked master.
        db.update("update marketplace.booking_masters set user_id = null where user_id = ?::uuid", executorUser);
        var other = db.queryForList("select id::text from marketplace.booking_masters where venue_id = ?::uuid and active "
                + "and id <> (select master_id from transactions.bookings where id = ?::uuid) order by id limit 1", String.class, venueId(), booking).stream().findFirst().orElse(null);
        assertThat(other).as("the demo cleaning venue has a second master").isNotNull();
        {
            db.update("update marketplace.booking_masters set user_id = ?::uuid where id = ?::uuid", executorUser, other);
            stage(booking, "EN_ROUTE", null, executor).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("JOB_NOT_FOUND"));
        }
        // A customer sees only their own booking.
        call("GET", "/api/v1/home-services/bookings/" + booking + "/visit", stranger, null).andExpect(status().isNotFound());
        call("GET", "/api/v1/home-services/bookings/" + booking + "/visit", null, null).andExpect(status().isUnauthorized());
    }

    @Test
    void inviteCodeLinksAMasterOnce() throws Exception {
        db.update("update marketplace.booking_masters set invite_code = 'HOME-0001' where id = (select id from marketplace.booking_masters where venue_id = ?::uuid and active order by id limit 1)", venueId());
        call("POST", "/api/v1/executor/home-services/link", executor, "{\"code\":\"bad\"}").andExpect(status().isBadRequest());
        call("POST", "/api/v1/executor/home-services/link", executor, "{\"code\":\"HOME-9999\"}").andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("INVITE_INVALID"));
        call("POST", "/api/v1/executor/home-services/link", executor, "{\"code\":\"home-0001\"}").andExpect(status().isNoContent());
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(status().isOk());
        call("POST", "/api/v1/executor/home-services/link", customer, "{\"code\":\"HOME-0001\"}").andExpect(status().isNotFound());
    }

    @Test
    void disabledFeatureHidesTheVisitApi() throws Exception {
        String booking = confirmedBooking();
        toggles.set(UUID.fromString(executorUser), FeatureToggles.Feature.HOME_SERVICES, false, "synthetic switch-off", null);
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("HOME_SERVICES_DISABLED"));
        call("GET", "/api/v1/home-services/bookings/" + booking + "/visit", customer, null).andExpect(status().isNotFound());
    }
}
