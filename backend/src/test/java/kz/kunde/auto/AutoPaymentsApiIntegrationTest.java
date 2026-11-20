package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import kz.kunde.booking.BookingDemoSeeder;
import kz.kunde.food.FoodDemoSeeder;
import kz.kunde.partner.PartnerOpsDemoSeeder;
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

/** DEV/TEST payment contract over HTTP against PostgreSQL: hold, capture, void, refund, ledger, guards. No real money, no card data. */
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000801,+77000000802,+77000000803,+77000000804",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class AutoPaymentsApiIntegrationTest {
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    String alice;
    String owner;
    String admin;
    String aliceCar;
    UUID sto;
    UUID partner;

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var r = (method.equals("GET") ? get(path) : method.equals("PUT") ? put(path) : post(path)).contentType(MediaType.APPLICATION_JSON);
        if (json != null) { r.content(json); }
        if (token != null) { r.header("Authorization", "Bearer " + token); }
        if (key != null) { r.header("Idempotency-Key", key); }
        return http.perform(r);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk()));
    }

    private static UUID subject(String loginBody) throws Exception {
        return UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    @BeforeEach
    void setUp() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000801','+77000000802','+77000000803','+77000000804')");
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json", "food/flowers-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json", "auto/demo-venues.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        partner = new PartnerOpsDemoSeeder(db, auth, env).seed();
        alice = JsonPath.read(loginBody("+77000000801"), "$.accessToken");
        owner = JsonPath.read(loginBody("+77000000002"), "$.accessToken");
        String ad = loginBody("+77000000802");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'AUTO_OPERATIONS', 'synthetic DEV admin')", subject(ad));
        admin = JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null, "{\"refreshToken\":\"" + JsonPath.read(ad, "$.refreshToken") + "\"}", null)), "$.accessToken");
        sto = db.queryForObject("select id from marketplace.booking_venues where slug = 'auto-demo-sto'", UUID.class);
        db.update("update marketplace.booking_venues set partner_id = ? where id = ?", partner, sto);
        aliceCar = JsonPath.read(body(send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"Toyota\",\"model\":\"Camry\",\"year\":2018}", null)), "$.id");
    }

    private LocalDate workday() {
        LocalDate d = LocalDate.now(ALMATY).plusDays(3);
        while (d.getDayOfWeek().getValue() == 7) { d = d.plusDays(1); }
        return d;
    }

    private UUID service(String name) { return db.queryForObject("select id from marketplace.booking_services where venue_id = ? and name = ?", UUID.class, sto, name); }

    private List<String> slots(UUID service) throws Exception {
        return JsonPath.read(body(send("GET", "/api/v1/auto/slots?venueId=" + sto + "&serviceId=" + service + "&date=" + workday(), null, null, null)), "$[*].startsAt");
    }

    private String book(String serviceName, int slotIndex, String key, String method) throws Exception {
        UUID svc = service(serviceName);
        String quote = JsonPath.read(body(send("POST", "/api/v1/auto/quotes", alice, "{\"venueId\":\"" + sto + "\",\"serviceId\":\"" + svc + "\",\"vehicleId\":\""
                + aliceCar + "\",\"startsAt\":\"" + slots(svc).get(slotIndex) + "\"}", null).andExpect(status().isCreated())), "$.id");
        return body(send("POST", "/api/v1/auto/bookings", alice, "{\"quoteId\":\"" + quote + "\"" + (method == null ? "" : ",\"paymentMethod\":\"" + method + "\"") + "}", key)
                .andExpect(status().isCreated()));
    }

    private String action(String booking, String action, String extra) throws Exception {
        return body(send("POST", "/api/v1/partner/partners/" + partner + "/booking/bookings/" + booking + "/action", owner,
                "{\"action\":\"" + action + "\"" + (extra == null ? "" : "," + extra) + "}", null).andExpect(status().isOk()));
    }

    private List<String> ledger(String bookingId) {
        return db.queryForList("select e.kind from transactions.auto_payment_events e join transactions.auto_payments p on p.id = e.payment_id where p.booking_id = ?::uuid order by e.id",
                String.class, bookingId);
    }

    @Test
    void payOnSiteMovesNoMoneyAndUnknownMethodsAreRefused() throws Exception {
        String b = book("Шиномонтаж (4 колеса)", 0, "pay-key-000000000001", null);
        assertThat((String) JsonPath.read(b, "$.payment.method")).isEqualTo("PAY_ON_SITE");
        assertThat((Integer) JsonPath.read(b, "$.payment.heldMinor")).isZero();
        assertThat(ledger(JsonPath.read(b, "$.id"))).isEmpty();
        UUID svc = service("Замена масла");
        String quote = JsonPath.read(body(send("POST", "/api/v1/auto/quotes", alice, "{\"venueId\":\"" + sto + "\",\"serviceId\":\"" + svc + "\",\"vehicleId\":\"" + aliceCar
                + "\",\"startsAt\":\"" + slots(svc).get(8) + "\"}", null)), "$.id");
        send("POST", "/api/v1/auto/bookings", alice, "{\"quoteId\":\"" + quote + "\",\"paymentMethod\":\"CRYPTO\"}", "pay-key-000000000002")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PAYMENT_METHOD_UNSUPPORTED"));
        assertThat(db.queryForObject("select count(*) from transactions.bookings where category = 'AUTO'", Integer.class)).isEqualTo(1);
    }

    @Test
    void testCardIsHeldThenCapturedAtTheApprovedFinalPrice() throws Exception {
        String b = book("Замена масла", 0, "pay-key-000000000011", "TEST_CARD");
        String id = JsonPath.read(b, "$.id");
        assertThat((String) JsonPath.read(b, "$.payment.status")).isEqualTo("TEST_HELD");
        assertThat((String) JsonPath.read(b, "$.payment.mode")).isEqualTo("DEV_TEST");
        assertThat((Integer) JsonPath.read(b, "$.payment.heldMinor")).isEqualTo(1200000);
        action(id, "CONFIRM", null);
        action(id, "CHECK_IN", null);
        action(id, "START", null);
        action(id, "PROPOSE_PRICE", "\"finalPriceMinor\":1450000");
        send("POST", "/api/v1/auto/bookings/" + id + "/price-decision", alice, "{\"approve\":true}", null).andExpect(status().isOk());
        action(id, "COMPLETE", null);
        action(id, "COMPLETE", null); // idempotent repeat must not capture twice
        String done = body(send("GET", "/api/v1/auto/bookings/" + id, alice, null, null));
        assertThat((String) JsonPath.read(done, "$.payment.status")).isEqualTo("TEST_CAPTURED");
        assertThat((Integer) JsonPath.read(done, "$.payment.capturedMinor")).isEqualTo(1450000);
        assertThat(ledger(id)).containsExactly("HOLD", "CAPTURE");
    }

    @Test
    void holdsAreReleasedOnCancelRejectNoShowAndUnansweredRequests() throws Exception {
        String cancelled = JsonPath.read(book("Замена масла", 1, "pay-key-000000000021", "TEST_CARD"), "$.id");
        send("POST", "/api/v1/auto/bookings/" + cancelled + "/cancel", alice, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.payment.status").value("TEST_VOIDED"));
        send("POST", "/api/v1/auto/bookings/" + cancelled + "/cancel", alice, null, null).andExpect(status().isOk());
        assertThat(ledger(cancelled)).containsExactly("HOLD", "VOID");
        String rejected = JsonPath.read(book("Замена масла", 2, "pay-key-000000000022", "TEST_CARD"), "$.id");
        action(rejected, "REJECT", "\"reason\":\"Нет запчастей\"");
        assertThat(ledger(rejected)).containsExactly("HOLD", "VOID");
        String noShow = JsonPath.read(book("Замена масла", 3, "pay-key-000000000023", "TEST_CARD"), "$.id");
        action(noShow, "CONFIRM", null);
        db.update("update transactions.bookings set starts_at = now() - interval '2 hours', ends_at = now() - interval '75 minutes' where id = ?::uuid", noShow);
        action(noShow, "NO_SHOW", null);
        assertThat(ledger(noShow)).containsExactly("HOLD", "VOID");
        String stale = JsonPath.read(book("Замена масла", 4, "pay-key-000000000024", "TEST_CARD"), "$.id");
        db.update("update transactions.bookings set starts_at = now() - interval '3 hours', ends_at = now() - interval '2 hours' where id = ?::uuid", stale);
        send("GET", "/api/v1/auto/bookings/" + stale, alice, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.payment.status").value("TEST_VOIDED"));
        assertThat((String) db.queryForObject("select status from transactions.auto_payments where booking_id = ?::uuid", String.class, noShow)).isEqualTo("TEST_VOIDED");
    }

    @Test
    void adminRefundsAreBoundedAuditedAndRestrictedToCapturedTestPayments() throws Exception {
        String id = JsonPath.read(book("Замена масла", 5, "pay-key-000000000031", "TEST_CARD"), "$.id");
        UUID payment = db.queryForObject("select id from transactions.auto_payments where booking_id = ?::uuid", UUID.class, id);
        String refund = "{\"amountMinor\":300000,\"reason\":\"Скидка за задержку\"}";
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, refund, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PAYMENT_NOT_REFUNDABLE"));
        action(id, "CONFIRM", null);
        action(id, "CHECK_IN", null);
        action(id, "START", null);
        action(id, "COMPLETE", null);
        send("GET", "/api/v1/admin/auto/payments?refundableOnly=true", alice, null, null).andExpect(status().isForbidden());
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", alice, refund, null).andExpect(status().isForbidden());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/admin/auto/payments?refundableOnly=true", admin, null, null).andExpect(status().isOk())), "$")).hasSize(1);
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, "{\"amountMinor\":300000,\"reason\":\"\"}", null).andExpect(status().isBadRequest());
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, "{\"amountMinor\":0,\"reason\":\"x\"}", null).andExpect(status().isBadRequest());
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, "{\"amountMinor\":9999999,\"reason\":\"слишком много\"}", null)
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("REFUND_AMOUNT_INVALID"));
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, refund, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("TEST_PART_REFUNDED")).andExpect(jsonPath("$.refundedMinor").value(300000));
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, "{\"amountMinor\":900001,\"reason\":\"выше остатка\"}", null).andExpect(status().isBadRequest());
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, "{\"amountMinor\":900000,\"reason\":\"остаток\"}", null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("TEST_REFUNDED"));
        send("POST", "/api/v1/admin/auto/payments/" + payment + "/refund", admin, refund, null).andExpect(status().isConflict());
        assertThat(ledger(id)).containsExactly("HOLD", "CAPTURE", "REFUND", "REFUND");
        assertThat(db.queryForObject("select count(*) from marketplace.auto_admin_events where action = 'PAYMENT_REFUNDED'", Integer.class)).isEqualTo(2);
        // the ledger is append-only and the database refuses a refund above the captured amount
        org.junit.jupiter.api.Assertions.assertThrows(org.springframework.dao.DataAccessException.class, () -> db.update("delete from transactions.auto_payment_events"));
    }

    @Test
    void roadsideJobPaymentIsHeldAndCapturedAtTheApprovedPrice() throws Exception {
        String spec = JsonPath.read(loginBody("+77000000803"), "$.accessToken");
        UUID specId = subject(loginBody("+77000000803"));
        send("POST", "/api/v1/executor/auto/profile", spec, "{\"name\":\"Специалист\"}", null).andExpect(status().isOk());
        send("POST", "/api/v1/admin/auto/specialists/" + specId + "/decision", admin, "{\"approve\":true,\"categories\":[\"ROADSIDE\"],\"reason\":\"Проверен\"}", null).andExpect(status().isOk());
        send("PUT", "/api/v1/executor/auto/availability", spec, "{\"online\":true}", null).andExpect(status().isOk());
        send("PUT", "/api/v1/executor/auto/location", spec, "{\"latitude\":43.2389,\"longitude\":76.8897}", null).andExpect(status().isNoContent());
        String job = JsonPath.read(body(send("POST", "/api/v1/auto/jobs", alice, "{\"vehicleId\":\"" + aliceCar + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Тестовая 5\","
                + "\"latitude\":43.25,\"longitude\":76.9,\"paymentMethod\":\"TEST_CARD\"}", "job-pay-key-0000001").andExpect(status().isCreated()).andExpect(jsonPath("$.payment.status").value("TEST_HELD"))), "$.id");
        for (String a : new String[] {"accept"}) { send("POST", "/api/v1/executor/auto/jobs/" + job + "/" + a, spec, null, null).andExpect(status().isOk()); }
        for (String a : new String[] {"ARRIVE", "START"}) { send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", spec, "{\"action\":\"" + a + "\"}", null).andExpect(status().isOk()); }
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", spec, "{\"action\":\"PROPOSE_PRICE\",\"finalPriceMinor\":2200000}", null).andExpect(status().isOk());
        send("POST", "/api/v1/auto/jobs/" + job + "/price-decision", alice, "{\"approve\":true}", null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/auto/jobs/" + job + "/progress", spec, "{\"action\":\"COMPLETE\"}", null).andExpect(status().isOk());
        String done = body(send("GET", "/api/v1/auto/jobs/" + job, alice, null, null));
        assertThat((String) JsonPath.read(done, "$.payment.status")).isEqualTo("TEST_CAPTURED");
        assertThat((Integer) JsonPath.read(done, "$.payment.capturedMinor")).isEqualTo(2200000);
        // a cancelled job releases the hold
        UUID car2 = UUID.fromString(JsonPath.read(body(send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"Kia\",\"model\":\"Rio\",\"year\":2012}", null)), "$.id"));
        String second = JsonPath.read(body(send("POST", "/api/v1/auto/jobs", alice, "{\"vehicleId\":\"" + car2 + "\",\"category\":\"ROADSIDE\",\"addressText\":\"Алматы, ул. Другая 1\","
                + "\"latitude\":43.25,\"longitude\":76.9,\"paymentMethod\":\"TEST_CARD\"}", "job-pay-key-0000002").andExpect(status().isCreated())), "$.id");
        send("POST", "/api/v1/auto/jobs/" + second + "/cancel", alice, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.payment.status").value("TEST_VOIDED"));
    }
}
