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
 * H8: staff operations over Home Services orders over HTTP against PostgreSQL: the register and its filters, the order card with
 * history, cancellation and re-assignment, RBAC (a separate grant from catalogue moderation), stale versions, impossible states and
 * the audit. Synthetic data; rolls back. Run alone: ./gradlew :app:test --tests 'kz.kunde.homeservices.HomeServicesAdminOrdersIntegrationTest'.
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
class HomeServicesAdminOrdersIntegrationTest {
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
        UUID partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        db.update("update marketplace.booking_venues set partner_id = ? where slug = 'home-clean-demo'", partnerA);
        service = db.queryForObject("select s.id::text from marketplace.booking_services s join marketplace.booking_venues v on v.id = s.venue_id "
                + "where v.slug = 'home-clean-demo' and s.name = 'Генеральная уборка'", String.class);
        String opsLogin = loginBody("+77000000431");
        opsUser = subject(opsLogin);
        ops = adminWith(opsLogin, "HOME_SERVICES_OPERATIONS");
        catalogOnly = adminWith(loginBody("+77000000435"), "HOME_SERVICES_CATALOG");
        plain = login("+77000000432");
        customer = login(CUSTOMER_PHONE);
        otherCustomer = login("+77000000003");
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

    // ---- tests

    @Test
    void onlyTheOperationsGrantOpensOrders() throws Exception {
        String booking = orderFor(customer, "admin-orders-rbac-00000001");
        call("GET", orders(""), null, null).andExpect(status().isUnauthorized());
        call("GET", orders(""), plain, null).andExpect(status().isForbidden());
        call("GET", orders(""), customer, null).andExpect(status().isForbidden());
        // Catalogue moderation is a different duty: its grant does not open orders, and does not allow actions on them.
        call("GET", orders(""), catalogOnly, null).andExpect(status().isForbidden());
        call("GET", orders("/" + booking), catalogOnly, null).andExpect(status().isForbidden());
        call("POST", orders("/" + booking + "/cancel"), catalogOnly, "{\"expectedVersion\":" + version(booking) + ",\"reason\":\"x\"}").andExpect(status().isForbidden());
        call("POST", orders("/" + booking + "/cancel"), plain, "{\"expectedVersion\":0,\"reason\":\"x\"}").andExpect(status().isForbidden());
        assertThat(statusOf(booking)).isIn("PENDING", "CONFIRMED");
        call("GET", orders(""), ops, null).andExpect(status().isOk());
    }

    @Test
    void registerFiltersPagesAndHidesCustomerContacts() throws Exception {
        String first = orderFor(customer, "admin-orders-list-00000001");
        String number = db.queryForObject("select booking_number from transactions.bookings where id = ?::uuid", String.class, first);

        String all = body(call("GET", orders(""), ops, null).andExpect(status().isOk()).andExpect(jsonPath("$.total").value(1))
                .andExpect(jsonPath("$.items.length()").value(1)).andExpect(jsonPath("$.items[0].id").value(first))
                .andExpect(jsonPath("$.items[0].bookingNumber").value(number)).andExpect(jsonPath("$.items[0].priceMinor").isNumber()));
        // A register of orders never carries customer contact data.
        assertThat(all).doesNotContain(CUSTOMER_PHONE).doesNotContain("Тестовая");

        call("GET", orders("?q=" + number.substring(0, 8).toLowerCase()), ops, null).andExpect(jsonPath("$.total").value(1));
        call("GET", orders("?q=KND-999999"), ops, null).andExpect(jsonPath("$.total").value(0)).andExpect(jsonPath("$.items.length()").value(0));
        call("GET", orders("?q=%27%3B--"), ops, null).andExpect(clientError());  // not a number format: rejected, never reaches SQL
        call("GET", orders("?status=CANCELLED"), ops, null).andExpect(jsonPath("$.total").value(0));
        call("GET", orders("?status=" + statusOf(first)), ops, null).andExpect(jsonPath("$.total").value(1));
        call("GET", orders("?status=BOGUS"), ops, null).andExpect(clientError());
        call("GET", orders("?venueId=" + venueId()), ops, null).andExpect(jsonPath("$.total").value(1));
        call("GET", orders("?venueId=" + UUID.randomUUID()), ops, null).andExpect(jsonPath("$.total").value(0));
        call("GET", orders("?limit=0"), ops, null).andExpect(clientError());
        call("GET", orders("?limit=101"), ops, null).andExpect(clientError());
        call("GET", orders("?limit=1&offset=1"), ops, null).andExpect(jsonPath("$.items.length()").value(0)).andExpect(jsonPath("$.total").value(1));

        String day = JsonPath.read(slots, "$[0].startsAt").toString().substring(0, 10);
        call("GET", orders("?from=" + java.time.LocalDate.parse(day).minusDays(2) + "&to=" + java.time.LocalDate.parse(day).plusDays(1)), ops, null)
                .andExpect(jsonPath("$.total").value(1));
        call("GET", orders("?from=" + java.time.LocalDate.parse(day).plusDays(3)), ops, null).andExpect(jsonPath("$.total").value(0));
    }

    @Test
    void orderCardShowsAddressVisitAndFullHistory() throws Exception {
        String booking = confirm(orderFor(customer, "admin-orders-card-00000001"));
        db.update("insert into marketplace.home_service_visits (booking_id, stage, eta_minutes) values (?::uuid, 'EN_ROUTE', 15)", booking);
        call("GET", orders("/" + booking), ops, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.order.id").value(booking)).andExpect(jsonPath("$.addressText").value("Алматы, ул. Тестовая 1"))
                .andExpect(jsonPath("$.areaSqm").value(50)).andExpect(jsonPath("$.actionable").value(true))
                .andExpect(jsonPath("$.visit.stage").value("EN_ROUTE")).andExpect(jsonPath("$.visit.etaMinutes").value(15))
                .andExpect(jsonPath("$.history.length()").value(org.hamcrest.Matchers.greaterThanOrEqualTo(1)))
                .andExpect(jsonPath("$.adminActions.length()").value(0));
        call("GET", orders("/" + UUID.randomUUID()), ops, null).andExpect(status().isNotFound());
        // An order of another product is not a Home Services order.
        List<String> barber = db.queryForList("select id::text from transactions.bookings where category <> 'CLEANING' limit 1", String.class);
        if (!barber.isEmpty()) { call("GET", orders("/" + barber.get(0)), ops, null).andExpect(status().isNotFound()); }
    }

    @Test
    void staffCancelIsAuditedVersionedAndFreesTheSlot() throws Exception {
        String booking = confirm(orderFor(customer, "admin-orders-cancel-0000001"));
        long version = version(booking);
        String reason = "{\"expectedVersion\":" + version + ",\"reason\":\"Клиент просил отменить по телефону\"}";

        call("POST", orders("/" + booking + "/cancel"), ops, "{\"expectedVersion\":" + version + ",\"reason\":\"  \"}").andExpect(status().isBadRequest());
        call("POST", orders("/" + booking + "/cancel"), ops, "{\"expectedVersion\":" + (version + 5) + ",\"reason\":\"stale\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        assertThat(statusOf(booking)).isEqualTo("CONFIRMED");

        call("POST", orders("/" + booking + "/cancel"), ops, reason).andExpect(status().isOk())
                .andExpect(jsonPath("$.order.status").value("CANCELLED")).andExpect(jsonPath("$.order.cancelledBy").value("ADMIN"))
                .andExpect(jsonPath("$.cancelReason").value("Клиент просил отменить по телефону")).andExpect(jsonPath("$.actionable").value(false))
                .andExpect(jsonPath("$.adminActions[0].action").value("CANCEL"));
        assertThat(version(booking)).isEqualTo(version + 1);
        assertThat(db.queryForObject("select count(*) from transactions.booking_events where booking_id = ?::uuid and status = 'CANCELLED' and actor_type = 'ADMIN' and actor_user_id = ?::uuid",
                Long.class, booking, opsUser)).isEqualTo(1L);
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_admin_events where booking_id = ?::uuid and admin_user_id = ?::uuid and action = 'CANCEL'",
                Long.class, booking, opsUser)).isEqualTo(1L);

        // The customer sees the outcome; a repeated or late action changes nothing; the freed slot can be ordered again.
        call("GET", "/api/v1/booking/bookings/" + booking, customer, null).andExpect(jsonPath("$.status").value("CANCELLED"));
        call("POST", orders("/" + booking + "/cancel"), ops, "{\"expectedVersion\":" + (version + 1) + ",\"reason\":\"again\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("ORDER_NOT_OPERABLE"));
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_admin_events where booking_id = ?::uuid", Long.class, booking)).isEqualTo(1L);
        orderFor(otherCustomer, "admin-orders-cancel-0000002");
    }

    @Test
    void workThatHasStartedCannotBeCancelledOrReassignedByOperations() throws Exception {
        String booking = confirm(orderFor(customer, "admin-orders-started-000001"));
        String other = masterOtherThan(booking);
        for (String state : List.of("IN_PROGRESS", "COMPLETED")) {
            db.update("update transactions.bookings set status = ? where id = ?::uuid", state, booking);
            long version = version(booking);
            call("POST", orders("/" + booking + "/cancel"), ops, "{\"expectedVersion\":" + version + ",\"reason\":\"no\"}").andExpect(status().isConflict())
                    .andExpect(jsonPath("$.code").value("ORDER_NOT_OPERABLE"));
            call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + other + "\",\"expectedVersion\":" + version + ",\"reason\":\"no\"}")
                    .andExpect(status().isConflict());
            assertThat(statusOf(booking)).isEqualTo(state);
        }
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_admin_events", Long.class)).isZero();
    }

    @Test
    void reassignMovesTheOrderToAnotherMasterOfTheSameVenue() throws Exception {
        String booking = confirm(orderFor(customer, "admin-orders-reassign-00001"));
        String oldMaster = db.queryForObject("select master_id::text from transactions.bookings where id = ?::uuid", String.class, booking);
        db.update("update marketplace.booking_masters set user_id = ?::uuid where id = ?::uuid", executorUser, oldMaster);
        db.update("insert into marketplace.home_service_visits (booking_id, stage, eta_minutes) values (?::uuid, 'EN_ROUTE', 10)", booking);
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(jsonPath("$.length()").value(1));

        String options = body(call("GET", orders("/" + booking + "/masters"), ops, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(options, "$")).hasSizeGreaterThanOrEqualTo(2);
        String target = masterOtherThan(booking);
        long version = version(booking);

        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + oldMaster + "\",\"expectedVersion\":" + version + ",\"reason\":\"same\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("MASTER_UNCHANGED"));
        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + UUID.randomUUID() + "\",\"expectedVersion\":" + version + ",\"reason\":\"unknown\"}")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("MASTER_INVALID"));
        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + target + "\",\"expectedVersion\":" + (version + 1) + ",\"reason\":\"stale\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + target + "\",\"expectedVersion\":" + version + "}").andExpect(status().isBadRequest());
        call("POST", orders("/" + booking + "/reassign"), plain, "{\"masterId\":\"" + target + "\",\"expectedVersion\":" + version + ",\"reason\":\"x\"}")
                .andExpect(status().isForbidden());
        assertThat(db.queryForObject("select master_id::text from transactions.bookings where id = ?::uuid", String.class, booking)).isEqualTo(oldMaster);

        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + target + "\",\"expectedVersion\":" + version + ",\"reason\":\"Мастер заболел\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.order.status").value("CONFIRMED"))
                .andExpect(jsonPath("$.adminActions[0].action").value("REASSIGN")).andExpect(jsonPath("$.visit").doesNotExist());
        assertThat(db.queryForObject("select master_id::text from transactions.bookings where id = ?::uuid", String.class, booking)).isEqualTo(target);
        assertThat(db.queryForObject("select master_name from transactions.bookings where id = ?::uuid", String.class, booking))
                .isEqualTo(db.queryForObject("select name from marketplace.booking_masters where id = ?::uuid", String.class, target));
        assertThat(version(booking)).isEqualTo(version + 1);
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_admin_events where booking_id = ?::uuid and from_master_id = ?::uuid and to_master_id = ?::uuid and admin_user_id = ?::uuid",
                Long.class, booking, oldMaster, target, opsUser)).isEqualTo(1L);
        assertThat(db.queryForObject("select count(*) from transactions.booking_events where booking_id = ?::uuid and actor_type = 'ADMIN' and reason like 'REASSIGNED:%'",
                Long.class, booking)).isEqualTo(1L);
        // The previous master no longer sees the job.
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void reassignRefusesAMasterOfAnotherVenueAndABusyMaster() throws Exception {
        String booking = confirm(orderFor(customer, "admin-orders-reassign-00002"));
        long version = version(booking);
        List<String> foreign = db.queryForList("select id::text from marketplace.booking_masters where venue_id <> (select venue_id from transactions.bookings where id = ?::uuid) and active limit 1",
                String.class, booking);
        assertThat(foreign).as("the demo data has masters of other venues").isNotEmpty();
        {
            call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + foreign.get(0) + "\",\"expectedVersion\":" + version + ",\"reason\":\"other venue\"}")
                    .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("MASTER_INVALID"));
        }
        // A master of the venue who does not perform this service is not a valid target (nor offered in the list).
        String target0 = masterOtherThan(booking);
        db.update("delete from marketplace.booking_master_services where master_id = ?::uuid and service_id = (select service_id from transactions.bookings where id = ?::uuid)",
                target0, booking);
        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + target0 + "\",\"expectedVersion\":" + version + ",\"reason\":\"no service\"}")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("MASTER_INVALID"));
        assertThat(body(call("GET", orders("/" + booking + "/masters"), ops, null))).doesNotContain(target0);
        db.update("insert into marketplace.booking_master_services (master_id, service_id) select ?::uuid, service_id from transactions.bookings where id = ?::uuid",
                target0, booking);
        // A deactivated master of the venue is not a valid target either.
        String target = masterOtherThan(booking);
        db.update("update marketplace.booking_masters set active = false where id = ?::uuid", target);
        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + target + "\",\"expectedVersion\":" + version + ",\"reason\":\"inactive\"}")
                .andExpect(status().isUnprocessableEntity());
        db.update("update marketplace.booking_masters set active = true where id = ?::uuid", target);

        // The target master already has a confirmed visit at the same time (a copy of the order for another master; the masters' working
        // hours differ per weekday, so the time is set up directly): the Booking Engine's constraint refuses, nothing changes.
        String busy = masterOtherThan(booking);
        String first = db.queryForObject("select master_id::text from transactions.bookings where id = ?::uuid", String.class, booking);
        db.update("""
                insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name, master_name,
                    duration_minutes, starts_at, ends_at, price_minor, status, idempotency_key, category, address_text, area_sqm)
                select user_id, venue_id, service_id, ?::uuid, venue_name, venue_address, service_name, 'Busy master',
                    duration_minutes, starts_at, ends_at, price_minor, 'CONFIRMED', 'admin-orders-busy-copy-1', category, address_text, area_sqm
                from transactions.bookings where id = ?::uuid
                """, busy, booking);
        call("POST", orders("/" + booking + "/reassign"), ops, "{\"masterId\":\"" + busy + "\",\"expectedVersion\":" + version + ",\"reason\":\"busy\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("MASTER_BUSY"));
        assertThat(version(booking)).isEqualTo(version);
        assertThat(db.queryForObject("select master_id::text from transactions.bookings where id = ?::uuid", String.class, booking)).isEqualTo(first);
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_admin_events", Long.class)).isZero();
    }

    @Test
    void grantsAreSeparateAndRevocationIsImmediate() throws Exception {
        String booking = orderFor(customer, "admin-orders-grants-0000001");
        // Operations grant: orders yes, catalogue moderation no. Catalogue grant: the opposite (covered in onlyTheOperationsGrantOpensOrders).
        call("GET", "/api/v1/admin/home-services/offers", ops, null).andExpect(status().isForbidden());
        call("GET", "/api/v1/admin/home-services/offers", catalogOnly, null).andExpect(status().isOk());
        call("GET", orders("/" + booking), ops, null).andExpect(status().isOk());

        // Revoking takes effect on the very next request with the same token.
        int revoked = db.update("update identity.admin_grants set revoked_at = now(), revoked_by_user_id = ?::uuid where user_id = ?::uuid and permission = 'HOME_SERVICES_OPERATIONS' and revoked_at is null",
                opsUser, opsUser);
        assertThat(revoked).isEqualTo(1);
        call("GET", orders(""), ops, null).andExpect(status().isForbidden());
        call("POST", orders("/" + booking + "/cancel"), ops, "{\"expectedVersion\":" + version(booking) + ",\"reason\":\"after revoke\"}").andExpect(status().isForbidden());
        assertThat(statusOf(booking)).isIn("PENDING", "CONFIRMED");

        // A fresh grant restores access.
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?::uuid, 'HOME_SERVICES_OPERATIONS', 'synthetic re-grant')", opsUser);
        call("GET", orders(""), ops, null).andExpect(status().isOk());
    }

    @Test
    void auditIsAppendOnly() throws Exception {
        String booking = confirm(orderFor(customer, "admin-orders-audit-00000001"));
        call("POST", orders("/" + booking + "/cancel"), ops, "{\"expectedVersion\":" + version(booking) + ",\"reason\":\"audit\"}").andExpect(status().isOk());
        assertThatThrownBy(() -> db.update("update marketplace.home_service_admin_events set reason = 'changed'")).hasMessageContaining("");
        assertThatThrownBy(() -> db.update("delete from marketplace.home_service_admin_events")).hasMessageContaining("");
    }
}
