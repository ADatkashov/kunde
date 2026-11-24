package kz.kunde.beauty;

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
import java.util.UUID;
import kz.kunde.booking.BookingDemoSeeder;
import kz.kunde.auth.PhoneAuthProperties;
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

/**
 * Beauty Partner overview, Executor (master) appointments and Admin analytics over HTTP against PostgreSQL:
 * ownership isolation, invite-code linking, the appointment state machine, online/offline for new bookings only,
 * a master's own earnings and the grant-protected analytics. Synthetic data only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.food.enabled=true",
        "app.booking.enabled=true",
        "app.beauty.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000421,+77000000422,+77000000423,+77000000424",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class BeautyOperationsApiIntegrationTest {
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    String owner;        // partner A owner (+77000000002), owns LUNA
    String stranger;     // partner B owner (+77000000003)
    String customer;     // +77000000421
    String master;       // +77000000422, linked to «Алия С.»
    UUID partnerA;
    String luna;
    String service;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000421','+77000000422','+77000000423','+77000000424')");
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json", "food/flowers-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) { new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in)); }
        }
        try (var in = new ClassPathResource("beauty/demo-salons.json").getInputStream()) {
            new BeautyDemoSeeder(db, new BeautySettings(new org.springframework.mock.env.MockEnvironment().withProperty("app.environment", "test")))
                    .seed(new ObjectMapper().readTree(in));
        }
        partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        luna = db.queryForObject("select id from marketplace.booking_venues where slug = 'beauty-luna'", String.class);
        db.update("update marketplace.booking_venues set partner_id = ? where id = ?::uuid", partnerA, luna);
        service = db.queryForObject("select id from marketplace.booking_services where venue_id = ?::uuid and name = 'Окрашивание волос'", String.class, luna);
        owner = login("+77000000002");
        stranger = login("+77000000003");
        customer = login("+77000000421");
        master = login("+77000000422");
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String loginBody(String phone) throws Exception {
        http.perform(post("/api/v1/auth/otp/request").contentType(MediaType.APPLICATION_JSON).content("{\"phone\":\"" + phone + "\"}"))
                .andExpect(status().isAccepted());
        return body(http.perform(post("/api/v1/auth/otp/verify").contentType(MediaType.APPLICATION_JSON)
                .content("{\"phone\":\"" + phone + "\",\"code\":\"123456\"}")).andExpect(status().isOk()));
    }

    private String login(String phone) throws Exception { return JsonPath.read(loginBody(phone), "$.accessToken"); }

    private ResultActions call(String method, String path, String token, String json) throws Exception {
        var request = switch (method) { case "PUT" -> put(path); case "POST" -> post(path); default -> get(path); };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }

    /** Books «Окрашивание волос» with the only qualified master on the given day offset and returns the booking id. */
    private String book(int dayOffset, String key) throws Exception {
        String day = LocalDate.now(ALMATY).plusDays(dayOffset).toString();
        String slots = body(call("GET", "/api/v1/booking/slots?venueId=" + luna + "&serviceId=" + service + "&date=" + day, null, null).andExpect(status().isOk()));
        String request = "{\"venueId\":\"" + luna + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + JsonPath.read(slots, "$[0].masterId")
                + "\",\"startsAt\":\"" + JsonPath.read(slots, "$[0].startsAt") + "\"}";
        var created = http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + customer).header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON).content(request)).andExpect(status().isCreated());
        return JsonPath.read(body(created), "$.id");
    }

    private String partnerBase() { return "/api/v1/partner/partners/" + partnerA + "/beauty"; }

    private void link() throws Exception {
        call("POST", "/api/v1/executor/beauty/link", master, "{\"code\":\"demo-aliya\"}").andExpect(status().isNoContent());
    }

    @Test
    void partnerSeesOnlyOwnSalonsWithTodaysNumbersAndMasterInviteCodes() throws Exception {
        String today = book(1, "beauty-ops-0000000001");
        String yesterday = book(2, "beauty-ops-0000000002");
        db.update("update transactions.bookings set status = 'COMPLETED', starts_at = ((now() at time zone 'Asia/Almaty')::date + time '00:10') at time zone 'Asia/Almaty', "
                + "ends_at = ((now() at time zone 'Asia/Almaty')::date + time '01:10') at time zone 'Asia/Almaty' where id = ?::uuid", today);
        db.update("update transactions.bookings set status = 'COMPLETED', starts_at = (((now() at time zone 'Asia/Almaty')::date - 1) + time '00:10') at time zone 'Asia/Almaty', "
                + "ends_at = (((now() at time zone 'Asia/Almaty')::date - 1) + time '01:10') at time zone 'Asia/Almaty' where id = ?::uuid", yesterday);

        call("GET", partnerBase() + "/overview", owner, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.salons[?(@.name=='LUNA Beauty Studio')].id").value(luna))
                .andExpect(jsonPath("$.bookingsToday").value(1)).andExpect(jsonPath("$.revenueTodayMinor").value(1750000))
                .andExpect(jsonPath("$.bookingsDeltaPercent").value(0)).andExpect(jsonPath("$.revenueDeltaPercent").value(0))
                .andExpect(jsonPath("$.mastersTotal").value(org.hamcrest.Matchers.greaterThanOrEqualTo(3)))
                .andExpect(jsonPath("$.mastersOnline").value(org.hamcrest.Matchers.greaterThanOrEqualTo(3)));
        call("GET", partnerBase() + "/masters", owner, null).andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.name=='Алия С.')].inviteCode").value("DEMO-ALIYA"))
                .andExpect(jsonPath("$[?(@.name=='Алия С.')].linked").value(false));
        call("GET", partnerBase() + "/overview", stranger, null).andExpect(status().isNotFound());
        call("GET", partnerBase() + "/overview", customer, null).andExpect(status().isForbidden());
        call("GET", partnerBase() + "/overview", null, null).andExpect(status().isUnauthorized());
    }

    @Test
    void masterLinksOnceWithAnInviteCodeAndSeesOnlyOwnAppointments() throws Exception {
        call("GET", "/api/v1/executor/beauty/today", master, null).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("NOT_A_MASTER"));
        call("POST", "/api/v1/executor/beauty/link", master, "{\"code\":\"WRONG-CODE\"}").andExpect(status().isNotFound());
        link();
        call("POST", "/api/v1/executor/beauty/link", login("+77000000423"), "{\"code\":\"DEMO-ALIYA\"}").andExpect(status().isNotFound());
        call("GET", partnerBase() + "/masters", owner, null).andExpect(jsonPath("$[?(@.name=='Алия С.')].linked").value(true))
                .andExpect(jsonPath("$[?(@.name=='Алия С.')].inviteCode[0]").doesNotExist());

        String id = book(1, "beauty-ops-0000000003");
        call("GET", "/api/v1/executor/beauty/today", master, null).andExpect(status().isOk()).andExpect(jsonPath("$.masterName").value("Алия С."))
                .andExpect(jsonPath("$.online").value(true)).andExpect(jsonPath("$.appointments.length()").value(1))
                .andExpect(jsonPath("$.appointments[0].id").value(id))
                .andExpect(jsonPath("$.appointments[0].bookingNumber").value(org.hamcrest.Matchers.matchesPattern("KND-\\d{6,}")))
                .andExpect(jsonPath("$.appointments[0].canStart").value(false));
        // Someone else's master account sees nothing of it and cannot act on it.
        String other = login("+77000000424");
        call("POST", "/api/v1/executor/beauty/link", other, "{\"code\":\"DEMO-MADINA\"}").andExpect(status().isNoContent());
        call("GET", "/api/v1/executor/beauty/today", other, null).andExpect(jsonPath("$.appointments.length()").value(0));
        call("POST", "/api/v1/executor/beauty/appointments/" + id + "/start", other, null).andExpect(status().isNotFound());
    }

    @Test
    void appointmentStateMachineAndEarningsBelongToTheMaster() throws Exception {
        link();
        String id = book(1, "beauty-ops-0000000004");
        String early = "/api/v1/executor/beauty/appointments/" + id;
        call("POST", early + "/start", master, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("APPOINTMENT_TOO_EARLY"));
        call("POST", early + "/complete", master, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("APPOINTMENT_STATE_INVALID"));
        call("POST", early + "/no-show", master, null).andExpect(status().isConflict());

        db.update("update transactions.bookings set starts_at = now() - interval '5 minutes', ends_at = now() + interval '55 minutes' where id = ?::uuid", id);
        call("GET", "/api/v1/executor/beauty/today", master, null).andExpect(jsonPath("$.appointments[0].canStart").value(true))
                .andExpect(jsonPath("$.appointments[0].canComplete").value(false));
        call("POST", early + "/start", master, null).andExpect(status().isNoContent());
        call("POST", early + "/start", master, null).andExpect(status().isConflict());
        call("GET", "/api/v1/executor/beauty/today", master, null).andExpect(jsonPath("$.appointments[0].status").value("IN_PROGRESS"))
                .andExpect(jsonPath("$.appointments[0].canComplete").value(true));
        call("GET", "/api/v1/executor/beauty/earnings", master, null).andExpect(jsonPath("$.monthMinor").value(0));
        call("POST", early + "/complete", master, null).andExpect(status().isNoContent());
        call("GET", "/api/v1/executor/beauty/earnings", master, null).andExpect(status().isOk()).andExpect(jsonPath("$.monthMinor").value(1750000))
                .andExpect(jsonPath("$.completedMonth").value(1)).andExpect(jsonPath("$.currency").value("KZT"));
        assertThat(db.queryForList("select status from transactions.booking_events where booking_id = ?::uuid order by id", String.class, id))
                .endsWith("IN_PROGRESS", "COMPLETED");
        call("GET", "/api/v1/booking/bookings/" + id, customer, null).andExpect(jsonPath("$.status").value("COMPLETED"));

        db.update("update transactions.bookings set starts_at = now() - interval '5 hours', ends_at = now() - interval '4 hours' where id = ?::uuid", id);
        String late = book(2, "beauty-ops-0000000005");
        db.update("update transactions.bookings set starts_at = now() - interval '20 minutes', ends_at = now() + interval '40 minutes' where id = ?::uuid", late);
        call("POST", "/api/v1/executor/beauty/appointments/" + late + "/no-show", master, null).andExpect(status().isNoContent());
        call("GET", "/api/v1/booking/bookings/" + late, customer, null).andExpect(jsonPath("$.status").value("NO_SHOW"));
    }

    @Test
    void goingOfflineStopsNewBookingsButKeepsConfirmedOnes() throws Exception {
        link();
        String id = book(1, "beauty-ops-0000000006");
        call("PUT", "/api/v1/executor/beauty/availability", master, "{\"online\":false}").andExpect(status().isNoContent());
        call("GET", "/api/v1/executor/beauty/today", master, null).andExpect(jsonPath("$.online").value(false)).andExpect(jsonPath("$.appointments.length()").value(1));
        call("GET", "/api/v1/booking/bookings/" + id, customer, null).andExpect(jsonPath("$.status").value("CONFIRMED"));
        String day = LocalDate.now(ALMATY).plusDays(3).toString();
        call("GET", "/api/v1/booking/slots?venueId=" + luna + "&serviceId=" + service + "&date=" + day, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        call("PUT", "/api/v1/executor/beauty/availability", master, "{\"online\":true}").andExpect(status().isNoContent());
        call("GET", "/api/v1/booking/slots?venueId=" + luna + "&serviceId=" + service + "&date=" + day, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(org.hamcrest.Matchers.greaterThan(0)));
    }

    @Test
    void adminAnalyticsNeedTheBeautyGrantAndReturnAggregates() throws Exception {
        String done = book(1, "beauty-ops-0000000007");
        db.update("update transactions.bookings set status = 'COMPLETED', starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour' where id = ?::uuid", done);
        String session = loginBody("+77000000424");
        UUID adminUser = UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(session, "$.accessToken")).getJWTClaimsSet().getSubject());
        call("GET", "/api/v1/admin/beauty/analytics", JsonPath.read(session, "$.accessToken"), null).andExpect(status().isForbidden());
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'BEAUTY_OPERATIONS', 'synthetic DEV admin')", adminUser);
        String admin = JsonPath.read(body(http.perform(post("/api/v1/auth/token/refresh").contentType(MediaType.APPLICATION_JSON)
                .content("{\"refreshToken\":\"" + JsonPath.read(session, "$.refreshToken") + "\"}"))), "$.accessToken");
        call("GET", "/api/v1/admin/beauty/analytics?days=7", admin, null).andExpect(status().isOk()).andExpect(jsonPath("$.salons").value(6))
                .andExpect(jsonPath("$.bookings").value(1)).andExpect(jsonPath("$.revenueMinor").value(1750000))
                .andExpect(jsonPath("$.averageCheckMinor").value(1750000)).andExpect(jsonPath("$.bookingsByDay.length()").value(7))
                .andExpect(jsonPath("$.categories[0].code").value("HAIR")).andExpect(jsonPath("$.categories[0].percent").value(100))
                .andExpect(jsonPath("$.recent[0].salon").value("LUNA Beauty Studio"));
        call("GET", "/api/v1/admin/beauty/analytics?days=0", admin, null).andExpect(status().isBadRequest());
        call("GET", "/api/v1/admin/beauty/analytics", customer, null).andExpect(status().isForbidden());
    }
}
