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
 * Master onboarding of Home Services over HTTP against PostgreSQL: the partner creates a master of its cleaning venue, hands out a
 * one-time invite code, the master links it in Executor; reissue, retirement, roles, other organisations and the venue limit.
 * Synthetic data; the test rolls back.
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
class HomeServicesMastersApiIntegrationTest {
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

    private String base() { return "/api/v1/partner/partners/" + partnerA + "/home-services/masters"; }

    private ResultActions create(String name, String token) throws Exception {
        return call("POST", base(), token, "{\"venueId\":\"" + venueId() + "\",\"name\":\"" + name + "\"}");
    }

    private ResultActions link(String code, String token) throws Exception {
        return call("POST", "/api/v1/executor/home-services/link", token, "{\"code\":\"" + code + "\"}");
    }

    private String createdMasterId(ResultActions created) throws Exception { return JsonPath.read(body(created), "$.id"); }

    @Test
    void partnerCreatesMasterAndTheMasterLinksTheInviteCodeInExecutor() throws Exception {
        String json = body(create("Алия Тестова", owner).andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Алия Тестова")).andExpect(jsonPath("$.linked").value(false))
                .andExpect(jsonPath("$.venueId").value(venueId())).andExpect(jsonPath("$.inviteCode").value(org.hamcrest.Matchers.matchesPattern("H[A-Z2-9]{4}-[A-Z2-9]{5}"))));
        String id = JsonPath.read(json, "$.id");
        String code = JsonPath.read(json, "$.inviteCode");

        call("GET", base(), owner, null).andExpect(status().isOk()).andExpect(jsonPath("$[?(@.id=='" + id + "')].linked").value(false));
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("NOT_A_MASTER"));

        link(code.toLowerCase(), executor).andExpect(status().isNoContent());
        call("GET", "/api/v1/executor/home-services/jobs", executor, null).andExpect(status().isOk());
        // Linked: the code is no longer shown and works no more; a second account can not take the same master.
        String listed = body(call("GET", base(), owner, null).andExpect(jsonPath("$[?(@.id=='" + id + "')].linked").value(true)));
        java.util.List<Object> shownCodes = JsonPath.read(listed, "$[?(@.id=='" + id + "')].inviteCode");
        assertThat(shownCodes).as("a linked master shows no invite code").allMatch(java.util.Objects::isNull);
        link(code, customer).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("INVITE_INVALID"));
        call("POST", base() + "/" + id + "/invite", owner, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("MASTER_LINKED"));

        // The new master works like the seeded ones: all venue services, working days, and an audit trail.
        assertThat(db.queryForObject("select count(*) from marketplace.booking_master_services where master_id = ?::uuid", Long.class, id)).isGreaterThan(0L);
        assertThat(db.queryForObject("select count(*) from marketplace.booking_working_hours where master_id = ?::uuid", Long.class, id)).isEqualTo(6L);
        assertThat(db.queryForObject("select count(*) from marketplace.partner_catalog_events where entity_type = 'MASTER' and entity_id = ?::uuid", Long.class, id)).isEqualTo(1L);
    }

    @Test
    void reissuedCodeReplacesTheOldOneUntilTheMasterLinks() throws Exception {
        ResultActions created = create("Руслан Тестов", owner).andExpect(status().isCreated());
        String json = body(created);
        String id = JsonPath.read(json, "$.id");
        String oldCode = JsonPath.read(json, "$.inviteCode");
        String newCode = JsonPath.read(body(call("POST", base() + "/" + id + "/invite", owner, null).andExpect(status().isOk())), "$.inviteCode");
        assertThat(newCode).isNotEqualTo(oldCode);
        link(oldCode, executor).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("INVITE_INVALID"));
        link(newCode, executor).andExpect(status().isNoContent());
    }

    @Test
    void onlyCatalogManagersOfTheOwnOrganisationMayChangeMasters() throws Exception {
        call("GET", base(), null, null).andExpect(status().isUnauthorized());
        create("Чужой", stranger).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("PARTNER_NOT_FOUND"));
        call("GET", base(), stranger, null).andExpect(status().isNotFound());
        create("Клиент", customer).andExpect(status().isForbidden());
        // An operator reads the team but can not change it: Partner decides which roles manage the catalogue.
        String id = createdMasterId(create("Мастер Один", owner).andExpect(status().isCreated()));
        db.update("update marketplace.partner_staff set role = 'OPERATOR' where partner_id = ?", partnerA);
        call("GET", base(), owner, null).andExpect(status().isOk());
        create("Мастер Два", owner).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("PARTNER_ROLE_FORBIDDEN"));
        call("POST", base() + "/" + id + "/invite", owner, null).andExpect(status().isForbidden());
        call("POST", base() + "/" + id + "/deactivate", owner, null).andExpect(status().isForbidden());
        // Unknown venue / master, invalid name.
        db.update("update marketplace.partner_staff set role = 'OWNER' where partner_id = ?", partnerA);
        call("POST", base(), owner, "{\"venueId\":\"" + UUID.randomUUID() + "\",\"name\":\"Х\"}").andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("VENUE_NOT_FOUND"));
        call("POST", base() + "/" + UUID.randomUUID() + "/invite", owner, null).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("MASTER_NOT_FOUND"));
        call("POST", base(), owner, "{\"venueId\":\"" + venueId() + "\",\"name\":\"   \"}").andExpect(status().isBadRequest());
        // Another organisation can not retire or reissue this master.
        call("POST", "/api/v1/partner/partners/" + partnerB + "/home-services/masters/" + id + "/deactivate", stranger, null).andExpect(status().isNotFound());
    }

    @Test
    void retiredMasterStopsReceivingBookingsButOnlyWithoutOpenOnes() throws Exception {
        String json = body(create("Айдос Тестов", owner).andExpect(status().isCreated()));
        String id = JsonPath.read(json, "$.id");
        String code = JsonPath.read(json, "$.inviteCode");

        // An open booking of this master blocks retirement. Slots of "any master" show one master per start time, so ask for this one.
        String slotStart = null;
        for (int offset = 1; offset < 7 && slotStart == null; offset++) {
            var date = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Almaty")).plusDays(offset);
            String mine = body(call("GET", "/api/v1/booking/slots?venueId=" + venueId() + "&serviceId=" + service + "&masterId=" + id + "&date=" + date, null, null));
            java.util.List<String> starts = JsonPath.read(mine, "$[*].startsAt");
            if (!starts.isEmpty()) { slotStart = starts.getFirst(); }
        }
        assertThat(slotStart).as("the new master has free slots").isNotNull();
        String booking = JsonPath.read(body(http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + customer)
                .header("Idempotency-Key", "masters-block-00000001").contentType(MediaType.APPLICATION_JSON)
                .content("{\"venueId\":\"" + venueId() + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + id
                        + "\",\"startsAt\":\"" + slotStart + "\",\"addressText\":\"Алматы, ул. Тестовая 1\",\"areaSqm\":40}")).andExpect(status().isCreated())), "$.id");
        call("POST", base() + "/" + id + "/deactivate", owner, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("MASTER_HAS_BOOKINGS"));

        db.update("update transactions.bookings set status = 'CANCELLED' where id = ?::uuid", booking);
        call("POST", base() + "/" + id + "/deactivate", owner, null).andExpect(status().isNoContent());
        call("GET", base(), owner, null).andExpect(jsonPath("$[?(@.id=='" + id + "')]").isEmpty());
        link(code, executor).andExpect(status().isNotFound());   // the code died with the master
        call("POST", base() + "/" + id + "/deactivate", owner, null).andExpect(status().isNotFound());
    }

    @Test
    void aVenueHoldsAtMostFiftyMastersAndTheFeatureFlagHidesTheApi() throws Exception {
        int created = 0;
        while (created < 60) {
            var result = create("Мастер " + created, owner).andReturn().getResponse();
            if (result.getStatus() == 409) {
                assertThat(result.getContentAsString()).contains("TOO_MANY_MASTERS");
                break;
            }
            assertThat(result.getStatus()).isEqualTo(201);
            created++;
        }
        assertThat(db.queryForObject("select count(*) from marketplace.booking_masters where venue_id = ?::uuid and active", Long.class, venueId())).isEqualTo(50L);

        toggles.set(UUID.fromString(executorUser), FeatureToggles.Feature.HOME_SERVICES, false, "synthetic switch-off", null);
        call("GET", base(), owner, null).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("HOME_SERVICES_DISABLED"));
    }
}
