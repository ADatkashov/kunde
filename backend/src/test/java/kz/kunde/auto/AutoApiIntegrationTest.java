package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
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
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * KUNDE Auto over HTTP against PostgreSQL: catalog and search, vehicles and ownership, server-side quotes (no price from the
 * client, expiry), idempotent booking, double-booking and buffer protection, reschedule, cancellation, partner lifecycle with
 * price approval, time off, partner isolation, admin switches. Synthetic data only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.beauty.enabled=true",
        "app.auto.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000501,+77000000502,+77000000503",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class AutoApiIntegrationTest {
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    String alice;
    String bob;
    String ownerA;   // partner A owner
    String ownerB;   // partner B owner
    UUID wash;
    UUID sto;
    UUID partnerA;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000501','+77000000502','+77000000503')");
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json", "food/flowers-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json", "auto/demo-venues.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        alice = login("+77000000501");
        bob = login("+77000000502");
        ownerA = login("+77000000002");
        ownerB = login("+77000000003");
        wash = venue("auto-demo-wash");
        sto = venue("auto-demo-sto");
    }

    // ---- helpers -------------------------------------------------------------------------------

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
            case "PATCH" -> patch(path);
            case "PUT" -> put(path);
            case "DELETE" -> delete(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (key != null) { request.header("Idempotency-Key", key); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk()));
    }

    private static UUID subject(String loginBody) throws Exception {
        return UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    private String refreshed(String loginBody) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}", null).andExpect(status().isOk())), "$.accessToken");
    }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return JsonPath.read(body(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk())), "$.accessToken");
    }

    private UUID venue(String slug) { return db.queryForObject("select id from marketplace.booking_venues where slug = ?", UUID.class, slug); }

    private UUID service(UUID venue, String name) {
        return db.queryForObject("select id from marketplace.booking_services where venue_id = ? and name = ?", UUID.class, venue, name);
    }

    /** A date at least two days ahead that is not a Sunday (the synthetic posts are closed on Sunday). */
    private static LocalDate workday() {
        LocalDate d = LocalDate.now(ALMATY).plusDays(3);
        while (d.getDayOfWeek().getValue() == 7) { d = d.plusDays(1); }
        return d;
    }

    private List<String> slots(UUID venue, UUID service, LocalDate date) throws Exception {
        return JsonPath.read(body(send("GET", "/api/v1/auto/slots?venueId=" + venue + "&serviceId=" + service + "&date=" + date, null, null, null)
                .andExpect(status().isOk())), "$[*].startsAt");
    }

    private String vehicle(String token) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/auto/vehicles", token,
                "{\"make\":\"Toyota\",\"model\":\"Camry\",\"year\":2018,\"plate\":\"123 abc 02\"}", null).andExpect(status().isCreated())), "$.id");
    }

    private String quote(String token, UUID venue, UUID service, String vehicle, String startsAt) throws Exception {
        return body(send("POST", "/api/v1/auto/quotes", token, "{\"venueId\":\"" + venue + "\",\"serviceId\":\"" + service
                + "\",\"vehicleId\":\"" + vehicle + "\",\"startsAt\":\"" + startsAt + "\"}", null));
    }

    private String quoteId(String token, UUID venue, UUID service, String vehicle, String startsAt) throws Exception {
        String q = body(send("POST", "/api/v1/auto/quotes", token, "{\"venueId\":\"" + venue + "\",\"serviceId\":\"" + service
                + "\",\"vehicleId\":\"" + vehicle + "\",\"startsAt\":\"" + startsAt + "\"}", null).andExpect(status().isCreated()));
        return JsonPath.read(q, "$.id");
    }

    private ResultActions book(String token, String quoteId, String key) throws Exception {
        return send("POST", "/api/v1/auto/bookings", token, "{\"quoteId\":\"" + quoteId + "\"}", key);
    }

    private String booked(String token, UUID venue, UUID service, String vehicle, String startsAt, String key) throws Exception {
        return JsonPath.read(body(book(token, quoteId(token, venue, service, vehicle, startsAt), key).andExpect(status().isCreated())), "$.id");
    }

    private String partnerAction(String token, String booking, String action, String extra) throws Exception {
        return body(send("POST", "/api/v1/partner/partners/" + partnerA + "/booking/bookings/" + booking + "/action", token,
                "{\"action\":\"" + action + "\"" + (extra == null ? "" : "," + extra) + "}", null).andExpect(status().isOk()));
    }

    private void linkStoToPartner() {
        db.update("update marketplace.booking_venues set partner_id = ? where id = ?", partnerA, sto);
    }

    // ---- tests ---------------------------------------------------------------------------------

    @Test
    void catalogCategoriesSearchAndFilters() throws Exception {
        String cats = body(send("GET", "/api/v1/auto/categories", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(cats, "$")).hasSize(8);
        assertThat((List<String>) JsonPath.read(cats, "$[*].code")).contains("CAR_WASH", "TIRE", "OIL_CHANGE", "DIAGNOSTICS", "ROADSIDE");
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/venues", null, null, null).andExpect(status().isOk())), "$")).hasSize(2);
        String washOnly = body(send("GET", "/api/v1/auto/venues?category=CAR_WASH", null, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(washOnly, "$[*].name")).containsExactly("Тестовая автомойка «Демо»");
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/venues?q=мойка", null, null, null).andExpect(status().isOk())), "$")).hasSize(1);
        String detail = body(send("GET", "/api/v1/auto/venues/" + sto, null, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(detail, "$.services[*].priceKind")).containsExactlyInAnyOrder("FROM", "FIXED", "DIAGNOSTIC");
        // The old barbershop API does not list or book Auto venues
        assertThat((List<String>) JsonPath.read(body(send("GET", "/api/v1/booking/venues", null, null, null).andExpect(status().isOk())), "$[*].category"))
                .doesNotContain("AUTO");
    }

    @Test
    void vehiclesAreValidatedOwnedAndVersioned() throws Exception {
        send("GET", "/api/v1/auto/vehicles", null, null, null).andExpect(status().isUnauthorized());
        String id = vehicle(alice);
        String list = body(send("GET", "/api/v1/auto/vehicles", alice, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(list, "$[0].plate")).isEqualTo("123ABC02");
        send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"Kia\",\"model\":\"Rio\",\"year\":2012}", null)
                .andExpect(status().isCreated()).andExpect(jsonPath("$.plate").doesNotExist());
        send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"Kia\",\"model\":\"Rio\",\"year\":1900}", null).andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"\",\"model\":\"Rio\",\"year\":2012}", null).andExpect(status().isBadRequest());
        send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"Kia\",\"model\":\"Rio\",\"year\":2012,\"plate\":\"!!\"}", null).andExpect(status().isBadRequest());
        // ownership: Bob cannot see, change or delete Alice's vehicle
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/vehicles", bob, null, null)), "$")).isEmpty();
        send("PUT", "/api/v1/auto/vehicles/" + id, bob, "{\"make\":\"X\",\"model\":\"Y\",\"year\":2020,\"version\":0}", null).andExpect(status().isNotFound());
        send("DELETE", "/api/v1/auto/vehicles/" + id, bob, null, null).andExpect(status().isNotFound());
        // optimistic locking
        send("PUT", "/api/v1/auto/vehicles/" + id, alice, "{\"make\":\"Toyota\",\"model\":\"Corolla\",\"year\":2019,\"version\":0}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1));
        send("PUT", "/api/v1/auto/vehicles/" + id, alice, "{\"make\":\"Toyota\",\"model\":\"Corolla\",\"year\":2019,\"version\":0}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VEHICLE_VERSION_CONFLICT"));
        for (int i = 0; i < 3; i++) { vehicle(alice); }
        send("POST", "/api/v1/auto/vehicles", alice, "{\"make\":\"Kia\",\"model\":\"Rio\",\"year\":2012}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TOO_MANY_VEHICLES"));
        send("DELETE", "/api/v1/auto/vehicles/" + id, alice, null, null).andExpect(status().isNoContent());
    }

    @Test
    void quoteBookIsIdempotentServerPricedAndExpires() throws Exception {
        String car = vehicle(alice);
        UUID service = service(wash, "Мойка кузова");
        String start = slots(wash, service, workday()).get(0);
        // the request has no price field: a price sent by the client is ignored
        String q = body(send("POST", "/api/v1/auto/quotes", alice, "{\"venueId\":\"" + wash + "\",\"serviceId\":\"" + service + "\",\"vehicleId\":\"" + car
                + "\",\"startsAt\":\"" + start + "\",\"priceMinor\":1}", null).andExpect(status().isCreated()));
        assertThat((Integer) JsonPath.read(q, "$.priceMinor")).isEqualTo(300000);
        assertThat((String) JsonPath.read(q, "$.priceKind")).isEqualTo("FIXED");
        String quote = JsonPath.read(q, "$.id");
        String key = "alice-book-key-0000001";
        String first = body(book(alice, quote, key).andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("CONFIRMED")));
        assertThat((Integer) JsonPath.read(first, "$.priceMinor")).isEqualTo(300000);
        assertThat((String) JsonPath.read(first, "$.vehicle")).contains("Toyota Camry 2018");
        // same key + same quote: replay returns the same booking (200), nothing new is created
        String again = body(book(alice, quote, key).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(again, "$.id")).isEqualTo(JsonPath.read(first, "$.id"));
        assertThat(db.queryForObject("select count(*) from transactions.bookings where category = 'AUTO'", Integer.class)).isEqualTo(1);
        // same key for another quote -> 409; the used quote cannot be booked again under a new key
        String start2 = slots(wash, service, workday()).get(3);
        book(alice, quoteId(alice, wash, service, car, start2), key).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REUSED"));
        book(alice, quote, "alice-book-key-0000002").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_USED"));
        // missing key; someone else's quote and vehicle
        book(alice, quoteId(alice, wash, service, car, start2), null).andExpect(status().isBadRequest());
        String aliceQuote = quoteId(alice, wash, service, car, start2);
        book(bob, aliceQuote, "bob-book-key-00000001").andExpect(status().isNotFound());
        assertThat(quote(bob, wash, service, car, start2)).contains("VEHICLE_NOT_FOUND");
        // expiry
        db.update("update transactions.auto_quotes set expires_at = now() - interval '1 minute' where id = ?::uuid", aliceQuote);
        book(alice, aliceQuote, "alice-book-key-0000003").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_EXPIRED"));
        // a time the engine does not offer (off-grid / outside hours) cannot be quoted
        String offGrid = OffsetDateTime.parse(start).plusMinutes(5).toString();
        assertThat(quote(alice, wash, service, car, offGrid)).contains("SLOT_UNAVAILABLE");
        // the old booking endpoint refuses automotive venues
        send("POST", "/api/v1/booking/bookings", alice, "{\"venueId\":\"" + wash + "\",\"serviceId\":\"" + service + "\",\"masterId\":\""
                + db.queryForObject("select id from marketplace.booking_masters where venue_id = ? limit 1", UUID.class, wash)
                + "\",\"startsAt\":\"" + start2 + "\"}", "legacy-key-000000001").andExpect(status().isConflict());
    }

    @Test
    void noDoubleBookingOfAPostOrAVehicleAndTheBufferIsKept() throws Exception {
        String carA = vehicle(alice);
        String carB = vehicle(bob);
        UUID service = service(sto, "Замена масла"); // one post, 45 minutes
        LocalDate day = workday();
        String start = slots(sto, service, day).get(0);
        String qA = quoteId(alice, sto, service, carA, start);
        String qB = quoteId(bob, sto, service, carB, start);
        book(alice, qA, "alice-book-key-0000010").andExpect(status().isCreated());
        book(bob, qB, "bob-book-key-000000010").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SLOT_TAKEN"));
        assertThat(slots(sto, service, day)).doesNotContain(start);
        // the same vehicle cannot be in two places at once (another service of the same station, overlapping time)
        UUID tires = service(sto, "Шиномонтаж (4 колеса)");
        assertThat(quote(alice, sto, tires, carA, start)).contains("SLOT_UNAVAILABLE");
        // buffer: with 30 minutes between visits the slot right after (10:00 + 45 min) and the next grid slot are not offered
        db.update("update marketplace.booking_venues set buffer_minutes = 30 where id = ?", sto);
        List<String> afterBuffer = slots(sto, service, day);
        OffsetDateTime end = OffsetDateTime.parse(start).plusMinutes(45);
        assertThat(afterBuffer).noneMatch(s -> OffsetDateTime.parse(s).isBefore(end.plusMinutes(30)) && OffsetDateTime.parse(s).isAfter(OffsetDateTime.parse(start).minusMinutes(75)));
        assertThat(afterBuffer).anyMatch(s -> OffsetDateTime.parse(s).equals(end.plusMinutes(30)) || OffsetDateTime.parse(s).isAfter(end.plusMinutes(30)));
        // the database itself refuses an overlapping insert even if the application layer were bypassed
        UUID master = db.queryForObject("select id from marketplace.booking_masters where venue_id = ?", UUID.class, sto);
        org.junit.jupiter.api.Assertions.assertThrows(DataIntegrityViolationException.class, () -> db.update("""
                insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name, master_name,
                    duration_minutes, starts_at, ends_at, price_minor, idempotency_key, category, vehicle_id, vehicle_label)
                select b.user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name, master_name, duration_minutes,
                    starts_at + interval '10 minutes', ends_at + interval '10 minutes', price_minor, 'raw-overlap-key-000001', 'AUTO', vehicle_id, vehicle_label
                from transactions.bookings b where b.category = 'AUTO'
                """));
        assertThat(master).isNotNull();
    }

    @Test
    void rescheduleAndCancelFollowTheRules() throws Exception {
        String car = vehicle(alice);
        UUID service = service(sto, "Замена масла");
        LocalDate day = workday();
        List<String> free = slots(sto, service, day);
        String booking = booked(alice, sto, service, car, free.get(0), "alice-book-key-0000020");
        // move to a later free time; the booking's own time does not block it, history shows RESCHEDULED
        String moved = body(send("POST", "/api/v1/auto/bookings/" + booking + "/reschedule", alice, "{\"startsAt\":\"" + free.get(4) + "\"}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.rescheduleCount").value(1)));
        assertThat(OffsetDateTime.parse(JsonPath.read(moved, "$.startsAt")).toInstant()).isEqualTo(OffsetDateTime.parse(free.get(4)).toInstant());
        assertThat((List<String>) JsonPath.read(moved, "$.timeline[*].status")).contains("RESCHEDULED");
        assertThat(slots(sto, service, day)).contains(free.get(0)).doesNotContain(free.get(4));
        // stranger cannot move or cancel it
        send("POST", "/api/v1/auto/bookings/" + booking + "/reschedule", bob, "{\"startsAt\":\"" + free.get(1) + "\"}", null).andExpect(status().isNotFound());
        send("POST", "/api/v1/auto/bookings/" + booking + "/cancel", bob, null, null).andExpect(status().isNotFound());
        // an unavailable time is refused and nothing changes
        send("POST", "/api/v1/auto/bookings/" + booking + "/reschedule", alice, "{\"startsAt\":\"" + OffsetDateTime.parse(free.get(1)).plusMinutes(5) + "\"}", null)
                .andExpect(status().isConflict());
        // limit of two moves
        send("POST", "/api/v1/auto/bookings/" + booking + "/reschedule", alice, "{\"startsAt\":\"" + free.get(2) + "\"}", null).andExpect(status().isOk());
        send("POST", "/api/v1/auto/bookings/" + booking + "/reschedule", alice, "{\"startsAt\":\"" + free.get(3) + "\"}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("RESCHEDULE_LIMIT"));
        // cancel: free, idempotent, frees the slot
        send("POST", "/api/v1/auto/bookings/" + booking + "/cancel", alice, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        send("POST", "/api/v1/auto/bookings/" + booking + "/cancel", alice, null, null).andExpect(status().isOk());
        assertThat(slots(sto, service, day)).contains(free.get(2));
        send("POST", "/api/v1/auto/bookings/" + booking + "/reschedule", alice, "{\"startsAt\":\"" + free.get(3) + "\"}", null).andExpect(status().isConflict());
        // a booking less than 2 hours ahead is marked as a late cancel and cannot be moved
        String near = booked(alice, sto, service, car, free.get(5), "alice-book-key-0000021");
        db.update("update transactions.bookings set starts_at = now() + interval '1 hour', ends_at = now() + interval '105 minutes' where id = ?::uuid", near);
        send("POST", "/api/v1/auto/bookings/" + near + "/reschedule", alice, "{\"startsAt\":\"" + free.get(6) + "\"}", null).andExpect(status().isConflict());
        send("POST", "/api/v1/auto/bookings/" + near + "/cancel", alice, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.cancelReason").value("LATE_CANCEL"));
        // history of the customer only
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/bookings", bob, null, null)), "$")).isEmpty();
        send("GET", "/api/v1/auto/bookings/" + booking, bob, null, null).andExpect(status().isNotFound());
    }

    @Test
    void partnerRunsTheFullLifecycleWithPriceApprovalAndIsolation() throws Exception {
        linkStoToPartner();
        String car = vehicle(alice);
        UUID service = service(sto, "Замена масла"); // FROM price
        List<String> free = slots(sto, service, workday());
        String booking = booked(alice, sto, service, car, free.get(0), "alice-book-key-0000030");
        String path = "/api/v1/partner/partners/" + partnerA + "/booking/bookings/" + booking;
        assertThat((String) JsonPath.read(body(send("GET", "/api/v1/auto/bookings/" + booking, alice, null, null)), "$.status")).isEqualTo("PENDING");
        // isolation: partner B, a plain customer and an unauthenticated caller
        send("GET", path, ownerB, null, null).andExpect(status().isNotFound());
        send("GET", path, alice, null, null).andExpect(status().isForbidden());
        send("GET", path, null, null, null).andExpect(status().isUnauthorized());
        // only valid transitions
        send("POST", path + "/action", ownerA, "{\"action\":\"START\"}", null).andExpect(status().isConflict());
        String confirmed = partnerAction(ownerA, booking, "CONFIRM", null);
        assertThat((List<String>) JsonPath.read(confirmed, "$.allowedActions")).contains("CHECK_IN", "CANCEL");
        partnerAction(ownerA, booking, "CHECK_IN", null);
        partnerAction(ownerA, booking, "START", null);
        String running = partnerAction(ownerA, booking, "START", null); // idempotent repeat
        assertThat((List<String>) JsonPath.read(running, "$.allowedActions")).contains("PROPOSE_PRICE", "COMPLETE");
        // final price after inspection: needs the customer's approval before completion
        partnerAction(ownerA, booking, "PROPOSE_PRICE", "\"finalPriceMinor\":1500000");
        send("POST", path + "/action", ownerA, "{\"action\":\"COMPLETE\"}", null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PRICE_APPROVAL_PENDING"));
        send("POST", "/api/v1/auto/bookings/" + booking + "/price-decision", bob, "{\"approve\":true}", null).andExpect(status().isNotFound());
        send("POST", "/api/v1/auto/bookings/" + booking + "/price-decision", alice, "{\"approve\":false}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.priceApproval").value("DECLINED")).andExpect(jsonPath("$.finalPriceMinor").doesNotExist());
        partnerAction(ownerA, booking, "PROPOSE_PRICE", "\"finalPriceMinor\":1400000");
        send("POST", "/api/v1/auto/bookings/" + booking + "/price-decision", alice, "{\"approve\":true}", null).andExpect(status().isOk());
        partnerAction(ownerA, booking, "COMPLETE", null);
        String done = body(send("GET", "/api/v1/auto/bookings/" + booking, alice, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(done, "$.status")).isEqualTo("COMPLETED");
        assertThat((Integer) JsonPath.read(done, "$.finalPriceMinor")).isEqualTo(1400000);
        assertThat((Integer) JsonPath.read(done, "$.priceMinor")).isEqualTo(1200000);
        assertThat((List<String>) JsonPath.read(done, "$.timeline[*].status")).containsSubsequence("PENDING", "CONFIRMED", "CHECKED_IN", "IN_PROGRESS", "COMPLETED");
        // a FIXED price cannot be changed by the partner
        UUID fixed = service(sto, "Шиномонтаж (4 колеса)");
        String b2 = booked(alice, sto, fixed, car, free.get(6), "alice-book-key-0000031");
        partnerAction(ownerA, b2, "CONFIRM", null);
        partnerAction(ownerA, b2, "CHECK_IN", null);
        partnerAction(ownerA, b2, "START", null);
        send("POST", "/api/v1/partner/partners/" + partnerA + "/booking/bookings/" + b2 + "/action", ownerA, "{\"action\":\"PROPOSE_PRICE\",\"finalPriceMinor\":1}", null)
                .andExpect(status().isConflict());
        // no-show and rejection
        String b3 = booked(alice, sto, service, car, free.get(10), "alice-book-key-0000032");
        send("POST", "/api/v1/partner/partners/" + partnerA + "/booking/bookings/" + b3 + "/action", ownerA, "{\"action\":\"REJECT\"}", null).andExpect(status().isBadRequest());
        partnerAction(ownerA, b3, "REJECT", "\"reason\":\"Нет запчастей\"");
        assertThat((String) JsonPath.read(body(send("GET", "/api/v1/auto/bookings/" + b3, alice, null, null)), "$.status")).isEqualTo("CANCELLED");
        String b4 = booked(alice, sto, service, car, free.get(10), "alice-book-key-0000033");
        partnerAction(ownerA, b4, "CONFIRM", null);
        db.update("update transactions.bookings set starts_at = now() - interval '2 hours', ends_at = now() - interval '75 minutes' where id = ?::uuid", b4);
        partnerAction(ownerA, b4, "NO_SHOW", null);
        assertThat((String) JsonPath.read(body(send("GET", "/api/v1/auto/bookings/" + b4, alice, null, null)), "$.status")).isEqualTo("NO_SHOW");
        // partner history
        String history = body(send("GET", "/api/v1/partner/partners/" + partnerA + "/booking/bookings?scope=history", ownerA, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(history, "$[*].status")).contains("COMPLETED", "NO_SHOW", "CANCELLED");
        assertThat((String) JsonPath.read(history, "$[0].customerRef")).hasSize(8);
    }

    @Test
    void timeOffRemovesSlotsAndIsRefusedOverExistingBookings() throws Exception {
        linkStoToPartner();
        String car = vehicle(alice);
        UUID service = service(sto, "Замена масла");
        LocalDate day = workday();
        List<String> free = slots(sto, service, day);
        String base = "/api/v1/partner/partners/" + partnerA + "/booking/venues/" + sto + "/time-off";
        String from = free.get(8);
        String to = OffsetDateTime.parse(free.get(8)).plusHours(2).toString();
        send("POST", base, ownerB, "{\"startsAt\":\"" + from + "\",\"endsAt\":\"" + to + "\"}", null).andExpect(status().isNotFound());
        send("POST", base, ownerA, "{\"startsAt\":\"" + to + "\",\"endsAt\":\"" + from + "\"}", null).andExpect(status().isBadRequest());
        String created = body(send("POST", base, ownerA, "{\"startsAt\":\"" + from + "\",\"endsAt\":\"" + to + "\",\"reason\":\"Ремонт подъёмника\"}", null).andExpect(status().isOk()));
        List<String> after = slots(sto, service, day);
        assertThat(after).doesNotContain(free.get(8), free.get(9)).contains(free.get(0));
        // a booking inside a new period blocks it
        String booking = booked(alice, sto, service, car, free.get(0), "alice-book-key-0000040");
        send("POST", base, ownerA, "{\"startsAt\":\"" + free.get(0) + "\",\"endsAt\":\"" + OffsetDateTime.parse(free.get(0)).plusHours(1) + "\"}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TIME_OFF_CONFLICT"));
        assertThat(booking).isNotNull();
        assertThat((List<?>) JsonPath.read(body(send("GET", base, ownerA, null, null)), "$")).hasSize(1);
        send("DELETE", base + "/" + JsonPath.read(created, "$.id"), ownerA, null, null).andExpect(status().isNoContent());
        assertThat(slots(sto, service, day)).contains(free.get(8));
    }

    @Test
    void adminSwitchesAreProtectedAndAudited() throws Exception {
        send("GET", "/api/v1/admin/auto/categories", alice, null, null).andExpect(status().isForbidden());
        // an administrator with another permission only is refused (grant checked per request)
        String bobLogin = loginBody("+77000000502");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'PARTNER_VERIFICATION', 'synthetic DEV admin')", subject(bobLogin));
        send("GET", "/api/v1/admin/auto/categories", refreshed(bobLogin), null, null).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ADMIN_FORBIDDEN"));
        String adminLogin = loginBody("+77000000503");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'AUTO_OPERATIONS', 'synthetic DEV admin')", subject(adminLogin));
        String adminToken = refreshed(adminLogin);
        send("GET", "/api/v1/admin/auto/categories", adminToken, null, null).andExpect(status().isOk());
        send("PATCH", "/api/v1/admin/auto/categories/CAR_WASH", adminToken, "{\"enabled\":false}", null).andExpect(status().isOk()).andExpect(jsonPath("$.enabled").value(false));
        String car = vehicle(alice);
        UUID service = service(wash, "Мойка кузова");
        String start = slots(wash, service, workday()).get(0);
        assertThat(quote(alice, wash, service, car, start)).contains("AUTO_CATEGORY_DISABLED");
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/auto/venues?category=CAR_WASH", null, null, null)), "$")).isEmpty();
        send("PATCH", "/api/v1/admin/auto/categories/CAR_WASH", adminToken, "{\"enabled\":true}", null).andExpect(status().isOk());
        String booking = booked(alice, wash, service, car, start, "alice-book-key-0000050");
        // blocking a venue hides it from slots/new bookings; the existing booking can still be cancelled
        send("PATCH", "/api/v1/admin/auto/venues/" + wash, adminToken, "{\"open\":false}", null).andExpect(status().isOk());
        assertThat(quote(alice, wash, service, car, start)).contains("VENUE_NOT_FOUND");
        send("POST", "/api/v1/auto/bookings/" + booking + "/cancel", alice, null, null).andExpect(status().isOk());
        String monitor = body(send("GET", "/api/v1/admin/auto/bookings", adminToken, null, null).andExpect(status().isOk()));
        assertThat(monitor).doesNotContain("userId").doesNotContain("user_id").doesNotContain("123ABC02");
        assertThat(db.queryForObject("select count(*) from marketplace.auto_admin_events", Integer.class)).isEqualTo(3);
    }

    @Test
    void partnerManagesServicesAndPostsWithIsolationAndValidation() throws Exception {
        linkStoToPartner();
        String base = "/api/v1/partner/partners/" + partnerA + "/booking/venues/" + sto;
        UUID oil = service(sto, "Замена масла");
        // another partner and a plain customer cannot touch it
        send("PUT", base + "/services/" + oil, ownerB, "{\"priceMinor\":1}", null).andExpect(status().isNotFound());
        send("PUT", base + "/services/" + oil, alice, "{\"priceMinor\":1}", null).andExpect(status().isForbidden());
        // validation
        send("PUT", base + "/services/" + oil, ownerA, "{\"priceMinor\":-5}", null).andExpect(status().isBadRequest());
        send("PUT", base + "/services/" + oil, ownerA, "{\"durationMinutes\":50}", null).andExpect(status().isBadRequest());
        send("PUT", base + "/services/" + oil, ownerA, "{\"priceKind\":\"FREE\"}", null).andExpect(status().isBadRequest());
        // a price change applies to new quotes; an already booked price stays
        String car = vehicle(alice);
        List<String> free = slots(sto, oil, workday());
        String booking = booked(alice, sto, oil, car, free.get(0), "alice-book-key-0000060");
        send("PUT", base + "/services/" + oil, ownerA, "{\"priceMinor\":1500000,\"durationMinutes\":60,\"conditions\":\"Фильтр включён\"}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.priceMinor").value(1500000)).andExpect(jsonPath("$.durationMinutes").value(60));
        assertThat((Integer) JsonPath.read(body(send("GET", "/api/v1/auto/bookings/" + booking, alice, null, null)), "$.priceMinor")).isEqualTo(1200000);
        String q = quote(alice, sto, oil, car, slots(sto, oil, workday()).get(8));
        assertThat((Integer) JsonPath.read(q, "$.priceMinor")).isEqualTo(1500000);
        assertThat((Integer) JsonPath.read(q, "$.durationMinutes")).isEqualTo(60);
        // a quote made before the price changed is refused as stale
        String stale = quoteId(alice, sto, oil, car, slots(sto, oil, workday()).get(9));
        send("PUT", base + "/services/" + oil, ownerA, "{\"priceMinor\":1600000}", null).andExpect(status().isOk());
        book(alice, stale, "alice-book-key-0000061").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_STALE"));
        // new service and new post
        String created = body(send("POST", base + "/services", ownerA, "{\"name\":\"Развал-схождение\",\"autoCategory\":\"MAINTENANCE\",\"durationMinutes\":60,"
                + "\"priceMinor\":700000,\"priceKind\":\"FIXED\"}", null).andExpect(status().isOk()));
        UUID newService = UUID.fromString(JsonPath.read(created, "$.id"));
        send("POST", base + "/services", ownerA, "{\"name\":\"X\",\"autoCategory\":\"NOPE\",\"durationMinutes\":60,\"priceMinor\":1}", null).andExpect(status().isBadRequest());
        send("POST", base + "/masters", ownerB, "{\"name\":\"Пост Б\"}", null).andExpect(status().isNotFound());
        send("POST", base + "/masters", ownerA, "{\"name\":\"Пост Б\"}", null).andExpect(status().isOk()).andExpect(jsonPath("$.hours.length()").value(6));
        assertThat(slots(sto, newService, workday())).isNotEmpty();
        // a non-automotive venue cannot get automotive services
        UUID barber = db.queryForObject("select id from marketplace.booking_venues where slug = 'partner-salon-demo'", UUID.class);
        send("POST", "/api/v1/partner/partners/" + partnerA + "/booking/venues/" + barber + "/services", ownerA,
                "{\"name\":\"X\",\"autoCategory\":\"MAINTENANCE\",\"durationMinutes\":60,\"priceMinor\":1}", null).andExpect(status().isConflict());
        assertThat(db.queryForObject("select count(*) from marketplace.partner_catalog_events where partner_id = ?", Integer.class, partnerA)).isGreaterThanOrEqualTo(4);
    }
}
