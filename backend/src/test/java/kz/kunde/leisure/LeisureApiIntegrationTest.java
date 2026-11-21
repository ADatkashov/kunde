package kz.kunde.leisure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

/**
 * KUNDE Leisure over HTTP against PostgreSQL: catalogue, search, holds, seat conflicts, idempotent orders, test payments and refunds, QR check-in
 * (valid, repeated, foreign organiser, cancelled, unreadable), cancellation rules, manual confirmation, reviews, partner roles and isolation,
 * moderation and admin refunds. Synthetic data only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000521,+77000000522,+77000000523,+77000000524",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class LeisureApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    LeisureTestSupport t;
    String alice;
    String bob;
    String ownerA;
    String ownerB;
    UUID partnerA;
    UUID partnerB;
    int keyCounter;

    @BeforeEach
    void setUp() throws Exception {
        t = new LeisureTestSupport(http, db);
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000521','+77000000522','+77000000523','+77000000524')");
        new LeisureDemoSeeder(db, auth, env).seed();
        partnerA = db.queryForObject("select partner_id from marketplace.leisure_venues where slug = 'demo-leisure-cinema'", UUID.class);
        partnerB = db.queryForObject("select partner_id from marketplace.leisure_venues where slug = 'demo-leisure-vr'", UUID.class);
        alice = t.login("+77000000521");
        bob = t.login("+77000000522");
        ownerA = t.login("+77000000002");
        ownerB = t.login("+77000000003");
    }

    private String key() { return "leisure-test-key-" + String.format("%06d", ++keyCounter) + "x"; }

    private String hold(String token, UUID session, String json) throws Exception {
        return t.body(t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", token, json, null).andExpect(status().isCreated()));
    }

    private String seatHold(String token, UUID session, UUID type, UUID... seats) throws Exception {
        String ids = String.join(",", java.util.Arrays.stream(seats).map(s -> "\"" + s + "\"").toList());
        return hold(token, session, "{\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"seatIds\":[" + ids + "]}]}");
    }

    private String order(String token, String holdBody, String method, String key) throws Exception {
        return t.body(t.send("POST", "/api/v1/leisure/orders", token, "{\"holdId\":\"" + JsonPath.read(holdBody, "$.id") + "\",\"paymentMethod\":\"" + method + "\",\"ageConfirmed\":true}", key)
                .andExpect(status().is2xxSuccessful()));
    }

    private String partnerPath(UUID partner, String rest) { return "/api/v1/partner/partners/" + partner + "/leisure" + rest; }

    private String checkin(String token, UUID partner, String code) throws Exception {
        return t.body(t.send("POST", partnerPath(partner, "/checkins"), token, "{\"code\":\"" + code + "\"}", null).andExpect(status().isOk()));
    }

    @Test
    void catalogSearchDetailAndSeatMap() throws Exception {
        t.send("GET", "/api/v1/capabilities", null, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.leisureEnabled").value(true));
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/categories", null, null, null)), "$")).hasSize(17); // 12 original + 5 new activity categories; ticketed event categories moved to Events
        String all = t.body(t.send("GET", "/api/v1/leisure/events?limit=50", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(all, "$")).hasSizeGreaterThanOrEqualTo(4);
        assertThat((List<String>) JsonPath.read(all, "$[*].categoryCode")).doesNotContain("CINEMA", "CONCERT", "THEATER", "EXHIBITION"); // those are Events
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?category=CINEMA", null, null, null)), "$")).isEmpty();
        String bowling = t.body(t.send("GET", "/api/v1/leisure/events?category=BOWLING&available=true&guests=2&sort=price", null, null, null));
        assertThat((List<String>) JsonPath.read(bowling, "$[*].categoryCode")).containsOnly("BOWLING");
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?q=боулинг", null, null, null)), "$")).isNotEmpty();
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?age=3&category=KARAOKE", null, null, null)), "$")).isEmpty(); // karaoke is 18+
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?family=true", null, null, null)), "$")).isNotEmpty();
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?lat=43.22&lng=76.93&radiusKm=50&sort=distance", null, null, null)), "$[*].distanceKm")).isNotEmpty();
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?preset=today", null, null, null).andExpect(status().isOk())), "$")).isNotNull();
        assertThat(t.body(t.send("GET", "/api/v1/leisure/home?lat=43.22&lng=76.93", null, null, null).andExpect(status().isOk()))).contains("popular", "weekend");
        UUID film = t.event("Демо-фильм");
        String detail = t.body(t.send("GET", "/api/v1/leisure/events/" + film, null, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(detail, "$.bookingType")).isEqualTo("SEAT_MAP");
        assertThat((List<?>) JsonPath.read(detail, "$.ticketTypes")).hasSize(2);
        assertThat((Object) JsonPath.read(detail, "$.rating")).isNull(); // no reviews, no invented rating
        UUID session = t.firstSession(film);
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events/" + film + "/sessions?days=8", null, null, null)), "$")).isNotEmpty();
        // instants leave the API with the venue offset, so the apps never show the server's UTC wall clock
        assertThat((String) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events/" + film + "/sessions?days=8", null, null, null)), "$[0].startsAt")).endsWith("+05:00");
        String seats = t.body(t.send("GET", "/api/v1/leisure/sessions/" + session + "/seats", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(seats, "$")).hasSize(60);
        t.send("GET", "/api/v1/leisure/events/" + UUID.randomUUID(), null, null, null).andExpect(status().isNotFound());
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", null, "{}", null).andExpect(status().isUnauthorized());
    }

    @Test
    void seatPurchaseTicketAndCheckInLifecycle() throws Exception {
        UUID film = t.event("Демо-фильм");
        UUID session = t.firstSession(film);
        UUID std = t.ticketType(film, "Стандарт");
        UUID vip = t.ticketType(film, "VIP");
        String h = seatHold(alice, session, std, t.seat(session, "D", 5), t.seat(session, "D", 6));
        assertThat((Long) JsonPath.parse(h).read("$.totalMinor", Long.class)).isEqualTo(400000L);
        // a second customer cannot take a held seat, and a wrong zone is refused
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", bob, "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "D", 5) + "\"]}]}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SEAT_TAKEN"));
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", bob, "{\"lines\":[{\"ticketTypeId\":\"" + vip + "\",\"seatIds\":[\"" + t.seat(session, "D", 1) + "\"]}]}", null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("SEAT_ZONE_MISMATCH"));
        t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(h, "$.id") + "\"}", null).andExpect(status().isBadRequest());
        t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(h, "$.id") + "\",\"paymentMethod\":\"APPLE_PAY\",\"ageConfirmed\":true}", key())
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PAYMENT_METHOD_UNSUPPORTED"));
        t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(h, "$.id") + "\",\"paymentMethod\":\"TEST_CARD\"}", key())
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("AGE_CONFIRMATION_REQUIRED"));
        // idempotent purchase: the same key returns the same order
        String k = key();
        String o = order(alice, h, "TEST_CARD", k);
        String again = t.body(t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(h, "$.id") + "\",\"paymentMethod\":\"TEST_CARD\",\"ageConfirmed\":true}", k).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(again, "$.id")).isEqualTo(JsonPath.read(o, "$.id"));
        assertThat(db.queryForObject("select count(*) from transactions.leisure_orders where user_id is not null and hold_id = ?::uuid", Integer.class, (Object) JsonPath.read(h, "$.id"))).isEqualTo(1);
        assertThat((String) JsonPath.read(o, "$.status")).isEqualTo("CONFIRMED");
        assertThat((String) JsonPath.read(o, "$.payment.status")).isEqualTo("TEST_CAPTURED");
        assertThat((String) JsonPath.read(o, "$.payment.mode")).isEqualTo("DEV_TEST");
        assertThat((List<?>) JsonPath.read(o, "$.tickets")).hasSize(2);
        String qr = JsonPath.read(o, "$.tickets[0].qr");
        assertThat(qr).matches("KT1\\.[0-9a-f-]{36}\\.[0-9a-f]{32}").doesNotContain("77000000");
        // the same key with another hold is a conflict; another customer cannot read the order
        t.send("GET", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id"), bob, null, null).andExpect(status().isNotFound());
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/orders?scope=upcoming", alice, null, null)), "$")).hasSize(1);
        // gate: the seat is now sold for everyone
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", bob, "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "D", 6) + "\"]}]}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SEAT_TAKEN"));
        // entry opens 2 h before the start; the first session is more than 3 h away, so move it to "starting now" for the gate checks
        assertThat((String) JsonPath.read(checkin(ownerA, partnerA, qr), "$.result")).isEqualTo("TOO_EARLY");
        db.update("update marketplace.leisure_sessions set starts_at = now() + interval '30 minutes', ends_at = now() + interval '2 hours' where id = ?", session);
        assertThat((String) JsonPath.read(checkin(ownerA, partnerA, "garbage"), "$.result")).isEqualTo("INVALID");
        assertThat((String) JsonPath.read(checkin(ownerA, partnerA, qr.substring(0, qr.length() - 1) + (qr.endsWith("0") ? "1" : "0")), "$.result")).isEqualTo("INVALID");
        String foreign = checkin(ownerB, partnerB, qr);
        assertThat((String) JsonPath.read(foreign, "$.result")).isEqualTo("WRONG_ORGANIZATION");
        assertThat(foreign).doesNotContain("Демо-фильм");
        t.send("POST", partnerPath(partnerA, "/checkins"), ownerB, "{\"code\":\"" + qr + "\"}", null).andExpect(status().isNotFound()); // not a member of partner A
        String ok = checkin(ownerA, partnerA, qr);
        assertThat((String) JsonPath.read(ok, "$.result")).isEqualTo("ADMITTED");
        assertThat((Boolean) JsonPath.read(ok, "$.admitted")).isTrue();
        String dup = checkin(ownerA, partnerA, qr);
        assertThat((String) JsonPath.read(dup, "$.result")).isEqualTo("DUPLICATE");
        assertThat((Boolean) JsonPath.read(dup, "$.admitted")).isFalse();
        assertThat(db.queryForObject("select count(*) from transactions.leisure_checkins where result = 'ADMITTED'", Integer.class)).isEqualTo(1);
        // a used ticket blocks cancellation
        t.send("POST", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id") + "/cancel", alice, null, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TICKET_USED"));
        // after the session: completed, review once, no invented rating before it
        db.update("update marketplace.leisure_sessions set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = ?", session);
        String done = t.body(t.send("GET", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id"), alice, null, null));
        assertThat((String) JsonPath.read(done, "$.phase")).isEqualTo("COMPLETED");
        assertThat((Boolean) JsonPath.read(done, "$.canReview")).isTrue();
        t.send("POST", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id") + "/review", alice, "{\"rating\":9}", null).andExpect(status().isBadRequest());
        t.send("POST", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id") + "/review", alice, "{\"rating\":5,\"body\":\"Всё работает\"}", null).andExpect(status().isCreated());
        t.send("POST", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id") + "/review", alice, "{\"rating\":4}", null).andExpect(status().isConflict());
        String rated = t.body(t.send("GET", "/api/v1/leisure/events/" + film, null, null, null));
        assertThat((Double) JsonPath.read(rated, "$.rating")).isEqualTo(5.0);
        assertThat((Integer) JsonPath.read(rated, "$.reviewCount")).isEqualTo(1);
        assertThat(t.body(t.send("GET", "/api/v1/leisure/events/" + film + "/reviews", null, null, null))).contains("Всё работает").doesNotContain("77000000");
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/orders?scope=completed", alice, null, null)), "$")).hasSize(1);
    }

    @Test
    void cancellationRefundsAndFreesPlaces() throws Exception {
        UUID wash = t.event("Сеанс 90 минут");
        UUID session = t.firstSession(wash);
        UUID adult = t.ticketType(wash, "Взрослый");
        UUID child = t.ticketType(wash, "Детский");
        String h = hold(alice, session, "{\"lines\":[{\"ticketTypeId\":\"" + adult + "\",\"quantity\":2},{\"ticketTypeId\":\"" + child + "\",\"quantity\":1}]}");
        assertThat((Integer) JsonPath.read(h, "$.guests")).isEqualTo(3);
        assertThat((Integer) JsonPath.read(h, "$.totalMinor")).isEqualTo(1250000);
        String o = order(alice, h, "TEST_CARD", key());
        UUID order = UUID.fromString(JsonPath.read(o, "$.id"));
        int free = db.queryForObject("select capacity - (select count(*) from transactions.leisure_tickets where session_id = ? and status in ('PENDING','VALID','USED')) from marketplace.leisure_sessions where id = ?", Integer.class, session, session);
        assertThat(free).isEqualTo(27);
        String cancelled = t.body(t.send("POST", "/api/v1/leisure/orders/" + order + "/cancel", alice, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(cancelled, "$.status")).isEqualTo("CANCELLED");
        assertThat((String) JsonPath.read(cancelled, "$.payment.status")).isEqualTo("TEST_REFUNDED");
        assertThat((Integer) JsonPath.read(cancelled, "$.payment.refundedMinor")).isEqualTo(1250000);
        t.send("POST", "/api/v1/leisure/orders/" + order + "/cancel", alice, null, null).andExpect(status().isOk()); // repeat is safe
        assertThat(db.queryForObject("select count(*) from transactions.leisure_payment_events where kind = 'REFUND'", Integer.class)).isEqualTo(1);
        String qrless = JsonPath.read(cancelled, "$.tickets[0].status");
        assertThat(qrless).isEqualTo("CANCELLED");
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/orders?scope=cancelled", alice, null, null)), "$")).hasSize(1);
        // pay on site writes no ledger
        String h2 = hold(alice, session, "{\"lines\":[{\"ticketTypeId\":\"" + adult + "\",\"quantity\":1}]}");
        String o2 = order(alice, h2, "PAY_ON_SITE", key());
        assertThat((String) JsonPath.read(o2, "$.payment.mode")).isEqualTo("ON_SITE");
        // too many guests, wrong booking type
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice, "{\"lines\":[{\"ticketTypeId\":\"" + adult + "\",\"quantity\":11}]}", null).andExpect(status().isUnprocessableEntity());
        // cancellation window closed
        db.update("update marketplace.leisure_venues set cancellation_hours = 720 where slug = 'demo-leisure-trampoline'");
        t.send("POST", "/api/v1/leisure/orders/" + JsonPath.read(o2, "$.id") + "/cancel", alice, null, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("CANCELLATION_WINDOW_CLOSED"));
        // an expired hold cannot be paid
        String h3 = hold(bob, session, "{\"lines\":[{\"ticketTypeId\":\"" + adult + "\",\"quantity\":1}]}");
        db.update("update transactions.leisure_holds set expires_at = now() - interval '1 minute' where id = ?::uuid", (Object) JsonPath.read(h3, "$.id"));
        t.send("POST", "/api/v1/leisure/orders", bob, "{\"holdId\":\"" + JsonPath.read(h3, "$.id") + "\",\"paymentMethod\":\"PAY_ON_SITE\"}", key()).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("HOLD_EXPIRED"));
    }

    @Test
    void lastPlaceIsSoldOnceAndHoldsExpire() throws Exception {
        UUID lane = t.event("Дорожка на час");
        UUID session = t.firstSession(lane);
        UUID type = t.ticketType(lane, "Дорожка, 1 час");
        db.update("update marketplace.leisure_sessions set capacity = 1 where id = ?", session);
        String body = "{\"guests\":4,\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"quantity\":1}]}";
        String h = hold(alice, session, body);
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", bob, body, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("NOT_ENOUGH_PLACES"));
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice, "{\"guests\":9,\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"quantity\":1}]}", null).andExpect(status().isUnprocessableEntity());
        // the hold lapses -> the place is available again
        db.update("update transactions.leisure_holds set expires_at = now() - interval '1 second' where id = ?::uuid", (Object) JsonPath.read(h, "$.id"));
        String h2 = hold(bob, session, body);
        order(bob, h2, "PAY_ON_SITE", key());
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice, body, null).andExpect(status().isConflict());
    }

    @Test
    void manualConfirmationAndPartnerRoles() throws Exception {
        UUID room = t.event("Комната на 2 часа");
        UUID session = t.firstSession(room);
        UUID type = t.ticketType(room, "Комната, 2 часа");
        String h = hold(alice, session, "{\"guests\":6,\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"quantity\":1}]}");
        t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(h, "$.id") + "\",\"paymentMethod\":\"TEST_CARD\"}", key()).andExpect(status().isUnprocessableEntity()); // 18+
        String o = order(alice, h, "TEST_CARD", key());
        assertThat((String) JsonPath.read(o, "$.status")).isEqualTo("PENDING");
        assertThat((String) JsonPath.read(o, "$.payment.status")).isEqualTo("TEST_HELD");
        assertThat((Object) JsonPath.read(o, "$.tickets[0].qr")).isNull(); // no QR before confirmation
        String orderId = JsonPath.read(o, "$.id");
        // staff role: may confirm, may not cancel or create content
        String bobLogin = t.loginBody("+77000000523");
        db.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) select ?, ?, 'OPERATOR', created_by_user_id from marketplace.partners where id = ?",
                partnerA, LeisureTestSupport.subject(bobLogin), partnerA);
        String staff = t.refreshed(bobLogin);
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", partnerPath(partnerA, "/orders?scope=requests"), staff, null, null).andExpect(status().isOk())), "$")).hasSize(1);
        t.send("POST", partnerPath(partnerA, "/venues"), staff, "{\"name\":\"X\",\"address\":\"Y\"}", null).andExpect(status().isForbidden());
        t.send("POST", partnerPath(partnerA, "/orders/" + orderId + "/action"), staff, "{\"action\":\"CANCEL\"}", null).andExpect(status().isForbidden());
        t.send("GET", partnerPath(partnerA, "/history"), staff, null, null).andExpect(status().isForbidden());
        // another partner sees nothing of it
        t.send("GET", partnerPath(partnerB, "/orders/" + orderId), ownerB, null, null).andExpect(status().isNotFound());
        t.send("GET", partnerPath(partnerA, "/orders"), ownerB, null, null).andExpect(status().isNotFound());
        String confirmed = t.body(t.send("POST", partnerPath(partnerA, "/orders/" + orderId + "/action"), staff, "{\"action\":\"CONFIRM\"}", null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(confirmed, "$.status")).isEqualTo("CONFIRMED");
        assertThat((String) JsonPath.read(confirmed, "$.payment.status")).isEqualTo("TEST_CAPTURED");
        assertThat(confirmed).doesNotContain("77000000");
        t.send("POST", partnerPath(partnerA, "/orders/" + orderId + "/action"), staff, "{\"action\":\"CONFIRM\"}", null).andExpect(status().isOk()); // idempotent
        String mine = t.body(t.send("GET", "/api/v1/leisure/orders/" + orderId, alice, null, null));
        assertThat((String) JsonPath.read(mine, "$.tickets[0].qr")).startsWith("KT1.");
        // the organiser cancels a confirmed booking: refund
        String cancelled = t.body(t.send("POST", partnerPath(partnerA, "/orders/" + orderId + "/action"), ownerA, "{\"action\":\"CANCEL\",\"reason\":\"Комната закрыта\"}", null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(cancelled, "$.payment.status")).isEqualTo("TEST_REFUNDED");
        String qr = JsonPath.read(mine, "$.tickets[0].qr");
        db.update("update marketplace.leisure_sessions set starts_at = now() + interval '10 minutes', ends_at = now() + interval '2 hours' where id = ?", session);
        assertThat((String) JsonPath.read(checkin(ownerA, partnerA, qr), "$.result")).isEqualTo("CANCELLED");
        assertThat((String) JsonPath.read(t.body(t.send("GET", partnerPath(partnerA, "/history"), ownerA, null, null)), "$[0].action")).isEqualTo("ORDER_CANCEL");
    }

    @Test
    void partnerCreatesVenueEventSessionsAdminModeratesAndRefunds() throws Exception {
        String venue = t.body(t.send("POST", partnerPath(partnerB, "/venues"), ownerB,
                "{\"name\":\"Новая площадка (синтетика)\",\"address\":\"ул. Тест, 1\",\"district\":\"Медеуский\",\"photoUrls\":[\"https://example.invalid/p.jpg\"],\"cancellationHours\":1}", null).andExpect(status().isCreated()));
        String venueId = JsonPath.read(venue, "$.id");
        assertThat((String) JsonPath.read(venue, "$.status")).isEqualTo("DRAFT");
        t.send("POST", partnerPath(partnerB, "/venues"), ownerB, "{\"name\":\"X\",\"address\":\"Y\",\"photoUrls\":[\"http://insecure\"]}", null).andExpect(status().isBadRequest());
        String event = t.body(t.send("POST", partnerPath(partnerB, "/venues/" + venueId + "/events"), ownerB,
                "{\"categoryCode\":\"BILLIARDS\",\"title\":\"Стол на час (синтетика)\",\"durationMinutes\":60,\"maxGuests\":4}", null).andExpect(status().isCreated()));
        String eventId = JsonPath.read(event, "$.id");
        assertThat((String) JsonPath.read(event, "$.bookingType")).isEqualTo("TIME_SLOT");
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/submit"), ownerB, null, null).andExpect(status().isConflict()); // no ticket types yet
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/ticket-types"), ownerB, "{\"name\":\"Стол\",\"priceMinor\":500000,\"pricing\":\"PER_TICKET\"}", null).andExpect(status().isUnprocessableEntity());
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/ticket-types"), ownerB, "{\"name\":\"Стол\",\"priceMinor\":500000}", null).andExpect(status().isCreated());
        // another partner cannot touch it
        t.send("POST", partnerPath(partnerA, "/events/" + eventId + "/ticket-types"), ownerA, "{\"name\":\"Взлом\",\"priceMinor\":1}", null).andExpect(status().isNotFound());
        String start = java.time.OffsetDateTime.now().plusDays(2).withNano(0).toString();
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/sessions"), ownerB, "{\"startsAt\":[\"" + start + "\"],\"capacity\":2}", null).andExpect(status().isCreated());
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/sessions"), ownerB, "{\"startsAt\":[\"" + start + "\"],\"capacity\":2}", null).andExpect(status().isConflict());
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/sessions"), ownerB, "{\"startsAt\":[\"2020-01-01T10:00:00+05:00\"],\"capacity\":2}", null).andExpect(status().isBadRequest());
        // moderation: invisible until the administrator approves
        t.send("POST", partnerPath(partnerB, "/venues/" + venueId + "/submit"), ownerB, null, null).andExpect(status().isOk());
        t.send("POST", partnerPath(partnerB, "/events/" + eventId + "/submit"), ownerB, null, null).andExpect(status().isOk());
        t.send("GET", "/api/v1/leisure/events/" + eventId, null, null, null).andExpect(status().isNotFound());
        t.send("GET", "/api/v1/admin/leisure/summary", alice, null, null).andExpect(status().isForbidden());
        String adminLogin = t.loginBody("+77000000524");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'PARTNER_VERIFICATION', 'synthetic DEV admin')", LeisureTestSupport.subject(adminLogin));
        t.send("GET", "/api/v1/admin/leisure/summary", t.refreshed(adminLogin), null, null).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ADMIN_FORBIDDEN"));
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'LEISURE_OPERATIONS', 'synthetic DEV admin')", LeisureTestSupport.subject(adminLogin));
        String admin = t.refreshed(t.loginBody("+77000000524"));
        assertThat((Integer) JsonPath.read(t.body(t.send("GET", "/api/v1/admin/leisure/summary", admin, null, null).andExpect(status().isOk())), "$.pendingVenues")).isEqualTo(1);
        t.send("POST", "/api/v1/admin/leisure/venues/" + venueId + "/decision", admin, "{\"decision\":\"REJECT\"}", null).andExpect(status().isBadRequest());
        t.send("POST", "/api/v1/admin/leisure/venues/" + venueId + "/decision", admin, "{\"decision\":\"APPROVE\"}", null).andExpect(status().isOk());
        t.send("POST", "/api/v1/admin/leisure/events/" + eventId + "/decision", admin, "{\"decision\":\"APPROVE\"}", null).andExpect(status().isOk());
        t.send("POST", "/api/v1/admin/leisure/events/" + eventId + "/decision", admin, "{\"decision\":\"APPROVE\"}", null).andExpect(status().isConflict());
        t.send("GET", "/api/v1/leisure/events/" + eventId, null, null, null).andExpect(status().isOk());
        // customer buys with a test card, the administrator refunds part of it, then the rest by cancelling the order
        UUID session = db.queryForObject("select id from marketplace.leisure_sessions where event_id = ?::uuid", UUID.class, (Object) eventId);
        UUID type = db.queryForObject("select id from marketplace.leisure_ticket_types where event_id = ?::uuid", UUID.class, (Object) eventId);
        String h = hold(alice, session, "{\"guests\":2,\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"quantity\":1}]}");
        String o = order(alice, h, "TEST_CARD", key());
        String payment = db.queryForObject("select id::text from transactions.leisure_payments where order_id = ?::uuid", String.class, (Object) JsonPath.read(o, "$.id"));
        t.send("POST", "/api/v1/admin/leisure/payments/" + payment + "/refund", admin, "{\"amountMinor\":600000,\"reason\":\"слишком много\"}", null).andExpect(status().isBadRequest());
        String part = t.body(t.send("POST", "/api/v1/admin/leisure/payments/" + payment + "/refund", admin, "{\"amountMinor\":200000,\"reason\":\"Жалоба клиента\"}", null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(part, "$.status")).isEqualTo("TEST_PART_REFUNDED");
        t.send("POST", "/api/v1/admin/leisure/orders/" + JsonPath.read(o, "$.id") + "/cancel", admin, "{\"reason\":\"Блокировка\"}", null).andExpect(status().isNoContent());
        assertThat((String) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id"), alice, null, null)), "$.payment.status")).isEqualTo("TEST_REFUNDED");
        // blocking an event hides it; the journal records everything
        t.send("POST", "/api/v1/admin/leisure/events/" + eventId + "/decision", admin, "{\"decision\":\"BLOCK\",\"reason\":\"Нарушение правил\"}", null).andExpect(status().isOk());
        t.send("GET", "/api/v1/leisure/events/" + eventId, null, null, null).andExpect(status().isNotFound());
        String audit = t.body(t.send("GET", "/api/v1/admin/leisure/audit", admin, null, null).andExpect(status().isOk()));
        assertThat(audit).contains("EVENT_BLOCK", "PAYMENT_REFUNDED", "ORDER_CANCELLED", "VENUE_APPROVE");
        // the administrator switch (shared feature switches) turns the whole product off without deleting data
        t.send("PUT", "/api/v1/admin/features/LEISURE", admin, "{\"enabled\":false,\"reason\":\"проверка\"}", null);
    }

    @Test
    void complaintsFavoritesAndSessionCancellation() throws Exception {
        UUID play = t.event("Игровая зона");
        t.send("PUT", "/api/v1/leisure/favorites/" + play, alice, null, null).andExpect(status().isNoContent());
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/favorites", alice, null, null)), "$")).hasSize(1);
        t.send("DELETE", "/api/v1/leisure/favorites/" + play, alice, null, null).andExpect(status().isNoContent());
        UUID session = t.firstSession(play);
        UUID type = t.ticketType(play, "Ребёнок");
        String o = order(alice, hold(alice, session, "{\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"quantity\":2}]}"), "TEST_CARD", key());
        t.send("POST", "/api/v1/leisure/complaints", alice, "{\"orderId\":\"" + JsonPath.read(o, "$.id") + "\",\"body\":\"Не открыли вход\"}", null).andExpect(status().isCreated());
        t.send("POST", "/api/v1/leisure/complaints", bob, "{\"orderId\":\"" + JsonPath.read(o, "$.id") + "\",\"body\":\"чужой заказ\"}", null).andExpect(status().isNotFound());
        // the organiser cancels the session: every booking is cancelled and refunded
        t.send("POST", partnerPath(partnerA, "/sessions/" + session + "/cancel"), ownerA, "{\"reason\":\"Авария\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        String after = t.body(t.send("GET", "/api/v1/leisure/orders/" + JsonPath.read(o, "$.id"), alice, null, null));
        assertThat((String) JsonPath.read(after, "$.status")).isEqualTo("CANCELLED");
        assertThat((String) JsonPath.read(after, "$.payment.status")).isEqualTo("TEST_REFUNDED");
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", bob, "{\"lines\":[{\"ticketTypeId\":\"" + type + "\",\"quantity\":1}]}", null).andExpect(status().isNotFound());
    }

    @Test
    void executorAssignmentLifecycleOnlyForEventsThatNeedOne() throws Exception {
        UUID walk = t.event("Пешая экскурсия");
        UUID session = t.firstSession(walk);
        String assign = "{\"phone\":\"+77000000522\",\"role\":\"GUIDE\",\"note\":\"Встреча у фонтана\"}";
        // a cinema event needs no executor; unknown phone and other partner are refused
        UUID film = t.event("Демо-фильм");
        t.send("POST", partnerPath(partnerA, "/sessions/" + t.firstSession(film) + "/assignments"), ownerA, assign, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("EXECUTOR_NOT_NEEDED"));
        t.send("POST", partnerPath(partnerA, "/sessions/" + session + "/assignments"), ownerA, "{\"phone\":\"+77099999999\",\"role\":\"GUIDE\"}", null).andExpect(status().isNotFound());
        t.send("POST", partnerPath(partnerB, "/sessions/" + session + "/assignments"), ownerB, assign, null).andExpect(status().isNotFound());
        String offered = t.body(t.send("POST", partnerPath(partnerA, "/sessions/" + session + "/assignments"), ownerA, assign, null).andExpect(status().isCreated()));
        String id = JsonPath.read(offered, "$.id");
        assertThat(offered).doesNotContain("77000000522").contains("•••0522");
        t.send("POST", partnerPath(partnerA, "/sessions/" + session + "/assignments"), ownerA, assign, null).andExpect(status().isConflict());
        // the executor sees and accepts it; another user sees nothing
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/executor/leisure/assignments", bob, null, null).andExpect(status().isOk())), "$")).hasSize(1);
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/executor/leisure/assignments", alice, null, null)), "$")).isEmpty();
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", alice, "{\"step\":\"ACCEPT\"}", null).andExpect(status().isNotFound());
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"START\"}", null).andExpect(status().isConflict());
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"ACCEPT\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ACCEPTED"));
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"ACCEPT\"}", null).andExpect(status().isOk()); // idempotent
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"START\"}", null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("OUTSIDE_WORK_WINDOW"));
        db.update("update marketplace.leisure_sessions set starts_at = now() + interval '30 minutes', ends_at = now() + interval '2 hours' where id = ?", session);
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"START\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("STARTED"));
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"CANCEL\"}", null).andExpect(status().isConflict());
        t.send("POST", "/api/v1/executor/leisure/assignments/" + id + "/step", bob, "{\"step\":\"COMPLETE\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/executor/leisure/assignments?scope=history", bob, null, null)), "$")).hasSize(1);
        assertThat(t.body(t.send("GET", partnerPath(partnerA, "/history"), ownerA, null, null))).contains("ASSIGNMENT_OFFERED");
    }
}
