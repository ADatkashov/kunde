package kz.kunde.homeservices;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
 * Moderated Home Services offers over HTTP against PostgreSQL: the public catalogue shows only PUBLISHED offers, a partner
 * is confined to its own organisation, staff moderation needs the HOME_SERVICES_CATALOG grant, and every state change is
 * versioned and audited. Synthetic data only; the whole test rolls back.
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
class HomeServicesOffersApiIntegrationTest {
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
        var request = "POST".equals(method) ? post(path) : get(path);
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

    @Test
    void offerIsPublicOnlyWhilePublishedAndEveryStepIsAudited() throws Exception {
        String offer = createOffer(service, owner);
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));

        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"));
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(0));
        call("GET", "/api/v1/admin/home-services/offers?status=PENDING", staff, null).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(offer)).andExpect(jsonPath("$[0].partnerId").value(partnerA.toString()));

        staffAct(offer, "APPROVE", 2, "checked documents", staff).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PUBLISHED"));
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].id").value(offer))
                .andExpect(jsonPath("$[0].definitionCode").value("DEEP_CLEAN"))
                .andExpect(jsonPath("$[0].categoryCode").value("CLEANING"))
                .andExpect(jsonPath("$[0].nameRu").value("Генеральная уборка"))
                .andExpect(jsonPath("$[0].nameKk").exists()).andExpect(jsonPath("$[0].nameEn").value("Deep cleaning"))
                .andExpect(jsonPath("$[0].pricingModel").value("FROM"))
                .andExpect(jsonPath("$[0].warrantyDays").value(14))
                .andExpect(jsonPath("$[0].pricePerSqmMinor").isNumber())
                .andExpect(jsonPath("$[0].priceMinor").value(org.hamcrest.Matchers.greaterThan(0)));
        call("GET", "/api/v1/home-services/offers?category=PLUMBING", null, null).andExpect(jsonPath("$.length()").value(0));
        call("GET", "/api/v1/home-services/offers?category=CLEANING&limit=1&offset=1", null, null).andExpect(jsonPath("$.length()").value(0));
        call("GET", "/api/v1/home-services/offers?limit=0", null, null).andExpect(status().isBadRequest());

        staffAct(offer, "SUSPEND", 3, "complaint under review", staff).andExpect(jsonPath("$.status").value("SUSPENDED"));
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(0));
        staffAct(offer, "RESTORE", 4, "complaint resolved", staff).andExpect(jsonPath("$.status").value("PUBLISHED"));
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(1));
        partnerAct(offer, "WITHDRAW", 5, owner).andExpect(jsonPath("$.status").value("DRAFT"));
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(0));

        // A closed venue or an unavailable service hides even a published offer.
        partnerAct(offer, "SUBMIT", 6, owner).andExpect(status().isOk());
        staffAct(offer, "APPROVE", 7, "approved again", staff).andExpect(status().isOk());
        db.update("update marketplace.booking_services set available = false where id = ?::uuid", service);
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(0));

        var history = db.queryForList("select version, actor_role, from_status, to_status from marketplace.home_service_offer_events "
                + "where offer_id = ?::uuid order by version", offer);
        assertThat(history).hasSize(8);
        assertThat(history.getFirst().get("from_status")).isNull();
        assertThat(history.getFirst().get("to_status")).isEqualTo("DRAFT");
        assertThat(history.get(2).get("actor_role")).isEqualTo("ADMIN");
        assertThatThrownBy(() -> db.update("update marketplace.home_service_offer_events set reason = 'x' where offer_id = ?::uuid", offer))
                .hasMessageContaining("");
    }

    @Test
    void publicCatalogHidesOffersOfNonApprovedPartners() throws Exception {
        String offer = createOffer(service, owner);
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk());
        staffAct(offer, "APPROVE", 2, "checked documents", staff).andExpect(status().isOk());
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(1));

        db.update("update marketplace.partners set verification_status = 'SUSPENDED' where id = ?", partnerA);
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        assertThat(db.queryForObject("select status from marketplace.home_service_offers where id = ?::uuid", String.class, offer)).isEqualTo("PUBLISHED");

        db.update("update marketplace.partners set verification_status = 'APPROVED' where id = ?", partnerA);
        call("GET", "/api/v1/home-services/offers", null, null).andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0].id").value(offer));
    }

    @Test
    void offerAuthorityBelongsToPartnerRolesAndStatus() throws Exception {
        String offer = createOffer(service, owner);
        // An operator may read the organisation's offers but not manage them: Partner decides which roles carry the authority.
        db.update("update marketplace.partner_staff set role = 'OPERATOR' where partner_id = ?", partnerA);
        call("GET", partnerBase(partnerA), owner, null).andExpect(status().isOk());
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("PARTNER_ROLE_FORBIDDEN"));
        call("POST", partnerBase(partnerA), owner, "{\"serviceId\":\"" + otherService + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FIXED\"}")
                .andExpect(status().isForbidden());
        // A suspended organisation is invisible to its own staff: nothing can be written or listed.
        db.update("update marketplace.partner_staff set role = 'OWNER' where partner_id = ?", partnerA);
        db.update("update marketplace.partners set verification_status = 'SUSPENDED' where id = ?", partnerA);
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isNotFound());
        call("GET", partnerBase(partnerA), owner, null).andExpect(status().isNotFound());
        assertThat(db.queryForObject("select status from marketplace.home_service_offers where id = ?::uuid", String.class, offer)).isEqualTo("DRAFT");
    }

    @Test
    void partnerIsConfinedToItsOwnOrganisation() throws Exception {
        // Partner B can not offer partner A's service, even by guessing its id.
        call("POST", partnerBase(partnerB), stranger, "{\"serviceId\":\"" + service + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FIXED\"}")
                .andExpect(status().isNotFound());
        // A partner can not use another partner's path.
        call("GET", partnerBase(partnerA), stranger, null).andExpect(status().isNotFound());

        String offer = createOffer(service, owner);
        call("POST", partnerBase(partnerB) + "/" + offer + "/transition", stranger, "{\"action\":\"SUBMIT\",\"expectedVersion\":1}")
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("OFFER_NOT_FOUND"));
        call("GET", partnerBase(partnerB), stranger, null).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
        call("GET", partnerBase(partnerA), owner, null).andExpect(status().isOk()).andExpect(jsonPath("$[0].id").value(offer));
        call("GET", partnerBase(partnerA), customer, null).andExpect(status().isForbidden());
        call("GET", partnerBase(partnerA), null, null).andExpect(status().isUnauthorized());
        assertThat(db.queryForObject("select status from marketplace.home_service_offers where id = ?::uuid", String.class, offer)).isEqualTo("DRAFT");
    }

    @Test
    void moderationNeedsTheGrantAndAPartnerCanNotModerateItself() throws Exception {
        String offer = createOffer(service, owner);
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk());

        staffAct(offer, "APPROVE", 2, "ok ok", noGrant).andExpect(status().isForbidden());
        staffAct(offer, "APPROVE", 2, "ok ok", owner).andExpect(status().isForbidden());
        staffAct(offer, "APPROVE", 2, "ok ok", null).andExpect(status().isUnauthorized());
        call("GET", "/api/v1/admin/home-services/offers", noGrant, null).andExpect(status().isForbidden());
        // A partner can not use a staff action, and staff can not submit on behalf of a partner.
        partnerAct(offer, "APPROVE", 2, owner).andExpect(status().isBadRequest());
        assertThat(db.queryForObject("select status from marketplace.home_service_offers where id = ?::uuid", String.class, offer)).isEqualTo("PENDING");
        staffAct(offer, "APPROVE", 2, "ok", staff).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("REASON_REQUIRED"));
    }

    @Test
    void staleVersionsAndImpossibleTransitionsChangeNothing() throws Exception {
        String offer = createOffer(service, owner);
        partnerAct(offer, "SUBMIT", 7, owner).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        staffAct(offer, "APPROVE", 1, "cannot approve a draft", staff).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("INVALID_TRANSITION"));
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isOk());
        partnerAct(offer, "SUBMIT", 1, owner).andExpect(status().isConflict()); // replayed request
        partnerAct(offer, "SUBMIT", 2, owner).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("INVALID_TRANSITION"));
        staffAct(offer, "REJECT", 2, "photos are missing", staff).andExpect(jsonPath("$.status").value("REJECTED"))
                .andExpect(jsonPath("$.statusReason").value("photos are missing"));
        partnerAct(offer, "SUBMIT", 3, owner).andExpect(jsonPath("$.status").value("PENDING")); // resubmission after rejection
        assertThat(db.queryForObject("select count(*) from marketplace.home_service_offer_events where offer_id = ?::uuid", Integer.class, offer))
                .isEqualTo(4);

        call("POST", partnerBase(partnerA), owner, "{\"serviceId\":\"" + service + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FIXED\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("OFFER_EXISTS"));
        call("POST", partnerBase(partnerA), owner, "{\"serviceId\":\"" + otherService + "\",\"definitionCode\":\"NO_SUCH\",\"pricingModel\":\"FIXED\"}")
                .andExpect(status().isUnprocessableEntity());
        call("POST", partnerBase(partnerA), owner, "{\"serviceId\":\"" + otherService + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FREE\"}")
                .andExpect(status().isBadRequest());
        call("POST", partnerBase(partnerA), owner, "{\"serviceId\":\"" + otherService + "\",\"definitionCode\":\"DEEP_CLEAN\",\"pricingModel\":\"FIXED\",\"warrantyDays\":5000}")
                .andExpect(status().isBadRequest());
    }
}
