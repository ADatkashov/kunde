package kz.kunde.beauty;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/** Beauty salons over HTTP against PostgreSQL with the synthetic DEV salons: discovery, details, favorites, promotions. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.beauty.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000311,+77000000312",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class BeautySalonsApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired kz.kunde.platform.FeatureToggles toggles;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000311', '+77000000312')");
        try (var in = new ClassPathResource("beauty/demo-salons.json").getInputStream()) {
            new BeautyDemoSeeder(db, new BeautySettings(new org.springframework.mock.env.MockEnvironment()
                    .withProperty("app.environment", "test"))).seed(new ObjectMapper().readTree(in));
        }
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private ResultActions getJson(String path, String token) throws Exception {
        var request = get(path);
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }

    private String login(String phone) throws Exception {
        http.perform(post("/api/v1/auth/otp/request").contentType(MediaType.APPLICATION_JSON)
                .content("{\"phone\":\"" + phone + "\"}")).andExpect(status().isAccepted());
        return JsonPath.read(body(http.perform(post("/api/v1/auth/otp/verify").contentType(MediaType.APPLICATION_JSON)
                .content("{\"phone\":\"" + phone + "\",\"code\":\"123456\"}")).andExpect(status().isOk())), "$.accessToken");
    }

    private String salonId(String slug) {
        return db.queryForObject("select id from marketplace.booking_venues where slug = ?", String.class, slug);
    }

    @Test
    void salonListHasPaginationTotalAndRealRatings() throws Exception {
        getJson("/api/v1/beauty/salons?limit=2", null).andExpect(status().isOk())
                .andExpect(header().string("X-Total-Count", "6")).andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].name").value("LUNA Beauty Studio"))
                .andExpect(jsonPath("$[0].reviewCount").value(5))
                .andExpect(jsonPath("$[0].rating").value(4.8))
                .andExpect(jsonPath("$[0].fromPriceMinor").value(600000))
                .andExpect(jsonPath("$[0].discountPercent").value(30));
        getJson("/api/v1/beauty/salons?limit=2&offset=4", null).andExpect(jsonPath("$.length()").value(2));
        getJson("/api/v1/beauty/salons?limit=0", null).andExpect(status().isBadRequest());
        getJson("/api/v1/beauty/salons?filter=BOGUS", null).andExpect(status().isBadRequest());
    }

    @Test
    void categoryPriceTextAndVerifiedFiltersAreAppliedOnTheServer() throws Exception {
        getJson("/api/v1/beauty/salons?category=BARBERSHOPS", null).andExpect(header().string("X-Total-Count", "1"))
                .andExpect(jsonPath("$[0].name").value("Barber House"));
        getJson("/api/v1/beauty/salons?q=массаж", null).andExpect(header().string("X-Total-Count", "1"));
        getJson("/api/v1/beauty/salons?q=Алия", null).andExpect(jsonPath("$[0].name").value("LUNA Beauty Studio"));
        getJson("/api/v1/beauty/salons?minPriceMinor=900000", null).andExpect(header().string("X-Total-Count", "2"));
        getJson("/api/v1/beauty/salons?verifiedOnly=true", null).andExpect(header().string("X-Total-Count", "5"));
        getJson("/api/v1/beauty/salons?q=%25", null).andExpect(header().string("X-Total-Count", "0"));
    }

    @Test
    void ratingPromoAndNearbyOrdersWork() throws Exception {
        getJson("/api/v1/beauty/salons?filter=RATING", null).andExpect(status().isOk());
        String rating = body(getJson("/api/v1/beauty/salons?filter=RATING", null));
        List<Double> ratings = JsonPath.read(rating, "$[*].rating");
        assertThat(ratings).isSortedAccordingTo((a, b) -> Double.compare(b, a));
        getJson("/api/v1/beauty/salons?filter=PROMO", null).andExpect(header().string("X-Total-Count", "2"))
                .andExpect(jsonPath("$[0].discountPercent").value(30)).andExpect(jsonPath("$[1].discountPercent").value(15));
        // Standing at Barber House (Dostyk): it is the nearest salon and the distance is reported.
        getJson("/api/v1/beauty/salons?filter=NEARBY&lat=43.2410&lng=76.9570", null).andExpect(jsonPath("$[0].name").value("Barber House"))
                .andExpect(jsonPath("$[0].distanceMeters").value(0));
        getJson("/api/v1/beauty/salons?filter=NEARBY&lat=43.2410&lng=76.9570&maxDistanceMeters=1000", null)
                .andExpect(header().string("X-Total-Count", "2"));
        getJson("/api/v1/beauty/salons?filter=NEARBY", null).andExpect(status().isOk()).andExpect(jsonPath("$[0].distanceMeters").doesNotExist());
        getJson("/api/v1/beauty/salons?lat=43.2", null).andExpect(status().isBadRequest());
    }

    @Test
    void salonAndServiceDetailsCarryMastersReviewsAndNextFreeSlot() throws Exception {
        String detail = body(getJson("/api/v1/beauty/salons/" + salonId("beauty-luna"), null).andExpect(status().isOk())
                .andExpect(jsonPath("$.salon.name").value("LUNA Beauty Studio")).andExpect(jsonPath("$.services.length()").value(4))
                .andExpect(jsonPath("$.masters.length()").value(3)).andExpect(jsonPath("$.reviews.length()").value(5))
                .andExpect(jsonPath("$.services[0].tags[0]").value("Волосы")).andExpect(jsonPath("$.masters[0].specialty").value("Колорист")));
        assertThat((String) JsonPath.read(detail, "$.cancellationPolicy")).contains("отмена");
        String service = db.queryForObject("select s.id from marketplace.booking_services s join marketplace.booking_venues v on v.id = s.venue_id "
                + "where v.slug = 'beauty-luna' and s.name = 'Окрашивание волос'", String.class);
        getJson("/api/v1/beauty/services/" + service, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.service.priceFrom").value(true)).andExpect(jsonPath("$.service.priceMinor").value(2500000))
                .andExpect(jsonPath("$.includes.length()").value(4)).andExpect(jsonPath("$.masters.length()").value(1))
                .andExpect(jsonPath("$.masters[0].name").value("Алия С.")).andExpect(jsonPath("$.masters[0].nextSlotAt").isNotEmpty());
        getJson("/api/v1/beauty/salons/" + java.util.UUID.randomUUID(), null).andExpect(status().isNotFound());
        getJson("/api/v1/beauty/services/" + java.util.UUID.randomUUID(), null).andExpect(status().isNotFound());
    }

    @Test
    void promotionsListOnlyActiveOnesWithTheMaximumPercent() throws Exception {
        getJson("/api/v1/beauty/promotions", null).andExpect(status().isOk()).andExpect(jsonPath("$.maxPercent").value(30))
                .andExpect(jsonPath("$.items.length()").value(2));
        db.update("update marketplace.beauty_promotions set active = false");
        getJson("/api/v1/beauty/promotions", null).andExpect(jsonPath("$.maxPercent").doesNotExist()).andExpect(jsonPath("$.items.length()").value(0));
    }

    @Test
    void activePromotionIsAppliedToTheBookingPriceOnTheServerAndTheExpectedPriceIsChecked() throws Exception {
        String token = login("+77000000311");
        String venue = salonId("beauty-luna");
        String service = db.queryForObject("select s.id from marketplace.booking_services s where s.venue_id = ?::uuid and s.name = 'Окрашивание волос'", String.class, venue);
        String day = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Almaty")).plusDays(2).toString();
        String slots = body(http.perform(get("/api/v1/booking/slots?venueId=" + venue + "&serviceId=" + service + "&date=" + day)).andExpect(status().isOk()));
        String request = "{\"venueId\":\"" + venue + "\",\"serviceId\":\"" + service + "\",\"masterId\":\""
                + JsonPath.read(slots, "$[0].masterId") + "\",\"startsAt\":\"" + JsonPath.read(slots, "$[0].startsAt") + "\"";
        http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + token).header("Idempotency-Key", "beauty-price-000000001")
                .contentType(MediaType.APPLICATION_JSON).content(request + ",\"expectedPriceMinor\":2500000}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BOOKING_PRICE_CHANGED"));
        http.perform(post("/api/v1/booking/bookings").header("Authorization", "Bearer " + token).header("Idempotency-Key", "beauty-price-000000002")
                .contentType(MediaType.APPLICATION_JSON).content(request + ",\"expectedPriceMinor\":1750000}"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.priceMinor").value(1750000))
                .andExpect(jsonPath("$.originalPriceMinor").value(2500000)).andExpect(jsonPath("$.discountPercent").value(30))
                .andExpect(jsonPath("$.bookingNumber").value(org.hamcrest.Matchers.matchesPattern("KND-\\d{6,}")));
    }

    @Test
    void favoritesAreOwnedAndIdempotent() throws Exception {
        String mine = login("+77000000311");
        String other = login("+77000000312");
        String luna = salonId("beauty-luna");
        http.perform(get("/api/v1/beauty/favorites")).andExpect(status().isUnauthorized());
        http.perform(put("/api/v1/beauty/favorites/" + luna).header("Authorization", "Bearer " + mine)).andExpect(status().isNoContent());
        http.perform(put("/api/v1/beauty/favorites/" + luna).header("Authorization", "Bearer " + mine)).andExpect(status().isNoContent());
        http.perform(get("/api/v1/beauty/favorites").header("Authorization", "Bearer " + mine))
                .andExpect(jsonPath("$.length()").value(1)).andExpect(jsonPath("$[0]").value(luna));
        http.perform(get("/api/v1/beauty/favorites").header("Authorization", "Bearer " + other)).andExpect(jsonPath("$.length()").value(0));
        http.perform(put("/api/v1/beauty/favorites/" + java.util.UUID.randomUUID()).header("Authorization", "Bearer " + mine))
                .andExpect(status().isNotFound());
        http.perform(delete("/api/v1/beauty/favorites/" + luna).header("Authorization", "Bearer " + mine)).andExpect(status().isNoContent());
        http.perform(get("/api/v1/beauty/favorites").header("Authorization", "Bearer " + mine)).andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void everythingIsHiddenWhileBeautyIsSwitchedOff() throws Exception {
        String mine = login("+77000000311");
        java.util.UUID admin = db.queryForObject("select id from identity.users limit 1", java.util.UUID.class);
        try {
            toggles.set(admin, kz.kunde.platform.FeatureToggles.Feature.BEAUTY, false, "Disable test", null);
            getJson("/api/v1/beauty/salons", null).andExpect(status().isNotFound());
            getJson("/api/v1/beauty/salons/" + salonId("beauty-luna"), null).andExpect(status().isNotFound());
            getJson("/api/v1/beauty/promotions", null).andExpect(status().isNotFound());
            http.perform(get("/api/v1/beauty/favorites").header("Authorization", "Bearer " + mine)).andExpect(status().isNotFound());
        } finally {
            toggles.invalidate();
        }
    }
}
