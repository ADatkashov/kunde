package kz.kunde.homeservices;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.List;
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
 * H6: verified reviews of Home Services over HTTP against PostgreSQL: who may review, one review per order, computed ratings,
 * Partner tenant isolation and complaints, the master's own rating, staff moderation with audit, and the disabled product. Synthetic data; rolls back. Run alone: ./gradlew :app:test --tests 'kz.kunde.homeservices.HomeServicesReviewsIntegrationTest'.
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000431,+77000000432,+77000000433,+77000000435,+77000000434",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class HomeServicesReviewsIntegrationTest {
    static final String CUSTOMER_PHONE = "+77000000433";

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;
    @Autowired FeatureToggles toggles;

    String ops;          // +77000000431 with HOME_SERVICES_OPERATIONS
    String catalogOnly;  // +77000000435 with HOME_SERVICES_CATALOG only
    String plain;        // +77000000432, a plain account
    String customer;     // +77000000433
    String otherCustomer; // +77000000003 (partner B owner acting as a second customer)
    String executor;     // +77000000434, linked to the master of the first order
    String executorUser;
    String opsUser;
    String owner;        // +77000000002, owner of partner A (the cleaning venue)
    String stranger;     // +77000000003, owner of partner B
    UUID partnerA;
    UUID partnerB;
    String service;
    String slots;

    @BeforeEach
    void seed() throws Exception {
        toggles.invalidate();
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000431','+77000000432','+77000000433','+77000000434','+77000000435')");
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json", "food/flowers-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        partnerB = db.queryForObject("select id from marketplace.partners where display_name = 'Демо-партнёр Б (синтетика)'", UUID.class);
        db.update("update marketplace.booking_venues set partner_id = ? where slug = 'home-clean-demo'", partnerA);
        service = db.queryForObject("select s.id::text from marketplace.booking_services s join marketplace.booking_venues v on v.id = s.venue_id "
                + "where v.slug = 'home-clean-demo' and s.name = 'Генеральная уборка'", String.class);
        String opsLogin = loginBody("+77000000431");
        opsUser = subject(opsLogin);
        ops = adminWith(opsLogin, "HOME_SERVICES_OPERATIONS");
        catalogOnly = adminWith(loginBody("+77000000435"), "HOME_SERVICES_CATALOG");
        plain = login("+77000000432");
        customer = login(CUSTOMER_PHONE);
        owner = login("+77000000002");
        otherCustomer = login("+77000000003");
        stranger = otherCustomer;
        String executorLogin = loginBody("+77000000434");
        executor = JsonPath.read(executorLogin, "$.accessToken");
        executorUser = subject(executorLogin);
        slots = firstSlot();
    }

    @AfterEach
    void tearDown() {
        toggles.invalidate();
    }

    // ---- helpers

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
        var request = "POST".equals(method) ? post(path) : get(path);
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
            String found = body(call("GET", "/api/v1/booking/slots?venueId=" + venueId() + "&serviceId=" + service + "&date=" + date, null, null));
            if (!"[]".equals(found)) { return found; }
        }
        throw new IllegalStateException("no free slot in the next week");
    }

    private String bookingJson(String masterId, String startsAt) {
        return "{\"venueId\":\"" + venueId() + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + masterId
                + "\",\"startsAt\":\"" + startsAt + "\",\"addressText\":\"Алматы, ул. Тестовая 1\",\"areaSqm\":50}";
    }

    /** Orders the first slot for the first master; the master is linked to the synthetic executor account. */
    private String orderFor(String token, String key) throws Exception {
        String masterId = JsonPath.read(slots, "$[0].masterId");
        String booking = JsonPath.read(body(http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + token)
                .header("Idempotency-Key", key).contentType(MediaType.APPLICATION_JSON).content(bookingJson(masterId, JsonPath.read(slots, "$[0].startsAt"))))
                .andExpect(status().isCreated())), "$.id");
        return booking;
    }

    private String confirm(String booking) {
        db.update("update transactions.bookings set status = 'CONFIRMED' where id = ?::uuid", booking);
        return booking;
    }

    private long version(String booking) {
        return db.queryForObject("select version from transactions.bookings where id = ?::uuid", Long.class, booking);
    }

    private String statusOf(String booking) {
        return db.queryForObject("select status from transactions.bookings where id = ?::uuid", String.class, booking);
    }

    private String orders(String suffix) { return "/api/v1/admin/home-services/orders" + suffix; }

    private String masterOtherThan(String booking) {
        return db.queryForObject("select m.id::text from marketplace.booking_masters m join marketplace.booking_master_services ms on ms.master_id = m.id "
                + "and ms.service_id = (select service_id from transactions.bookings where id = ?::uuid) "
                + "where m.venue_id = (select venue_id from transactions.bookings where id = ?::uuid) and m.active and m.online "
                + "and m.id <> (select master_id from transactions.bookings where id = ?::uuid) order by m.name limit 1", String.class, booking, booking, booking);
    }

    private static org.springframework.test.web.servlet.ResultMatcher clientError() {
        return result -> assertThat(result.getResponse().getStatus()).isBetween(400, 499);
    }

    // ---- review helpers

    private String orderAt(String token, String key, int which) throws Exception {
        if (which < 0) { which = ((List<?>) JsonPath.read(slots, "$")).size() + which; }
        String masterId = JsonPath.read(slots, "$[" + which + "].masterId");
        return JsonPath.read(body(http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + token)
                .header("Idempotency-Key", key).contentType(MediaType.APPLICATION_JSON)
                .content(bookingJson(masterId, JsonPath.read(slots, "$[" + which + "].startsAt")))).andExpect(status().isCreated())), "$.id");
    }

    private String completed(String booking) {
        db.update("update transactions.bookings set status = 'COMPLETED' where id = ?::uuid", booking);
        return booking;
    }

    private String review(String booking, String token, String json) throws Exception {
        return body(call("POST", "/api/v1/home-services/bookings/" + booking + "/review", token, json).andExpect(status().is2xxSuccessful()));
    }

    private String publishOffer() throws Exception {
        String base = "/api/v1/partner/partners/" + partnerA + "/home-services/offers";
        String offer = JsonPath.read(body(call("POST", base, owner,
                "{\"serviceId\":\"" + service + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FROM\",\"warrantyDays\":14}").andExpect(status().isCreated())), "$.id");
        call("POST", base + "/" + offer + "/transition", owner, "{\"action\":\"SUBMIT\",\"expectedVersion\":1}").andExpect(status().isOk());
        call("POST", "/api/v1/admin/home-services/offers/" + offer + "/decision", catalogOnly,
                "{\"action\":\"APPROVE\",\"expectedVersion\":2,\"reason\":\"synthetic\"}").andExpect(status().isOk());
        return offer;
    }

    /** Two completed orders of the same master by two customers; the executor account is linked to that master. */
    private String[] twoCompleted() throws Exception {
        String first = completed(confirm(orderAt(customer, "reviews-order-000000000001", 0)));
        String last = completed(orderAt(otherCustomer, "reviews-order-000000000002", -1));
        String master = db.queryForObject("select master_id::text from transactions.bookings where id = ?::uuid", String.class, first);
        db.update("update transactions.bookings set master_id = ?::uuid where id = ?::uuid", master, last);
        db.update("update marketplace.booking_masters set user_id = ?::uuid where id = ?::uuid", executorUser, master);
        return new String[] {first, last, master};
    }

    // ---- tests

    @Test
    void onlyTheOwnerOfACompletedOrderReviewsItOnce() throws Exception {
        String booking = confirm(orderAt(customer, "reviews-order-000000000001", 0));
        String json = "{\"rating\":5,\"qualityRating\":4,\"punctualityRating\":3,\"comment\":\"  Отлично  \"}";
        String path = "/api/v1/home-services/bookings/" + booking + "/review";

        call("POST", path, customer, json).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ORDER_NOT_COMPLETED"));
        completed(booking);
        call("POST", path, null, json).andExpect(status().isUnauthorized());
        call("POST", path, otherCustomer, json).andExpect(status().isNotFound());   // not the owner
        call("POST", path, customer, "{\"rating\":0}").andExpect(status().isBadRequest());
        call("POST", path, customer, "{\"rating\":6}").andExpect(status().isBadRequest());
        call("POST", path, customer, "{\"rating\":5,\"qualityRating\":9}").andExpect(status().isBadRequest());
        call("POST", path, customer, "{}").andExpect(status().isBadRequest());
        call("GET", path, customer, null).andExpect(status().isNotFound());
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_reviews", Long.class)).isZero();

        String id = JsonPath.read(body(call("POST", path, customer, json).andExpect(status().isCreated())
                .andExpect(jsonPath("$.rating").value(5)).andExpect(jsonPath("$.comment").value("Отлично"))
                .andExpect(jsonPath("$.status").value("PUBLISHED"))), "$.id");
        // Repeating the same request returns the same review; a different review of the same order is refused.
        call("POST", path, customer, json).andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        call("POST", path, customer, "{\"rating\":1}").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("REVIEW_EXISTS"));
        call("GET", path, customer, null).andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        call("GET", path, otherCustomer, null).andExpect(status().isNotFound());
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_reviews", Long.class)).isEqualTo(1L);
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_review_events where review_id = ?::uuid and action = 'CREATED' and actor_type = 'CUSTOMER'",
                Long.class, id)).isEqualTo(1L);
    }

    @Test
    void ratingsAreComputedFromPublishedReviewsOnly() throws Exception {
        String offer = publishOffer();
        // No reviews yet: no rating at all (not zero), in the catalogue and in the offer's reviews.
        call("GET", "/api/v1/home-services/offers", customer, null).andExpect(jsonPath("$[0].rating").doesNotExist()).andExpect(jsonPath("$[0].reviewCount").value(0));
        call("GET", "/api/v1/home-services/offers/" + offer + "/reviews", customer, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.summary.rating").doesNotExist()).andExpect(jsonPath("$.summary.count").value(0)).andExpect(jsonPath("$.items.length()").value(0));

        String[] orders = twoCompleted();
        String r1 = JsonPath.read(review(orders[0], customer, "{\"rating\":5,\"qualityRating\":4,\"punctualityRating\":3,\"comment\":\"Быстро\"}"), "$.id");
        review(orders[1], otherCustomer, "{\"rating\":2,\"qualityRating\":2}");

        call("GET", "/api/v1/home-services/offers", customer, null).andExpect(jsonPath("$[0].rating").value(3.5)).andExpect(jsonPath("$[0].reviewCount").value(2));
        call("GET", "/api/v1/home-services/offers/" + offer + "/reviews", customer, null).andExpect(jsonPath("$.summary.rating").value(3.5))
                .andExpect(jsonPath("$.summary.qualityRating").value(3.0)).andExpect(jsonPath("$.summary.punctualityRating").value(3.0))
                .andExpect(jsonPath("$.total").value(2)).andExpect(jsonPath("$.items[0].authorName").value("Клиент"));
        call("GET", "/api/v1/home-services/masters/" + orders[2] + "/reviews", customer, null).andExpect(jsonPath("$.summary.count").value(2));
        // Public reviews never carry the author's identity.
        assertThat(body(call("GET", "/api/v1/home-services/masters/" + orders[2] + "/reviews", customer, null))).doesNotContain("userId").doesNotContain(CUSTOMER_PHONE);
        call("GET", "/api/v1/home-services/offers/" + UUID.randomUUID() + "/reviews", customer, null).andExpect(status().isNotFound());
        call("GET", "/api/v1/home-services/offers/" + offer + "/reviews?limit=1&offset=1", customer, null).andExpect(jsonPath("$.items.length()").value(1)).andExpect(jsonPath("$.total").value(2));
        call("GET", "/api/v1/home-services/offers/" + offer + "/reviews?limit=0", customer, null).andExpect(status().is4xxClientError());

        // A hidden review leaves the average at once.
        db.update("update marketplace.home_service_reviews set status = 'HIDDEN' where id = ?::uuid", r1);
        call("GET", "/api/v1/home-services/offers", customer, null).andExpect(jsonPath("$[0].rating").value(2.0)).andExpect(jsonPath("$[0].reviewCount").value(1));
    }

    @Test
    void partnerSeesOnlyItsOwnReviewsAndComplainsOnce() throws Exception {
        String[] orders = twoCompleted();
        String id = JsonPath.read(review(orders[0], customer, "{\"rating\":1,\"comment\":\"Плохо\"}"), "$.id");
        review(orders[1], otherCustomer, "{\"rating\":4}");
        String base = "/api/v1/partner/partners/" + partnerA + "/home-services/reviews";

        call("GET", base, owner, null).andExpect(status().isOk()).andExpect(jsonPath("$.total").value(2)).andExpect(jsonPath("$.summary.rating").value(2.5));
        call("GET", base + "?rating=1", owner, null).andExpect(jsonPath("$.total").value(1)).andExpect(jsonPath("$.items[0].comment").value("Плохо"));
        call("GET", base + "?masterId=" + orders[2], owner, null).andExpect(jsonPath("$.total").value(2));
        call("GET", base + "?masterId=" + UUID.randomUUID(), owner, null).andExpect(jsonPath("$.total").value(0));
        call("GET", base + "/summary", owner, null).andExpect(status().isOk()).andExpect(jsonPath("$.organization.count").value(2))
                .andExpect(jsonPath("$.masters[?(@.masterId == '" + orders[2] + "')].count").value(2));
        // Tenant isolation: another partner can not read or complain about these reviews, and a customer is not staff.
        call("GET", "/api/v1/partner/partners/" + partnerA + "/home-services/reviews", stranger, null).andExpect(status().isNotFound());
        call("GET", "/api/v1/partner/partners/" + partnerB + "/home-services/reviews", stranger, null).andExpect(jsonPath("$.total").value(0));
        call("POST", base + "/" + id + "/complaint", stranger, "{\"reason\":\"спам\"}").andExpect(status().isNotFound());
        call("GET", base, null, null).andExpect(status().isUnauthorized());

        call("POST", base + "/" + id + "/complaint", owner, "{\"reason\":\"\"}").andExpect(status().isBadRequest());
        call("POST", base + "/" + UUID.randomUUID() + "/complaint", owner, "{\"reason\":\"оскорбление\"}").andExpect(status().isNotFound());
        String complaint = JsonPath.read(body(call("POST", base + "/" + id + "/complaint", owner, "{\"reason\":\"Не было такого заказа\"}")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("OPEN"))), "$.id");
        call("POST", base + "/" + id + "/complaint", owner, "{\"reason\":\"Не было такого заказа\"}").andExpect(jsonPath("$.id").value(complaint));
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_review_complaints", Long.class)).isEqualTo(1L);
    }

    @Test
    void masterSeesOnlyTheirOwnRatingAndHistory() throws Exception {
        String[] orders = twoCompleted();
        review(orders[0], customer, "{\"rating\":5,\"punctualityRating\":5}");
        review(orders[1], otherCustomer, "{\"rating\":4}");
        call("GET", "/api/v1/executor/home-services/rating", executor, null).andExpect(status().isOk()).andExpect(jsonPath("$.rating.rating").value(4.5))
                .andExpect(jsonPath("$.rating.count").value(2)).andExpect(jsonPath("$.completedOrders").value(2));
        call("GET", "/api/v1/executor/home-services/reviews", executor, null).andExpect(jsonPath("$.total").value(2));
        call("GET", "/api/v1/executor/home-services/rating", customer, null).andExpect(status().isNotFound());   // not a master
        call("GET", "/api/v1/executor/home-services/rating", null, null).andExpect(status().isUnauthorized());
    }

    @Test
    void staffModerateComplaintsAndEverythingIsAudited() throws Exception {
        String[] orders = twoCompleted();
        String id = JsonPath.read(review(orders[0], customer, "{\"rating\":1,\"comment\":\"Грубый текст\"}"), "$.id");
        String quiet = JsonPath.read(review(orders[1], otherCustomer, "{\"rating\":5}"), "$.id");
        String complaint = JsonPath.read(body(call("POST", "/api/v1/partner/partners/" + partnerA + "/home-services/reviews/" + id + "/complaint", owner,
                "{\"reason\":\"Оскорбление в тексте\"}").andExpect(status().isCreated())), "$.id");
        String admin = "/api/v1/admin/home-services";

        // RBAC: the catalogue grant and plain accounts do not open moderation.
        call("GET", admin + "/reviews", catalogOnly, null).andExpect(status().isForbidden());
        call("GET", admin + "/reviews", plain, null).andExpect(status().isForbidden());
        call("GET", admin + "/review-complaints", plain, null).andExpect(status().isForbidden());
        call("GET", admin + "/reviews", null, null).andExpect(status().isUnauthorized());

        // The complained review comes first and shows the open complaint.
        call("GET", admin + "/reviews", ops, null).andExpect(status().isOk()).andExpect(jsonPath("$[0].id").value(id)).andExpect(jsonPath("$[0].openComplaints").value(1))
                .andExpect(jsonPath("$[1].id").value(quiet));
        call("GET", admin + "/reviews?status=HIDDEN", ops, null).andExpect(jsonPath("$.length()").value(0));
        call("GET", admin + "/review-complaints?status=OPEN", ops, null).andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0].id").value(complaint));

        // Moderation needs a reason and the version the screen saw.
        call("POST", admin + "/reviews/" + id + "/moderation", ops, "{\"action\":\"HIDE\",\"expectedVersion\":1}").andExpect(status().isBadRequest());
        call("POST", admin + "/reviews/" + id + "/moderation", ops, "{\"action\":\"HIDE\",\"expectedVersion\":7,\"reason\":\"stale\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        call("POST", admin + "/reviews/" + id + "/moderation", ops, "{\"action\":\"PUBLISH\",\"expectedVersion\":1,\"reason\":\"already\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("REVIEW_STATE_INVALID"));
        call("POST", admin + "/reviews/" + id + "/moderation", plain, "{\"action\":\"HIDE\",\"expectedVersion\":1,\"reason\":\"nope\"}").andExpect(status().isForbidden());
        call("POST", admin + "/reviews/" + id + "/moderation", ops, "{\"action\":\"HIDE\",\"expectedVersion\":1,\"reason\":\"Нарушает правила\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("HIDDEN")).andExpect(jsonPath("$.version").value(2));
        call("GET", "/api/v1/home-services/masters/" + orders[2] + "/reviews", customer, null).andExpect(jsonPath("$.summary.count").value(1)).andExpect(jsonPath("$.summary.rating").value(5.0));
        call("POST", admin + "/reviews/" + id + "/moderation", ops, "{\"action\":\"PUBLISH\",\"expectedVersion\":2,\"reason\":\"Ошибочно скрыт\"}")
                .andExpect(jsonPath("$.status").value("PUBLISHED")).andExpect(jsonPath("$.version").value(3));

        // Resolving the complaint with "hide" hides the review in the same step; a resolved complaint can not be resolved again.
        call("POST", admin + "/review-complaints/" + complaint + "/resolve", ops, "{\"resolution\":\"\"}").andExpect(status().isBadRequest());
        call("POST", admin + "/review-complaints/" + complaint + "/resolve", ops, "{\"resolution\":\"Жалоба обоснована\",\"hideReview\":true}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("RESOLVED")).andExpect(jsonPath("$.reviewStatus").value("HIDDEN"));
        call("POST", admin + "/review-complaints/" + complaint + "/resolve", ops, "{\"resolution\":\"ещё раз\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("COMPLAINT_RESOLVED"));
        call("POST", admin + "/review-complaints/" + UUID.randomUUID() + "/resolve", ops, "{\"resolution\":\"нет такой\"}").andExpect(status().isNotFound());
        call("GET", admin + "/review-complaints?status=OPEN", ops, null).andExpect(jsonPath("$.length()").value(0));

        // Audit: created, complaint, hidden, published, hidden, complaint done — append-only and attributed.
        assertThat(db.queryForList("select action from marketplace.home_service_review_events where review_id = ?::uuid order by id", String.class, id))
                .containsExactly("CREATED", "COMPLAINT", "HIDDEN", "PUBLISHED", "HIDDEN", "COMPLAINT_DONE");
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_review_events where review_id = ?::uuid and actor_type = 'ADMIN' and actor_user_id = ?::uuid",
                Long.class, id, opsUser)).isEqualTo(4L);
        assertThatThrownBy(() -> db.update("update marketplace.home_service_review_events set note = 'x'")).isInstanceOf(Exception.class);
        assertThatThrownBy(() -> db.update("delete from marketplace.home_service_review_events")).isInstanceOf(Exception.class);
    }

    @Test
    void withoutTheFeatureNoReviewsAreAvailable() throws Exception {
        String[] orders = twoCompleted();
        toggles.set(UUID.fromString(executorUser), FeatureToggles.Feature.HOME_SERVICES, false, "synthetic switch-off", null);
        call("POST", "/api/v1/home-services/bookings/" + orders[0] + "/review", customer, "{\"rating\":5}").andExpect(status().isNotFound());
        call("GET", "/api/v1/home-services/masters/" + orders[2] + "/reviews", customer, null).andExpect(status().isNotFound());
        call("GET", "/api/v1/executor/home-services/rating", executor, null).andExpect(status().isNotFound());
        call("GET", "/api/v1/partner/partners/" + partnerA + "/home-services/reviews", owner, null).andExpect(status().isNotFound());
    }
}
