package kz.kunde.booking;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
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

    private static String tomorrow() { return LocalDate.now(ALMATY).plusDays(1).toString(); }

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
        send("POST", "/api/v1/booking/bookings", token, book("barber-alatau", "Мужская стрижка", "Арман", start.minusDays(2).toString(), null),
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
}
