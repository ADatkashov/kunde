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
 * Home Services zones, surcharge tariffs and the quote over HTTP against PostgreSQL. The quote and the booking made from it use the
 * same pricing method, a zone refuses addresses outside it, and a partner writes only to its own venues with the right role.
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000431,+77000000432,+77000000433",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class HomeServicesPricingApiIntegrationTest {
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
    UUID partnerA;
    UUID partnerB;
    String service;
    String otherService;

    @BeforeEach
    void seed() throws Exception {
        toggles.invalidate();
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000431','+77000000432','+77000000433')");
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

    private String partnerBase(UUID partner) { return "/api/v1/partner/partners/" + partner + "/home-services/offers"; }

    private String createOffer(String serviceId, String token) throws Exception {
        return JsonPath.read(body(call("POST", partnerBase(partnerA), token,
                "{\"serviceId\":\"" + serviceId + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FROM\",\"warrantyDays\":14}")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("DRAFT"))
                .andExpect(jsonPath("$.version").value(1))), "$.id");
    }

    private ResultActions partnerAct(String offer, String action, long version, String token) throws Exception {
        return call("POST", partnerBase(partnerA) + "/" + offer + "/transition", token,
                "{\"action\":\"" + action + "\",\"expectedVersion\":" + version + "}");
    }

    private ResultActions staffAct(String offer, String action, long version, String reason, String token) throws Exception {
        return call("POST", "/api/v1/admin/home-services/offers/" + offer + "/decision", token,
                "{\"action\":\"" + action + "\",\"expectedVersion\":" + version + ",\"reason\":\"" + reason + "\"}");
    }

    private String zonesBase() { return "/api/v1/partner/partners/" + partnerA + "/home-services/zones"; }

    private String publishedOffer() throws Exception {
        String offer = createOffer(service, owner);
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk());
        staffAct(offer, "APPROVE", 2, "Проверено", staff).andExpect(status().isOk());
        return offer;
    }

    private ResultActions tariff(String offer, long version, String token) throws Exception {
        return call("PUT", partnerBase(partnerA) + "/" + offer + "/tariff", token,
                "{\"callOutFeeMinor\":50000,\"urgentSurchargePercent\":20,\"eveningSurchargePercent\":10,\"eveningFrom\":\"00:00\",\"expectedVersion\":" + version + "}");
    }

    private String firstSlot() throws Exception {
        for (int offset = 1; offset < 7; offset++) {
            var date = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Almaty")).plusDays(offset);
            String slots = body(call("GET", "/api/v1/booking/slots?venueId=" + venueId() + "&serviceId=" + service + "&date=" + date, null, null));
            if (!"[]".equals(slots)) { return slots; }
        }
        throw new IllegalStateException("no free slot in the next week");
    }

    private String venueId() {
        return db.queryForObject("select id::text from marketplace.booking_venues where slug = 'home-clean-demo'", String.class);
    }

    private String bookingJson(String slots, String extra) {
        return "{\"venueId\":\"" + venueId() + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + JsonPath.read(slots, "$[0].masterId")
                + "\",\"startsAt\":\"" + JsonPath.read(slots, "$[0].startsAt") + "\",\"addressText\":\"Алматы, ул. Тестовая 1\",\"areaSqm\":50" + extra + "}";
    }

    private ResultActions book(String json, String key) throws Exception {
        return http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + customer).header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    @Test
    void quoteMatchesTheBookingAndOnlyPublishedOffersAreQuoted() throws Exception {
        String offer = createOffer(service, owner);
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50", null, null).andExpect(status().isNotFound());
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk());
        staffAct(offer, "APPROVE", 2, "Проверено", staff).andExpect(status().isOk());
        tariff(offer, 0, owner).andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1));

        // 600 000 + 45 000 x 50 m2 = 2 850 000; call-out 50 000; urgent 20 % = 570 000; the evening threshold is midnight, so 10 % = 285 000.
        String slots = firstSlot();
        String startsAt = JsonPath.read(slots, "$[0].startsAt");
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50&urgent=true&startsAt=" + java.time.OffsetDateTime.parse(startsAt).withOffsetSameInstant(java.time.ZoneOffset.UTC), null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.listPriceMinor").value(2850000)).andExpect(jsonPath("$.callOutFeeMinor").value(50000))
                .andExpect(jsonPath("$.urgentSurchargeMinor").value(570000)).andExpect(jsonPath("$.eveningSurchargeMinor").value(285000))
                .andExpect(jsonPath("$.totalMinor").value(3755000));
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=5", null, null).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("AREA_INVALID"));

        // The booking made from this quote costs exactly the quoted total; a stale expected price is refused.
        book(bookingJson(slots, ",\"urgent\":true,\"expectedPriceMinor\":1"), "pricing-booking-000000001").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("BOOKING_PRICE_CHANGED"));
        book(bookingJson(slots, ",\"urgent\":true,\"expectedPriceMinor\":3755000"), "pricing-booking-000000002").andExpect(status().isCreated())
                .andExpect(jsonPath("$.priceMinor").value(3755000));
    }

    @Test
    void suspendedPartnerOffersAreHiddenFromCatalogueAndQuoteUntilRestored() throws Exception {
        String offer = publishedOffer();
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(1));
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50", null, null).andExpect(status().isOk());
        db.update("update marketplace.partners set verification_status = 'SUSPENDED' where id = ?", partnerA);
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50", null, null).andExpect(status().isNotFound());
        db.update("update marketplace.partners set verification_status = 'APPROVED' where id = ?", partnerA);
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(1));
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50", null, null).andExpect(status().isOk());
    }

    @Test
    void zoneRefusesAddressesOutsideItAndAVenueWithoutZonesServesTheCity() throws Exception {
        String offer = publishedOffer();
        call("GET", "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50", null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.totalMinor").value(2850000)).andExpect(jsonPath("$.zoneId").doesNotExist());
        String zone = JsonPath.read(body(call("POST", zonesBase(), owner, "{\"venueId\":\"" + venueId()
                + "\",\"name\":\"Центр\",\"centerLat\":43.238,\"centerLng\":76.945,\"radiusM\":3000}").andExpect(status().isCreated())), "$.id");
        String quote = "/api/v1/home-services/offers/" + offer + "/quote?areaSqm=50";
        call("GET", quote, null, null).andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("LOCATION_REQUIRED"));
        call("GET", quote + "&lat=43.25&lng=76.95", null, null).andExpect(status().isOk()).andExpect(jsonPath("$.zoneId").value(zone));
        call("GET", quote + "&lat=43.5&lng=77.5", null, null).andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("OUT_OF_ZONE"));
        // The booking engine applies the same zone: no coordinates or a far address refuse the booking, an address inside is accepted.
        String slots = firstSlot();
        book(bookingJson(slots, ""), "pricing-booking-000000003").andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("LOCATION_REQUIRED"));
        book(bookingJson(slots, ",\"latitude\":43.5,\"longitude\":77.5"), "pricing-booking-000000004").andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("OUT_OF_ZONE"));
        book(bookingJson(slots, ",\"latitude\":43.25,\"longitude\":76.95"), "pricing-booking-000000005").andExpect(status().isCreated());
        // A retired zone no longer restricts the venue.
        call("PUT", zonesBase() + "/" + zone, owner, "{\"name\":\"Центр\",\"centerLat\":43.238,\"centerLng\":76.945,\"radiusM\":3000,\"active\":false,\"expectedVersion\":1}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(2));
        call("GET", quote, null, null).andExpect(status().isOk());
    }

    @Test
    void zonesAndTariffsAreConfinedToTheOwnOrganisationRoleAndVersion() throws Exception {
        String offer = publishedOffer();
        String zoneBody = "{\"venueId\":\"" + venueId() + "\",\"name\":\"Центр\",\"centerLat\":43.238,\"centerLng\":76.945,\"radiusM\":3000}";
        // Another organisation can neither use this path nor this venue or offer.
        call("POST", "/api/v1/partner/partners/" + partnerB + "/home-services/zones", stranger, zoneBody).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("VENUE_NOT_FOUND"));
        call("POST", zonesBase(), stranger, zoneBody).andExpect(status().isNotFound());
        call("PUT", "/api/v1/partner/partners/" + partnerB + "/home-services/offers/" + offer + "/tariff", stranger,
                "{\"callOutFeeMinor\":1,\"urgentSurchargePercent\":0,\"eveningSurchargePercent\":0,\"eveningFrom\":\"20:00\",\"expectedVersion\":0}")
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("OFFER_NOT_FOUND"));
        call("GET", zonesBase(), customer, null).andExpect(status().isForbidden());
        call("GET", zonesBase(), null, null).andExpect(status().isUnauthorized());
        // An operator reads but does not write.
        db.update("update marketplace.partner_staff set role = 'OPERATOR' where partner_id = ?", partnerA);
        call("GET", zonesBase(), owner, null).andExpect(status().isOk());
        call("POST", zonesBase(), owner, zoneBody).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("PARTNER_ROLE_FORBIDDEN"));
        tariff(offer, 0, owner).andExpect(status().isForbidden());
        db.update("update marketplace.partner_staff set role = 'OWNER' where partner_id = ?", partnerA);
        // Optimistic locking: a stale version is a conflict and changes nothing.
        tariff(offer, 0, owner).andExpect(status().isOk());
        tariff(offer, 0, owner).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        tariff(offer, 1, owner).andExpect(status().isOk()).andExpect(jsonPath("$.version").value(2));
        String zone = JsonPath.read(body(call("POST", zonesBase(), owner, zoneBody).andExpect(status().isCreated())), "$.id");
        call("PUT", zonesBase() + "/" + zone, owner, "{\"name\":\"X\",\"centerLat\":43.2,\"centerLng\":76.9,\"radiusM\":1000,\"active\":true,\"expectedVersion\":9}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        call("GET", zonesBase(), owner, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0].version").value(1));
        call("GET", "/api/v1/partner/partners/" + partnerB + "/home-services/zones", stranger, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        call("POST", zonesBase(), owner, zoneBody.replace("\"radiusM\":3000", "\"radiusM\":10")).andExpect(status().isBadRequest());
    }
}
