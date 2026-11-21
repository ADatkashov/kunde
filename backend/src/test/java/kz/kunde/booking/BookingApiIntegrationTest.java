package kz.kunde.booking;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.io.ClassPathResource;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * Barbershop booking over HTTP against PostgreSQL: public catalog and slots, idempotent booking, persistence,
 * double-booking protection (API and database), free cancellation before the start, ownership isolation.
 * Synthetic numbers and the synthetic demo venues only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000301,+77000000302",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class BookingApiIntegrationTest {
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000301', '+77000000302')");
        try (var in = new ClassPathResource("booking/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
    }

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = (method.equals("GET") ? get(path) : post(path)).contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (key != null) { request.header("Idempotency-Key", key); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return JsonPath.read(body(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk())), "$.accessToken");
    }

    private String venueId(String slug) {
        return db.queryForObject("select id from marketplace.booking_venues where slug = ?", String.class, slug);
    }

    private String serviceId(String slug, String name) {
        return db.queryForObject("select s.id from marketplace.booking_services s join marketplace.booking_venues v on v.id = s.venue_id "
                + "where v.slug = ? and s.name = ?", String.class, slug, name);
    }

    private String masterId(String slug, String name) {
        return db.queryForObject("select m.id from marketplace.booking_masters m join marketplace.booking_venues v on v.id = m.venue_id "
                + "where v.slug = ? and m.name = ?", String.class, slug, name);
    }

    private static String tomorrow() {
        return LocalDate.now(ALMATY).with(java.time.temporal.TemporalAdjusters.next(java.time.DayOfWeek.MONDAY)).toString();
    }

    private List<Map<String, Object>> slots(String slug, String service, String master, String date) throws Exception {
        String path = "/api/v1/booking/slots?venueId=" + venueId(slug) + "&serviceId=" + serviceId(slug, service)
                + (master == null ? "" : "&masterId=" + masterId(slug, master)) + "&date=" + date;
        return JsonPath.read(body(send("GET", path, null, null, null).andExpect(status().isOk())), "$");
    }

    private String book(String slug, String service, String master, String startsAt, String comment) {
        return "{\"venueId\":\"" + venueId(slug) + "\",\"serviceId\":\"" + serviceId(slug, service) + "\",\"masterId\":\""
                + masterId(slug, master) + "\",\"startsAt\":\"" + startsAt + "\"" + (comment == null ? "" : ",\"comment\":\"" + comment + "\"") + "}";
    }

    @Test
    void healthFavoritesArePrivateIdempotentAndLimitedToPublicTargets() throws Exception {
        try (var in = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
        var path = "/api/v1/booking/health/favorites";
        var clinic = "health-demo-clinic";
        var clinicId = venueId(clinic);
        var organization = path + "/ORGANIZATION/" + clinicId;
        var specialist = path + "/SPECIALIST/" + masterId(clinic, "Профиль М-01");
        var wellness = path + "/WELLNESS_SERVICE/" + serviceId("health-demo-fitness", "Персональная тренировка");
        var medical = path + "/WELLNESS_SERVICE/" + serviceId(clinic, "Приём терапевта");
        send("GET", path, null, null, null).andExpect(status().isUnauthorized());
        var owner = "Bearer " + login("+77000000301");
        var other = "Bearer " + login("+77000000302");
        for (String target : List.of(organization, specialist, wellness, organization)) {
            http.perform(put(target).header("Authorization", owner)).andExpect(status().isNoContent());
        }
        http.perform(put(medical).header("Authorization", owner)).andExpect(status().isNotFound());
        http.perform(get(path).header("Authorization", other)).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
        http.perform(delete(organization).header("Authorization", other)).andExpect(status().isNoContent());
        http.perform(get(path).header("Authorization", owner)).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));

        db.update("update marketplace.booking_venues set health_published = false where id = ?",
                UUID.fromString(clinicId));
        http.perform(get(path).header("Authorization", owner)).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].kind").value("WELLNESS_SERVICE"));
        http.perform(delete(wellness).header("Authorization", owner)).andExpect(status().isNoContent());
        http.perform(get(path).header("Authorization", owner)).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void healthCatalogCombinesFiltersOnTheSameAvailableService() throws Exception {
        try (var in = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
        var path = "/api/v1/booking/health/venues";
        http.perform(get(path)
                .param("district", "бостандыкский")
                .param("organization", "контур")
                .param("service", "приём")
                .param("specialist", "м-01")
                .param("specialty", "терапевт")
                .param("minPriceMinor", "850000")
                .param("maxPriceMinor", "850000"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].slug").value("health-demo-clinic"));
        http.perform(get(path)
                .param("organization", "контур")
                .param("service", "приём")
                .param("minPriceMinor", "1200000"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        http.perform(get(path).param("minPriceMinor", "2").param("maxPriceMinor", "1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("HEALTH_PRICE_RANGE_INVALID"));
    }

    @Test
    void healthCatalogReportsFilteredTotalBeyondTheLastPage() throws Exception {
        try (var in = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
        var path = "/api/v1/booking/health/venues";
        send("GET", path + "?limit=1", null, null, null).andExpect(status().isOk())
                .andExpect(header().string("X-Total-Count", "6"))
                .andExpect(jsonPath("$.length()").value(1));
        send("GET", path + "?direction=DOCTORS&offset=20", null, null, null).andExpect(status().isOk())
                .andExpect(header().string("X-Total-Count", "1"))
                .andExpect(jsonPath("$.length()").value(0));
        send("GET", path + "?q=no-matching-venue", null, null, null).andExpect(status().isOk())
                .andExpect(header().string("X-Total-Count", "0"))
                .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void healthCatalogAndSyntheticBookingKeepPriceAndPaymentConsistent() throws Exception {
        try (var in = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            assertThat(new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in))).isEqualTo(6);
        }
        try (var in = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            assertThat(new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in))).isZero();
        }
        send("GET", "/api/v1/capabilities", null, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.healthEnabled").value(true));
        send("GET", "/api/v1/booking/health/venues?direction=DOCTORS&limit=1", null, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].synthetic").value(true));
        var date = LocalDate.now(ALMATY).plusDays(1);
        if (date.getDayOfWeek() == java.time.DayOfWeek.SUNDAY) { date = date.plusDays(1); }
        String slug = "health-demo-clinic";
        String service = "Приём терапевта";
        String master = "Профиль М-01";
        String start = (String) slots(slug, service, master, date.toString()).getFirst().get("startsAt");
        String token = login("+77000000301");
        String other = login("+77000000302");
        String path = "/api/v1/booking/bookings";
        String key = "health-booking-test-001";
        String request = book(slug, service, master, start, null).replace("}",
                ",\"expectedPriceMinor\":850000,\"paymentMethod\":\"TEST_CARD\",\"acceptsTerms\":true}");
        send("POST", path, token, request.replace("850000", "1"), key)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BOOKING_PRICE_CHANGED"));
        send("POST", path, token, request.replace("}", ",\"comment\":\"private\"}"), key)
                .andExpect(status().isBadRequest());
        String id = JsonPath.read(body(send("POST", path, token, request, key).andExpect(status().isCreated())
                .andExpect(jsonPath("$.confirmation").value("DEV_MOCK"))
                .andExpect(jsonPath("$.paymentStatus").value("TEST_HELD"))), "$.id");
        send("POST", path, token, request, key).andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(id));
        send("POST", path, token, request.replace("TEST_CARD", "PAY_ON_SITE"), key)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REUSED"));
        send("POST", path, other, request, key).andExpect(status().isConflict());
        send("GET", path + "/" + id, other, null, null).andExpect(status().isNotFound());
        String alternate = (String) slots(slug, service, master, date.toString()).getLast().get("startsAt");
        String move = "{\"expectedStartsAt\":\"" + start + "\",\"startsAt\":\"" + alternate + "\"}";
        send("POST", path + "/" + id + "/reschedule", other, move, null).andExpect(status().isNotFound());
        send("POST", path + "/" + id + "/reschedule", token, move, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.startsAt").value(alternate));
        send("POST", path + "/" + id + "/reschedule", token, move, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.paymentStatus").value("TEST_HELD"));
        send("POST", path, token, request, key).andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        send("POST", path + "/" + id + "/cancel", token, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.paymentStatus").value("TEST_VOIDED"));
        send("POST", path, other, request, key).andExpect(status().isCreated());
    }

    @Test
    void catalogAndSlotsFollowHoursBreaksAndTheGrid() throws Exception {
        String venues = body(send("GET", "/api/v1/booking/venues", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(venues, "$")).hasSize(4);
        assertThat((Boolean) JsonPath.read(venues, "$[0].synthetic")).isTrue();
        String detail = body(send("GET", "/api/v1/booking/venues/" + venueId("barber-alatau"), null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(detail, "$.services")).hasSize(6);
        assertThat((List<?>) JsonPath.read(detail, "$.masters")).hasSize(3);
        send("GET", "/api/v1/booking/venues/" + java.util.UUID.randomUUID(), null, null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/booking/venues?category=TAXI", null, null, null).andExpect(status().isBadRequest());

        // Arman works 10:00-21:00 with a 14:00-15:00 break; a 45-minute haircut must fit inside the hours and outside the break.
        var armanSlots = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow());
        assertThat(armanSlots).isNotEmpty();
        for (var slot : armanSlots) {
            var local = OffsetDateTime.parse((String) slot.get("startsAt")).atZoneSameInstant(ALMATY).toLocalTime();
            assertThat(local.getMinute() % 15).isZero();
            assertThat(local).isBetween(java.time.LocalTime.of(10, 0), java.time.LocalTime.of(20, 15));
            boolean overlapsBreak = local.isBefore(java.time.LocalTime.of(15, 0)) && local.plusMinutes(45).isAfter(java.time.LocalTime.of(14, 0));
            assertThat(overlapsBreak).as("slot %s overlaps the break", local).isFalse();
            assertThat(slot.get("masterName")).isEqualTo("Арман");
        }
        // Any-master mode lists each start time once, with a concrete master.
        var any = slots("barber-alatau", "Мужская стрижка", null, tomorrow());
        assertThat(any.stream().map(s -> s.get("startsAt")).distinct().count()).isEqualTo(any.size());
        assertThat(any.size()).isGreaterThanOrEqualTo(armanSlots.size());
        // Out of the 14-day horizon, in the past, and a master who does not perform the service.
        send("GET", "/api/v1/booking/slots?venueId=" + venueId("barber-alatau") + "&serviceId=" + serviceId("barber-alatau", "Мужская стрижка")
                + "&date=" + LocalDate.now(ALMATY).plusDays(30), null, null, null).andExpect(status().isBadRequest());
        send("GET", "/api/v1/booking/slots?venueId=" + venueId("barber-alatau") + "&serviceId=" + serviceId("barber-alatau", "Мужская стрижка")
                + "&date=" + LocalDate.now(ALMATY).minusDays(1), null, null, null).andExpect(status().isBadRequest());
        send("GET", "/api/v1/booking/slots?venueId=" + venueId("barber-alatau") + "&serviceId=" + serviceId("barber-alatau", "Королевское бритьё")
                + "&masterId=" + masterId("barber-alatau", "Тимур") + "&date=" + tomorrow(), null, null, null).andExpect(status().isNotFound());
    }

    @Test
    void bookingIsPersistedIdempotentAndBlocksTheSlotUntilCancelled() throws Exception {
        String token = login("+77000000301");
        String other = login("+77000000302");
        var slot = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).get(2);
        String startsAt = (String) slot.get("startsAt");

        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", startsAt, null), null)
                .andExpect(status().isBadRequest());
        String created = body(send("POST", "/api/v1/booking/bookings", token,
                book("barber-alatau", "Мужская стрижка", "Арман", startsAt, "Окантовка"), "booking-key-000000001")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("CONFIRMED"))
                .andExpect(jsonPath("$.confirmation").value("DEV_MOCK")).andExpect(jsonPath("$.cancellable").value(true))
                .andExpect(jsonPath("$.priceMinor").value(650_000)).andExpect(jsonPath("$.durationMinutes").value(45)));
        String id = JsonPath.read(created, "$.id");
        assertThat(db.queryForObject("select count(*) from transactions.bookings where id = ?::uuid", Integer.class, id)).isEqualTo(1);

        // Same key and request: same booking, no second row.
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", startsAt, "Окантовка"),
                "booking-key-000000001").andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        assertThat(db.queryForObject("select count(*) from transactions.bookings", Integer.class)).isEqualTo(1);
        // Same key for another time is refused.
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман",
                (String) slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).get(0).get("startsAt"), null),
                "booking-key-000000001").andExpect(status().isConflict());

        // The slot and its overlapping neighbours are gone; another customer cannot take it.
        var after = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow());
        assertThat(after.stream().map(s -> s.get("startsAt"))).doesNotContain(startsAt);
        OffsetDateTime start = OffsetDateTime.parse(startsAt);
        for (var s : after) {
            OffsetDateTime t = OffsetDateTime.parse((String) s.get("startsAt"));
            boolean overlaps = t.isBefore(start.plusMinutes(45)) && t.plusMinutes(45).isAfter(start);
            assertThat(overlaps).as("slot %s overlaps the booking", t).isFalse();
        }
        send("POST", "/api/v1/booking/bookings", other, book("barber-alatau", "Мужская стрижка", "Арман", startsAt, null), "booking-key-000000002")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SLOT_UNAVAILABLE"));
        // The same customer cannot be at two masters at once.
        var danyar = slots("barber-alatau", "Мужская стрижка", "Данияр", tomorrow());
        var clash = danyar.stream().filter(s -> {
            OffsetDateTime t = OffsetDateTime.parse((String) s.get("startsAt"));
            return t.isBefore(start.plusMinutes(45)) && t.plusMinutes(45).isAfter(start);
        }).findFirst().orElseThrow();
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Данияр", (String) clash.get("startsAt"), null),
                "booking-key-000000003").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BOOKING_OVERLAPS_YOURS"));

        send("GET", "/api/v1/booking/bookings", token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(id)).andExpect(jsonPath("$[0].masterName").value("Арман"));
        send("GET", "/api/v1/booking/bookings/" + id, token, null, null).andExpect(status().isOk());
        // Ownership isolation.
        send("GET", "/api/v1/booking/bookings/" + id, other, null, null).andExpect(status().isNotFound());
        send("POST", "/api/v1/booking/bookings/" + id + "/cancel", other, null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/booking/bookings", other, null, null).andExpect(jsonPath("$.length()").value(0));

        // Free cancellation frees the time for others; a second cancel is refused.
        send("POST", "/api/v1/booking/bookings/" + id + "/cancel", token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CANCELLED")).andExpect(jsonPath("$.cancellable").value(false));
        assertThat(slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).stream().map(s -> s.get("startsAt"))).contains(startsAt);
        send("POST", "/api/v1/booking/bookings/" + id + "/cancel", token, null, null).andExpect(status().isConflict());
        send("POST", "/api/v1/booking/bookings", other, book("barber-alatau", "Мужская стрижка", "Арман", startsAt, null), "booking-key-000000004")
                .andExpect(status().isCreated());
    }

    @Test
    void invalidRequestsAndStartedAppointmentsAreRefused() throws Exception {
        send("GET", "/api/v1/booking/bookings", null, null, null).andExpect(status().isUnauthorized());
        send("POST", "/api/v1/booking/bookings", null, "{}", "booking-key-000000010").andExpect(status().isUnauthorized());
        String token = login("+77000000301");
        var slot = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).get(0);
        OffsetDateTime start = OffsetDateTime.parse((String) slot.get("startsAt"));
        // Off the 15-minute grid, in the past, outside the working hours, wrong master for the service.
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", start.plusMinutes(7).toString(), null),
                "booking-key-000000011").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SLOT_UNAVAILABLE"));
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", OffsetDateTime.now(ALMATY).minusDays(2).toString(), null),
                "booking-key-000000012").andExpect(status().isBadRequest());
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", start.withHour(3).toString(), null),
                "booking-key-000000013").andExpect(status().isConflict());
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Королевское бритьё", "Тимур", start.toString(), null),
                "booking-key-000000014").andExpect(status().isNotFound());

        // A booking whose time has passed is completed, not cancellable.
        String id = JsonPath.read(body(send("POST", "/api/v1/booking/bookings", token,
                book("barber-alatau", "Мужская стрижка", "Арман", start.toString(), null), "booking-key-000000015")
                .andExpect(status().isCreated())), "$.id");
        db.update("update transactions.bookings set starts_at = now() - interval '3 hours', ends_at = now() - interval '2 hours' where id = ?::uuid", id);
        send("GET", "/api/v1/booking/bookings/" + id, token, null, null).andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.cancellable").value(false));
        send("POST", "/api/v1/booking/bookings/" + id + "/cancel", token, null, null).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("BOOKING_NOT_CANCELLABLE"));
    }

    @Test
    void theDatabaseItselfRejectsOverlappingBookingsOfOneMaster() throws Exception {
        String token = login("+77000000301");
        String other = login("+77000000302");
        var slot = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).get(1);
        String startsAt = (String) slot.get("startsAt");
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", startsAt, null),
                "booking-key-000000020").andExpect(status().isCreated());
        String otherUser = db.queryForObject("select user_id from identity.phone_identities where phone_e164 = '+77000000302'", String.class);
        // Bypassing the API (a race): an overlapping insert for the same master violates the exclusion constraint.
        assertThatThrownBy(() -> db.update("""
                insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name,
                    master_name, duration_minutes, starts_at, ends_at, price_minor, idempotency_key)
                select ?::uuid, venue_id, service_id, master_id, venue_name, venue_address, service_name, master_name, duration_minutes,
                       starts_at + interval '15 minutes', ends_at + interval '15 minutes', price_minor, 'race-key-00000000001'
                from transactions.bookings limit 1
                """, otherUser)).isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("bookings_master_no_overlap");
        assertThat(other).isNotBlank();
    }

    private String cleaningBook(String service, String master, String startsAt, String extra) {
        return "{\"venueId\":\"" + venueId("home-clean-demo") + "\",\"serviceId\":\"" + serviceId("home-clean-demo", service)
                + "\",\"masterId\":\"" + masterId("home-clean-demo", master) + "\",\"startsAt\":\"" + startsAt + "\"" + extra + "}";
    }

    @Test
    void cleaningReusesBookingWithAddressAreaServerPriceAndSeparateCategory() throws Exception {
        // Barbershops stay separate from cleaning in the category listing; both use the same endpoints.
        String cleaning = body(send("GET", "/api/v1/booking/venues?category=CLEANING", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(cleaning, "$")).hasSize(1);
        assertThat((String) JsonPath.read(cleaning, "$[0].category")).isEqualTo("CLEANING");
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/booking/venues", null, null, null)), "$")).hasSize(4);
        String detail = body(send("GET", "/api/v1/booking/venues/" + venueId("home-clean-demo"), null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(detail, "$.services")).hasSize(3);
        assertThat((Integer) JsonPath.read(detail, "$.services[0].pricePerSqmMinor")).isPositive();

        String token = login("+77000000301");
        String other = login("+77000000302");
        String service = "Генеральная уборка";
        var slot = slots("home-clean-demo", service, null, tomorrow()).get(1);
        String startsAt = (String) slot.get("startsAt");
        String crew = (String) slot.get("masterId");
        String masterName = (String) slot.get("masterName");
        String body = "{\"venueId\":\"" + venueId("home-clean-demo") + "\",\"serviceId\":\"" + serviceId("home-clean-demo", service)
                + "\",\"masterId\":\"" + crew + "\",\"startsAt\":\"" + startsAt + "\",\"addressText\":\"Алматы, ул. Тестовая 1, кв. 5\",\"areaSqm\":60}";

        // Incorrect requests: no address, no area, area out of range, area for a barbershop, address for a barbershop.
        String noAddress = body.replace(",\"addressText\":\"Алматы, ул. Тестовая 1, кв. 5\"", "");
        send("POST", "/api/v1/booking/bookings", token, noAddress, "clean-key-0000000001").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("ADDRESS_REQUIRED"));
        send("POST", "/api/v1/booking/bookings", token, body.replace(",\"areaSqm\":60", ""), "clean-key-0000000002")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("AREA_INVALID"));
        send("POST", "/api/v1/booking/bookings", token, body.replace("\"areaSqm\":60", "\"areaSqm\":5"), "clean-key-0000000003")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("AREA_INVALID"));
        send("POST", "/api/v1/booking/bookings", token, body.replace("\"areaSqm\":60", "\"areaSqm\":900"), "clean-key-0000000004")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("AREA_INVALID"));
        var barberSlot = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).get(0);
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман",
                (String) barberSlot.get("startsAt"), null).replace("}", ",\"areaSqm\":40}"), "clean-key-0000000005")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("DETAILS_NOT_APPLICABLE"));
        assertThat(db.queryForObject("select count(*) from transactions.bookings", Integer.class)).isZero();

        // Valid request: the server computes the price (600000 + 45000 * 60 area), the booking stores address and area.
        String created = body(send("POST", "/api/v1/booking/bookings", token, body, "clean-key-0000000006").andExpect(status().isCreated())
                .andExpect(jsonPath("$.category").value("CLEANING")).andExpect(jsonPath("$.areaSqm").value(60))
                .andExpect(jsonPath("$.addressText").value("Алматы, ул. Тестовая 1, кв. 5"))
                .andExpect(jsonPath("$.priceMinor").value(600_000 + 45_000 * 60)).andExpect(jsonPath("$.durationMinutes").value(180))
                .andExpect(jsonPath("$.status").value("CONFIRMED")));
        String id = JsonPath.read(created, "$.id");
        assertThat(db.queryForObject("select area_sqm from transactions.bookings where id = ?::uuid", Integer.class, id)).isEqualTo(60);

        // The crew's time is blocked for everybody; the same customer cannot overlap themselves.
        send("POST", "/api/v1/booking/bookings", other, body, "clean-key-0000000007").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("SLOT_UNAVAILABLE"));
        assertThat(slots("home-clean-demo", service, masterName, tomorrow()).stream().map(x -> x.get("startsAt"))).doesNotContain(startsAt);
        // History keeps the category, shows it for the owner only; free cancellation frees the crew.
        send("GET", "/api/v1/booking/bookings", token, null, null).andExpect(jsonPath("$[0].category").value("CLEANING"));
        send("GET", "/api/v1/booking/bookings/" + id, other, null, null).andExpect(status().isNotFound());
        send("POST", "/api/v1/booking/bookings/" + id + "/cancel", token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CANCELLED"));
        assertThat(slots("home-clean-demo", service, masterName, tomorrow()).stream().map(x -> x.get("startsAt"))).contains(startsAt);
    }

    @Test
    void existingBarbershopBookingsKeepWorkingWithoutAddressOrArea() throws Exception {
        String token = login("+77000000301");
        var slot = slots("barber-alatau", "Мужская стрижка", "Арман", tomorrow()).get(0);
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман",
                (String) slot.get("startsAt"), null), "barber-key-000000001").andExpect(status().isCreated())
                .andExpect(jsonPath("$.category").value("BARBER")).andExpect(jsonPath("$.addressText").doesNotExist())
                .andExpect(jsonPath("$.priceMinor").value(650_000));
    }
}
