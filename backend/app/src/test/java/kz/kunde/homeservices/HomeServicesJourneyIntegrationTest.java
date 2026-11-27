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
 * Product API E2E of Home Services (ADR-027): the whole journey over HTTP against PostgreSQL, all five roles. The partner publishes an
 * offer, Admin moderates it, the customer quotes and orders (idempotently), the partner accepts, the master walks the visit, the
 * customer sees COMPLETED. Also: cancellation, access errors, repeated requests and impossible transitions. Synthetic data; rolls back.
 * Run alone: ./gradlew :app:test --tests 'kz.kunde.homeservices.HomeServicesJourneyIntegrationTest'.
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
class HomeServicesJourneyIntegrationTest {
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

    private ResultActions stage(String booking, String stage, String eta, String token) throws Exception {
        return http.perform(put("/api/v1/executor/home-services/jobs/" + booking + "/stage").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content("{\"stage\":\"" + stage + "\"" + (eta == null ? "" : ",\"etaMinutes\":" + eta) + "}"));
    }

    private ResultActions act(String booking, String action, String token) throws Exception {
        return call("POST", "/api/v1/executor/home-services/jobs/" + booking + "/" + action, token, null);
    }

    private String partnerBase() { return "/api/v1/partner/partners/" + partnerA + "/home-services/offers"; }

    private String bookingBase() { return "/api/v1/partner/partners/" + partnerA + "/booking/bookings"; }

    private ResultActions offerAct(String offer, String action, long version, String token) throws Exception {
        return call("POST", partnerBase() + "/" + offer + "/transition", token, "{\"action\":\"" + action + "\",\"expectedVersion\":" + version + "}");
    }

    private ResultActions decide(String offer, String action, long version, String token) throws Exception {
        return call("POST", "/api/v1/admin/home-services/offers/" + offer + "/decision", token,
                "{\"action\":\"" + action + "\",\"expectedVersion\":" + version + ",\"reason\":\"journey check\"}");
    }

    private String publishOffer() throws Exception {
        String offer = JsonPath.read(body(call("POST", partnerBase(), owner,
                "{\"serviceId\":\"" + service + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FROM\",\"warrantyDays\":14}")
                .andExpect(status().isCreated())), "$.id");
        offerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"));
        decide(offer, "APPROVE", 2, staff).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PUBLISHED"));
        return offer;
    }

    private String bookingJson(String slots) {
        return "{\"venueId\":\"" + venueId() + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + JsonPath.read(slots, "$[0].masterId")
                + "\",\"startsAt\":\"" + JsonPath.read(slots, "$[0].startsAt") + "\",\"addressText\":\"Алматы, ул. Тестовая 1\",\"areaSqm\":50}";
    }

    private ResultActions order(String json, String key, String token) throws Exception {
        return http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + token)
                .header("Idempotency-Key", key).contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private String bookingStatus(String booking) {
        return db.queryForObject("select status from transactions.bookings where id = ?::uuid", String.class, booking);
    }

    private static org.springframework.test.web.servlet.ResultMatcher clientError() {
        return result -> assertThat(result.getResponse().getStatus()).isBetween(400, 499);
    }

    @Test
    void customerOrderIsModeratedAcceptedPerformedAndCompleted() throws Exception {
        // 1. Partner offer + Admin moderation. A plain account can not moderate; the customer sees nothing before approval.
        String offer = JsonPath.read(body(call("POST", partnerBase(), owner,
                "{\"serviceId\":\"" + service + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FROM\",\"warrantyDays\":14}")
                .andExpect(status().isCreated())), "$.id");
        offerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk());
        call("GET", "/api/v1/home-services/offers", customer, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        decide(offer, "APPROVE", 2, noGrant).andExpect(clientError());
        decide(offer, "APPROVE", 2, owner).andExpect(clientError());
        decide(offer, "APPROVE", 2, staff).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PUBLISHED"));
        decide(offer, "APPROVE", 2, staff).andExpect(clientError());  // stale version / repeated decision changes nothing

        // 2. Customer finds, quotes and orders; the order is idempotent and a reused key with another booking is refused.
        call("GET", "/api/v1/home-services/offers", customer, null).andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0].id").value(offer));
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50", customer, null).andExpect(status().isOk());
        String slots = firstSlot();
        String json = bookingJson(slots);
        String key = "journey-order-0000000001";
        String booking = JsonPath.read(body(order(json, key, customer).andExpect(status().isCreated())), "$.id");
        order(json, key, customer).andExpect(status().isOk()).andExpect(jsonPath("$.id").value(booking));
        order(json.replace("\"areaSqm\":50", "\"areaSqm\":60").replace(JsonPath.read(slots, "$[0].masterId"), UUID.randomUUID().toString()), key, customer)
                .andExpect(clientError());
        assertThat(db.queryForObject("select count(*) from transactions.bookings where user_id = (select user_id from transactions.bookings where id = ?::uuid)",
                Long.class, booking)).isEqualTo(1L);

        // 3. Partner accepts (a stranger partner and the customer can not act on it); repeated confirmation is harmless.
        call("POST", "/api/v1/partner/partners/" + partnerB + "/booking/bookings/" + booking + "/action", stranger, "{\"action\":\"CONFIRM\"}").andExpect(clientError());
        call("POST", bookingBase() + "/" + booking + "/action", customer, "{\"action\":\"CONFIRM\"}").andExpect(clientError());
        call("POST", bookingBase() + "/" + booking + "/action", null, "{\"action\":\"CONFIRM\"}").andExpect(status().isUnauthorized());
        if ("PENDING".equals(bookingStatus(booking))) {
            call("POST", bookingBase() + "/" + booking + "/action", owner, "{\"action\":\"CONFIRM\"}").andExpect(status().isOk());
        }
        call("POST", bookingBase() + "/" + booking + "/action", owner, "{\"action\":\"CONFIRM\"}").andExpect(status().isOk());
        assertThat(bookingStatus(booking)).isEqualTo("CONFIRMED");

        // 4. The master (linked to the booking's master) performs the visit in order; impossible transitions change nothing.
        db.update("update marketplace.booking_masters set user_id = ?::uuid where id = ?::uuid", executorUser, JsonPath.read(slots, "$[0].masterId"));
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0].id").value(booking));
        act(booking, "complete", executor).andExpect(status().isConflict());
        stage(booking, "ARRIVED", null, executor).andExpect(status().isConflict());
        stage(booking, "EN_ROUTE", "20", executor).andExpect(status().isOk());
        stage(booking, "EN_ROUTE", "20", executor).andExpect(status().isOk());  // repeated report is idempotent
        stage(booking, "ARRIVED", null, executor).andExpect(status().isOk());
        act(booking, "start", executor).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("IN_PROGRESS"));
        act(booking, "start", executor).andExpect(clientError());
        act(booking, "complete", executor).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        act(booking, "complete", executor).andExpect(clientError());

        // 5. The customer sees the outcome; completed work can no longer be cancelled or re-confirmed.
        call("GET", "/api/v1/booking/bookings/" + booking, customer, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        call("GET", "/api/v1/home-services/bookings/" + booking + "/visit", customer, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        call("POST", "/api/v1/booking/bookings/" + booking + "/cancel", customer, null).andExpect(clientError());
        call("POST", bookingBase() + "/" + booking + "/action", owner, "{\"action\":\"REJECT\"}").andExpect(clientError());
        assertThat(bookingStatus(booking)).isEqualTo("COMPLETED");
        call("GET", "/api/v1/booking/bookings/" + booking, stranger, null).andExpect(status().isNotFound());
    }

    @Test
    void customerCancelsBeforeTheVisitAndNobodyCanWorkOnACancelledOrder() throws Exception {
        publishOffer();
        String slots = firstSlot();
        String booking = JsonPath.read(body(order(bookingJson(slots), "journey-cancel-000000001", customer).andExpect(status().isCreated())), "$.id");
        db.update("update marketplace.booking_masters set user_id = ?::uuid where id = ?::uuid", executorUser, JsonPath.read(slots, "$[0].masterId"));

        call("POST", "/api/v1/booking/bookings/" + booking + "/cancel", stranger, null).andExpect(status().isNotFound());
        call("POST", "/api/v1/booking/bookings/" + booking + "/cancel", null, null).andExpect(status().isUnauthorized());
        assertThat(bookingStatus(booking)).isIn("PENDING", "CONFIRMED");
        call("POST", "/api/v1/booking/bookings/" + booking + "/cancel", customer, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        call("POST", "/api/v1/booking/bookings/" + booking + "/cancel", customer, null).andExpect(result ->
                assertThat(result.getResponse().getStatus()).isLessThan(500));  // repeated cancel is refused or idempotent, never an error
        assertThat(bookingStatus(booking)).isEqualTo("CANCELLED");

        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(jsonPath("$.length()").value(0));
        stage(booking, "EN_ROUTE", "10", executor).andExpect(clientError());
        act(booking, "start", executor).andExpect(clientError());
        call("POST", bookingBase() + "/" + booking + "/action", owner, "{\"action\":\"CONFIRM\"}").andExpect(clientError());
        assertThat(bookingStatus(booking)).isEqualTo("CANCELLED");
        // The freed slot can be booked again.
        order(bookingJson(slots), "journey-cancel-000000002", customer).andExpect(status().isCreated());
    }

    @Test
    void withoutTheFeatureNoOneCanOrderHomeServices() throws Exception {
        publishOffer();
        toggles.set(UUID.fromString(executorUser), FeatureToggles.Feature.HOME_SERVICES, false, "synthetic switch-off", null);
        call("GET", "/api/v1/home-services/offers", customer, null).andExpect(clientError());
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(status().isNotFound());
    }
}
