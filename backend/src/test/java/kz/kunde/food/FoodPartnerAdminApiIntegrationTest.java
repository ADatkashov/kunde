package kz.kunde.food;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
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
 * Food 2.0 partner and administrator flows over HTTP against PostgreSQL: pickup state machine for the partner, restaurant
 * settings, partner promotions within limits, tenant isolation, the dashboard summary, and the Admin Food control center
 * (permission gate, moderation, test refund, promotion and review moderation, audit). Synthetic data only; rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.food.enabled=true",
        "app.booking.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000421,+77000000422,+77000000423,+77000000424,+77000000425,+77000000426",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FoodPartnerAdminApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    String owner;
    String otherOwner;
    String customer;
    String admin;
    UUID partnerA;
    UUID restaurant;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000421','+77000000422','+77000000423','+77000000424','+77000000425','+77000000426')");
        FoodDemoSeeder seeder = new FoodDemoSeeder(db);
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) {
                seeder.seed(new ObjectMapper().readTree(in));
            }
        }
        seeder.seedPromotions();
        partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        owner = login("+77000000002");
        otherOwner = login("+77000000003");
        customer = login("+77000000421");
        String adminLogin = loginBody("+77000000422");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'FOOD_OPERATIONS', 'synthetic DEV admin')", subject(adminLogin));
        admin = JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(adminLogin, "$.refreshToken") + "\"}")), "$.accessToken");
        restaurant = UUID.fromString(db.queryForObject("select id from marketplace.food_restaurants where slug = 'partner-kitchen-demo'", String.class));
        db.update("update marketplace.food_restaurants set min_order_minor = 0 where id = ?", restaurant);
    }

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
            case "PATCH" -> patch(path);
            case "DELETE" -> delete(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String login(String phone) throws Exception { return JsonPath.read(loginBody(phone), "$.accessToken"); }

    private String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}").andExpect(status().isOk()));
    }

    private static UUID subject(String loginBody) throws Exception {
        return UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    private String address(String token) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/me/addresses", token,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}")
                .andExpect(status().isCreated())), "$.id");
    }

    private String place(String type, String payment, String key) throws Exception {
        String dish = db.queryForObject("select id from marketplace.food_dishes where restaurant_id = ? and available "
                + "and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = food_dishes.id and g.min_select > 0) limit 1", String.class, restaurant);
        String json = "{\"restaurantId\":\"" + restaurant + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":1,\"optionIds\":[]}],"
                + ("PICKUP".equals(type) ? "\"fulfillmentType\":\"PICKUP\"," : "\"addressId\":\"" + address(customer) + "\",")
                + "\"paymentMethod\":\"" + payment + "\"}";
        var request = post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON).content(json)
                .header("Authorization", "Bearer " + customer).header("Idempotency-Key", key);
        return JsonPath.read(body(http.perform(request).andExpect(status().isCreated())), "$.id");
    }

    private String base() { return "/api/v1/partner/partners/" + partnerA + "/food"; }

    private ResultActions move(String token, String order, String to) throws Exception {
        return send("POST", base() + "/orders/" + order + "/status", token, "{\"status\":\"" + to + "\"}");
    }

    @Test
    void partnerMovesAPickupOrderThroughReadyWithoutACourierLeg() throws Exception {
        String order = place("PICKUP", "TEST_CARD", "partner-pickup-key-0001");
        move(owner, order, "ACCEPTED").andExpect(status().isOk());
        move(owner, order, "PREPARING").andExpect(status().isOk());
        move(owner, order, "ON_THE_WAY").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ORDER_TRANSITION_INVALID"));
        move(owner, order, "READY_FOR_PICKUP").andExpect(status().isOk()).andExpect(jsonPath("$.order.status").value("READY_FOR_PICKUP"))
                .andExpect(jsonPath("$.allowedNext[0]").value("DELIVERED"));
        move(owner, order, "READY_FOR_PICKUP").andExpect(status().isOk()); // idempotent repeat
        send("GET", "/api/v1/food/orders/" + order, customer, null).andExpect(jsonPath("$.status").value("READY_FOR_PICKUP"));
        move(otherOwner, order, "DELIVERED").andExpect(status().isNotFound());
        move(owner, order, "DELIVERED").andExpect(status().isOk());
        move(owner, order, "CANCELLED").andExpect(status().isConflict());
        List<String> timeline = JsonPath.read(body(send("GET", "/api/v1/food/orders/" + order, customer, null)), "$.timeline[*].status");
        assertThat(timeline).containsExactly("PLACED", "ACCEPTED", "PREPARING", "READY_FOR_PICKUP", "DELIVERED");
    }

    @Test
    void deliveryOrderMayBeMarkedReadyForTheCourierBeforeItLeaves() throws Exception {
        String order = place("DELIVERY", "CASH_ON_DELIVERY", "partner-delivery-key-0001");
        move(owner, order, "ACCEPTED").andExpect(status().isOk());
        move(owner, order, "PREPARING").andExpect(status().isOk());
        move(owner, order, "READY_FOR_PICKUP").andExpect(status().isOk());
        move(owner, order, "ON_THE_WAY").andExpect(status().isOk());
        move(owner, order, "DELIVERED").andExpect(status().isOk());
    }

    @Test
    void restaurantSettingsPromotionsAndSummaryAreScopedToTheOwningPartner() throws Exception {
        String r = base() + "/restaurants/" + restaurant;
        send("PATCH", r, owner, "{\"pickupEnabled\":false,\"prepMinutes\":35,\"addressText\":\"Алматы, ул. Демо 1 (вымышленный адрес)\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.pickupEnabled").value(false)).andExpect(jsonPath("$.prepMinutes").value(35));
        send("PATCH", r, owner, "{\"prepMinutes\":999}").andExpect(status().isBadRequest());
        send("PATCH", r, owner, "{\"etaMinMinutes\":50,\"etaMaxMinutes\":20}").andExpect(status().isBadRequest());
        send("PATCH", r, otherOwner, "{\"open\":false}").andExpect(status().isNotFound());
        send("PATCH", r, customer, "{\"open\":false}").andExpect(status().isForbidden());
        assertThat(db.queryForObject("select count(*) from marketplace.food_audit", Integer.class)).isZero(); // settings use the partner audit
        assertThat(db.queryForObject("select count(*) from marketplace.partner_profile_events", Integer.class)).isNotNull();

        String ends = java.time.OffsetDateTime.now().plusDays(30).toString();
        String promo = "{\"code\":\"demo-kitchen15\",\"title\":\"15% в Партнёр-кухне\",\"kind\":\"PERCENT\",\"value\":15,\"restaurantId\":\"" + restaurant
                + "\",\"endsAt\":\"" + ends + "\",\"minSubtotalMinor\":0}";
        String created = body(send("POST", base() + "/promotions", owner, promo).andExpect(status().isCreated()).andExpect(jsonPath("$.code").value("DEMO-KITCHEN15")));
        send("POST", base() + "/promotions", owner, promo).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PROMO_CODE_TAKEN"));
        send("POST", base() + "/promotions", owner, promo.replace("\"value\":15", "\"value\":80").replace("demo-kitchen15", "TOOBIG"))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PROMO_LIMIT_EXCEEDED"));
        send("POST", base() + "/promotions", owner, promo.replace("demo-kitchen15", "LONGONE").replace(ends, java.time.OffsetDateTime.now().plusDays(400).toString()))
                .andExpect(status().isBadRequest());
        String foreign = db.queryForObject("select id from marketplace.food_restaurants where slug = 'pizza-alatau'", String.class);
        send("POST", base() + "/promotions", owner, promo.replace(restaurant.toString(), foreign).replace("demo-kitchen15", "FOREIGN1"))
                .andExpect(status().isNotFound());
        send("POST", base() + "/promotions", otherOwner, promo.replace("demo-kitchen15", "STOLEN1")).andExpect(status().isNotFound());
        String id = JsonPath.read(created, "$.id");
        send("POST", base() + "/promotions/" + id + "/status", owner, "{\"status\":\"PAUSED\"}").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PAUSED"));
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/promotions", null, null)), "$[?(@.code=='DEMO-KITCHEN15')]")).isEmpty();
        send("POST", base() + "/promotions/" + id + "/status", owner, "{\"status\":\"ACTIVE\"}").andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/promotions?restaurantId=" + restaurant, null, null)), "$[?(@.code=='DEMO-KITCHEN15')]")).hasSize(1);

        String order = place("DELIVERY", "CASH_ON_DELIVERY", "partner-summary-key-001");
        String summary = body(send("GET", base() + "/summary", owner, null).andExpect(status().isOk()));
        assertThat((Integer) JsonPath.read(summary, "$.ordersToday")).isEqualTo(1);
        assertThat((Integer) JsonPath.read(summary, "$.activeOrders")).isEqualTo(1);
        assertThat((Integer) JsonPath.read(summary, "$.revenueTodayMinor")).isZero(); // nothing delivered yet
        assertThat((List<?>) JsonPath.read(summary, "$.perDay")).hasSize(7);
        send("GET", base() + "/summary", otherOwner, null).andExpect(status().isNotFound());
        assertThat(order).isNotBlank();
    }

    @Test
    void adminFoodDashboardModerationAndTestRefundAreGatedAndAudited() throws Exception {
        String a = "/api/v1/admin/food";
        send("GET", a + "/summary", customer, null).andExpect(status().isForbidden());
        send("GET", a + "/summary", owner, null).andExpect(status().isForbidden());
        // an empty period shows zeros, not sample numbers
        db.update("delete from transactions.food_promo_redemptions");
        db.update("delete from transactions.food_orders");
        String empty = body(send("GET", a + "/summary", admin, null).andExpect(status().isOk()));
        assertThat((Integer) JsonPath.read(empty, "$.orders")).isZero();
        assertThat((Integer) JsonPath.read(empty, "$.revenueMinor")).isZero();
        assertThat((Integer) JsonPath.read(empty, "$.averageCheckMinor")).isZero();
        assertThat((List<?>) JsonPath.read(empty, "$.perDay")).hasSize(7);

        String order = place("PICKUP", "TEST_CARD", "admin-refund-key-00001");
        send("POST", a + "/orders/" + order + "/refund", admin, "{\"reason\":\"тест\"}").andExpect(status().isConflict()); // still in progress
        move(owner, order, "ACCEPTED").andExpect(status().isOk());
        move(owner, order, "PREPARING").andExpect(status().isOk());
        move(owner, order, "READY_FOR_PICKUP").andExpect(status().isOk());
        move(owner, order, "DELIVERED").andExpect(status().isOk());
        String filled = body(send("GET", a + "/summary", admin, null).andExpect(status().isOk()));
        assertThat((Integer) JsonPath.read(filled, "$.deliveredOrders")).isEqualTo(1);
        assertThat((Integer) JsonPath.read(filled, "$.pickupOrders")).isEqualTo(1);
        assertThat((Integer) JsonPath.read(filled, "$.averageCheckMinor")).isEqualTo((Integer) JsonPath.read(filled, "$.revenueMinor"));
        send("POST", a + "/orders/" + order + "/refund", admin, "{\"reason\":\"x\"}").andExpect(status().isBadRequest());
        send("POST", a + "/orders/" + order + "/refund", admin, "{\"reason\":\"Тестовый возврат\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.paymentStatus").value("REFUNDED"));
        send("POST", a + "/orders/" + order + "/refund", admin, "{\"reason\":\"Тестовый возврат\"}").andExpect(status().isOk()); // idempotent
        assertThat(db.queryForObject("select count(*) from marketplace.food_audit where action = 'ORDER_REFUNDED'", Integer.class)).isEqualTo(1);
        send("GET", "/api/v1/food/orders/" + order, customer, null).andExpect(jsonPath("$.paymentStatus").value("REFUNDED"));
        String rows = body(send("GET", a + "/orders", admin, null).andExpect(status().isOk()));
        assertThat(rows).doesNotContain("Абая").doesNotContain("+7700");
        String cash = place("DELIVERY", "CASH_ON_DELIVERY", "admin-refund-key-00002");
        db.update("update transactions.food_orders set status = 'DELIVERED' where id = ?::uuid", cash);
        send("POST", a + "/orders/" + cash + "/refund", admin, "{\"reason\":\"Тестовый возврат\"}").andExpect(status().isConflict());

        // restaurant moderation: a blocked restaurant disappears from the open catalog and the partner cannot reopen it
        send("POST", a + "/restaurants/" + restaurant + "/moderation", admin, "{\"decision\":\"BLOCK\"}").andExpect(status().isBadRequest());
        send("POST", a + "/restaurants/" + restaurant + "/moderation", admin, "{\"decision\":\"BLOCK\",\"reason\":\"Проверка документов\"}").andExpect(status().isOk());
        send("POST", a + "/restaurants/" + restaurant + "/moderation", admin, "{\"decision\":\"BLOCK\",\"reason\":\"Проверка документов\"}").andExpect(status().isConflict());
        send("GET", "/api/v1/food/restaurants/" + restaurant, null, null).andExpect(jsonPath("$.restaurant.open").value(false));
        send("PATCH", base() + "/restaurants/" + restaurant, owner, "{\"open\":true}").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("RESTAURANT_BLOCKED"));
        send("POST", a + "/restaurants/" + restaurant + "/moderation", admin, "{\"decision\":\"UNBLOCK\",\"reason\":\"Документы проверены\"}").andExpect(status().isOk());

        // promotions: administrator disables, partner cannot re-enable
        String promoId = db.queryForObject("select id from marketplace.food_promotions where code = 'WELCOME10'", String.class);
        send("POST", a + "/promotions/" + promoId + "/status", admin, "{\"status\":\"DISABLED\",\"reason\":\"Нарушение условий\"}").andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/promotions", null, null)), "$[?(@.code=='WELCOME10')]")).isEmpty();
        send("POST", a + "/promotions/" + promoId + "/status", admin, "{\"status\":\"BAD\"}").andExpect(status().isBadRequest());

        // reviews: hide, complaint resolution
        String review = JsonPath.read(body(send("POST", "/api/v1/food/orders/" + order + "/review", customer, "{\"rating\":2,\"comment\":\"Остыло\"}")
                .andExpect(status().isCreated())), "$.id");
        send("POST", "/api/v1/food/reviews/" + review + "/complaints", customer, "{\"reason\":\"Не по теме\"}").andExpect(status().isAccepted());
        String complaint = JsonPath.read(body(send("GET", a + "/complaints", admin, null).andExpect(status().isOk())), "$[0].id");
        send("POST", a + "/reviews/" + review + "/moderation", admin, "{\"decision\":\"HIDE\",\"reason\":\"Нарушает правила\"}").andExpect(status().isOk());
        assertThat((Integer) JsonPath.read(body(send("GET", "/api/v1/food/restaurants/" + restaurant + "/reviews", null, null)), "$.count")).isZero();
        send("POST", a + "/complaints/" + complaint + "/resolve", admin, "{\"resolution\":\"Отзыв скрыт\"}").andExpect(status().isOk());
        send("POST", a + "/complaints/" + complaint + "/resolve", admin, "{\"resolution\":\"Отзыв скрыт\"}").andExpect(status().isNotFound());

        List<String> actions = JsonPath.read(body(send("GET", a + "/audit", admin, null).andExpect(status().isOk())), "$[*].action");
        assertThat(actions).contains("ORDER_REFUNDED", "RESTAURANT_BLOCK", "RESTAURANT_UNBLOCK", "PROMO_DISABLED", "REVIEW_HIDE", "COMPLAINT_RESOLVED");
        send("GET", a + "/restaurants", admin, null).andExpect(status().isOk());
        send("GET", a + "/reviews", admin, null).andExpect(status().isOk());
        send("GET", a + "/promotions", admin, null).andExpect(status().isOk());
    }

    @Test
    void partnerManagesGroceryProductFieldsPhotosAndWeighedProducts() throws Exception {
        String dish = db.queryForObject("select id from marketplace.food_dishes where restaurant_id = ? limit 1", String.class, restaurant);
        String section = db.queryForObject("select section_id from marketplace.food_dishes where id = ?::uuid", String.class, dish);
        String path = base() + "/restaurants/" + restaurant + "/dishes/" + dish;
        long price = db.queryForObject("select price_minor from marketplace.food_dishes where id = ?::uuid", Long.class, dish);

        // Category must exist; the price before a discount must be above the price; nutrition is bounded.
        send("PATCH", path + "/product", owner, "{\"groceryCategory\":\"nope\"}").andExpect(status().isBadRequest());
        send("PATCH", path + "/product", owner, "{\"compareAtPriceMinor\":" + price + "}").andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("COMPARE_PRICE_INVALID"));
        send("PATCH", path + "/product", owner, "{\"protein\":101}").andExpect(status().isBadRequest());
        String saved = body(send("PATCH", path + "/product", owner,
                "{\"groceryCategory\":\"dairy\",\"brand\":\" Жайлау \",\"originCountry\":\"Казахстан\",\"composition\":\"Молоко\","
                        + "\"storageConditions\":\"+2…+6 °C\",\"kcal\":52,\"protein\":2.8,\"fat\":2.5,\"carbs\":4.7,\"compareAtPriceMinor\":" + (price + 1000) + "}")
                .andExpect(status().isOk()));
        assertThat((String) JsonPath.read(saved, "$.brand")).isEqualTo("Жайлау");
        assertThat((Integer) JsonPath.read(saved, "$.kcal")).isEqualTo(52);
        assertThat(db.queryForObject("select grocery_category from marketplace.food_dishes where id = ?::uuid", String.class, dish)).isEqualTo("dairy");
        assertThat(db.queryForObject("select compare_at_price_minor from marketplace.food_dishes where id = ?::uuid", Long.class, dish)).isEqualTo(price + 1000);
        // Raising the price to the old price is refused by the same rule on a later edit of the discount.
        send("PATCH", path + "/product", owner, "{\"clearCompareAt\":true,\"clearCategory\":true,\"brand\":\"\"}").andExpect(status().isOk());
        assertThat(db.queryForObject("select compare_at_price_minor from marketplace.food_dishes where id = ?::uuid", Long.class, dish)).isNull();
        assertThat(db.queryForObject("select brand from marketplace.food_dishes where id = ?::uuid", String.class, dish)).isNull();
        assertThat(db.queryForObject("select count(*) from marketplace.partner_catalog_events where entity_id = ?::uuid and field in ('category','brand','compareAt')",
                Integer.class, dish)).isGreaterThanOrEqualTo(3);

        // Photos: HTTPS only, at most six, the first is the cover, removal moves the cover on.
        send("POST", path + "/photos", owner, "{\"url\":\"http://example.test/a.jpg\"}").andExpect(status().isBadRequest());
        String first = body(send("POST", path + "/photos", owner, "{\"url\":\"https://img.example.test/a.jpg\"}").andExpect(status().isCreated()));
        send("POST", path + "/photos", owner, "{\"url\":\"https://img.example.test/b.jpg\"}").andExpect(status().isCreated());
        assertThat(db.queryForObject("select image_url from marketplace.food_dishes where id = ?::uuid", String.class, dish)).isEqualTo("https://img.example.test/a.jpg");
        String photoId = JsonPath.read(first, "$.photos[0].id");
        send("DELETE", path + "/photos/" + photoId, owner, null).andExpect(status().isOk());
        assertThat(db.queryForObject("select image_url from marketplace.food_dishes where id = ?::uuid", String.class, dish)).isEqualTo("https://img.example.test/b.jpg");
        for (int i = 0; i < 5; i++) { send("POST", path + "/photos", owner, "{\"url\":\"https://img.example.test/p" + i + ".jpg\"}").andExpect(status().isCreated()); }
        send("POST", path + "/photos", owner, "{\"url\":\"https://img.example.test/extra.jpg\"}").andExpect(status().isConflict());
        send("DELETE", path + "/photos/" + UUID.randomUUID(), owner, null).andExpect(status().isNotFound());

        // Tenant isolation: another partner can neither read nor change this store's products.
        send("PATCH", path + "/product", otherOwner, "{\"brand\":\"x\"}").andExpect(status().is4xxClientError());
        send("POST", path + "/photos", otherOwner, "{\"url\":\"https://img.example.test/z.jpg\"}").andExpect(status().is4xxClientError());

        // A weighed product: price per kg, stock in grams.
        String kg = body(send("POST", base() + "/restaurants/" + restaurant + "/dishes", owner,
                "{\"sectionId\":\"" + section + "\",\"name\":\"Яблоки тест\",\"priceMinor\":59000,\"unit\":\"KG\"}").andExpect(status().isCreated()));
        assertThat((String) JsonPath.read(kg, "$.unit")).isEqualTo("KG");
        send("POST", base() + "/restaurants/" + restaurant + "/dishes", owner,
                "{\"sectionId\":\"" + section + "\",\"name\":\"Плохая единица\",\"priceMinor\":100,\"unit\":\"LITER\"}").andExpect(status().isBadRequest());
    }

    private String placeGrocery(String key, String... lines) throws Exception {
        String json = "{\"restaurantId\":\"" + restaurant + "\",\"items\":[" + String.join(",", lines) + "],\"addressId\":\"" + address(customer)
                + "\",\"paymentMethod\":\"TEST_CARD\"}";
        var request = post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON).content(json)
                .header("Authorization", "Bearer " + customer).header("Idempotency-Key", key);
        return body(http.perform(request).andExpect(status().isCreated()));
    }

    private static String line(String dish, String policy) {
        return "{\"dishId\":\"" + dish + "\",\"quantity\":1,\"optionIds\":[],\"substitution\":\"" + policy + "\",\"substituteDishIds\":[]}";
    }

    @Test
    void groceryPickingNeedsEveryLineDecidedAndTheCustomersAnswerToAProposal() throws Exception {
        db.update("update marketplace.food_restaurants set vertical = 'GROCERY' where id = ?", restaurant);
        List<String> dishes = db.queryForList("select id::text from marketplace.food_dishes d where d.restaurant_id = ? and d.available and d.unit = 'PIECE' "
                + "and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = d.id and g.min_select > 0) order by d.name limit 3", String.class, restaurant);
        String d1 = dishes.get(0), d2 = dishes.get(1), d3 = dishes.get(2);
        long p1 = db.queryForObject("select price_minor from marketplace.food_dishes where id = ?::uuid", Long.class, d1);
        long p3 = db.queryForObject("select price_minor from marketplace.food_dishes where id = ?::uuid", Long.class, d3);

        String order = placeGrocery("grocery-pick-0000001", line(d1, "NONE"), line(d2, "NONE"));
        String id = JsonPath.read(order, "$.id");
        assertThat(move(owner, id, "ACCEPTED").andReturn().getResponse().getStatus()).isEqualTo(200);
        String preparing = body(move(owner, id, "PREPARING").andExpect(status().isOk()));
        // Interactive picking: nothing is decided automatically, the order cannot leave the store yet.
        assertThat((List<String>) JsonPath.read(preparing, "$.order.items[*].fulfillmentStatus")).containsOnly("PENDING");
        move(owner, id, "READY_FOR_PICKUP").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PICKING_INCOMPLETE"));
        String item1 = JsonPath.read(preparing, "$.order.items[0].itemId");
        String item2 = JsonPath.read(preparing, "$.order.items[1].itemId");
        String pick = base() + "/orders/" + id + "/items/";

        send("POST", pick + item1 + "/pick", otherOwner, "{\"action\":\"PICKED\"}").andExpect(status().is4xxClientError());
        send("POST", pick + item1 + "/pick", owner, "{\"action\":\"DANCE\"}").andExpect(status().isBadRequest());
        send("POST", pick + item1 + "/pick", owner, "{\"action\":\"PICKED\"}").andExpect(status().isOk());
        send("POST", pick + item1 + "/pick", owner, "{\"action\":\"MISSING\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("ITEM_ALREADY_DECIDED"));
        send("POST", pick + item2 + "/pick", owner, "{\"action\":\"REPLACE\"}").andExpect(status().isBadRequest());
        // The customer did not pre-approve replacements (policy NONE): it becomes a proposal.
        String proposed = body(send("POST", pick + item2 + "/pick", owner, "{\"action\":\"REPLACE\",\"replacementDishId\":\"" + d3 + "\"}").andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(proposed, "$.order.items[?(@.itemId=='" + item2 + "')].fulfillmentStatus")).containsExactly("PROPOSED");
        move(owner, id, "READY_FOR_PICKUP").andExpect(status().isConflict());
        // Only the customer who owns the order can answer.
        send("POST", "/api/v1/food/orders/" + id + "/items/" + item2 + "/decision", owner, "{\"approve\":true}").andExpect(status().isNotFound());
        String decided = body(send("POST", "/api/v1/food/orders/" + id + "/items/" + item2 + "/decision", customer, "{\"approve\":true}").andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(decided, "$.items[?(@.itemId=='" + item2 + "')].fulfillmentStatus")).containsExactly("SUBSTITUTED");
        assertThat(((Number) JsonPath.read(decided, "$.finalTotalMinor")).longValue()).isEqualTo(p1 + p3 + 40000);
        assertThat((Boolean) JsonPath.read(decided, "$.hasChanges")).isTrue();
        send("POST", "/api/v1/food/orders/" + id + "/items/" + item2 + "/decision", customer, "{\"approve\":true}").andExpect(status().isConflict());
        move(owner, id, "READY_FOR_PICKUP").andExpect(status().isOk());

        // Declining the proposal removes the line; with nothing left the order is cancelled by the system.
        String second = placeGrocery("grocery-pick-0000002", line(d1, "NONE"));
        String id2 = JsonPath.read(second, "$.id");
        move(owner, id2, "ACCEPTED").andExpect(status().isOk());
        String prep = body(move(owner, id2, "PREPARING").andExpect(status().isOk()));
        String only = JsonPath.read(prep, "$.order.items[0].itemId");
        send("POST", base() + "/orders/" + id2 + "/items/" + only + "/pick", owner, "{\"action\":\"REPLACE\",\"replacementDishId\":\"" + d3 + "\"}").andExpect(status().isOk());
        String declined = body(send("POST", "/api/v1/food/orders/" + id2 + "/items/" + only + "/decision", customer, "{\"approve\":false}").andExpect(status().isOk()));
        assertThat((String) JsonPath.read(declined, "$.status")).isEqualTo("CANCELLED");
        assertThat((String) JsonPath.read(declined, "$.cancelReason")).isEqualTo("NO_ITEMS_AVAILABLE");
    }

    private String approvedCourier(String phone) throws Exception {
        String login = loginBody(phone);
        db.update("insert into transactions.delivery_couriers (user_id, display_name, vehicle, status, online, max_grams, max_side_cm) values (?, 'Курьер DEV', 'CAR', 'APPROVED', true, 20000, 100)", subject(login));
        return JsonPath.read(login, "$.accessToken");
    }

    @Test
    void groceryDeliveryIsHandedToExactlyOneCourierAndMovesTheOrderToDelivered() throws Exception {
        db.update("update marketplace.food_restaurants set vertical = 'GROCERY' where id = ?", restaurant);
        String dish = db.queryForObject("select id from marketplace.food_dishes d where d.restaurant_id = ? and d.available and d.unit = 'PIECE' "
                + "and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = d.id and g.min_select > 0) order by d.name limit 1", String.class, restaurant);
        String courierA = approvedCourier("+77000000424");
        String courierB = approvedCourier("+77000000425");
        // A courier profile is required.
        send("GET", "/api/v1/executor/food/tasks/open", customer, null).andExpect(status().isForbidden());

        String id = JsonPath.read(placeGrocery("grocery-courier-00001", line(dish, "NONE")), "$.id");
        move(owner, id, "ACCEPTED").andExpect(status().isOk());
        String prep = body(move(owner, id, "PREPARING").andExpect(status().isOk()));
        // The store never drives the courier leg of a grocery delivery.
        assertThat((List<String>) JsonPath.read(prep, "$.allowedNext")).containsExactly("READY_FOR_PICKUP", "CANCELLED");
        send("POST", base() + "/orders/" + id + "/items/" + JsonPath.read(prep, "$.order.items[0].itemId") + "/pick", owner, "{\"action\":\"PICKED\"}").andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/executor/food/tasks/open", courierA, null).andExpect(status().isOk())), "$")).isEmpty();
        String ready = body(move(owner, id, "READY_FOR_PICKUP").andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(ready, "$.allowedNext")).containsExactly("CANCELLED");
        move(owner, id, "ON_THE_WAY").andExpect(status().isConflict());

        // Before acceptance the courier sees the store and the order, not the customer's address.
        String open = body(send("GET", "/api/v1/executor/food/tasks/open", courierA, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(open, "$")).hasSize(1);
        assertThat((Object) JsonPath.read(open, "$[0].deliveryAddress")).isNull();
        String task = JsonPath.read(open, "$[0].id");
        String path = "/api/v1/executor/food/tasks/" + task;
        send("POST", path + "/accept", courierA, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ASSIGNED"))
                .andExpect(jsonPath("$.deliveryAddress").value("Алматы, пр. Абая 10 (тестовый адрес)"));
        send("POST", path + "/accept", courierB, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TASK_UNAVAILABLE"));
        send("POST", path + "/accept", courierA, null).andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/executor/food/tasks/open", courierB, null)), "$")).isEmpty();
        send("POST", path + "/pickup", courierB, null).andExpect(status().isNotFound());
        send("POST", path + "/deliver", courierA, null).andExpect(status().isConflict());
        send("POST", path + "/pickup", courierA, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PICKED_UP"));
        send("POST", path + "/pickup", courierA, null).andExpect(status().isOk());
        String onTheWay = body(send("GET", "/api/v1/food/orders/" + id, customer, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(onTheWay, "$.status")).isEqualTo("ON_THE_WAY");
        send("POST", path + "/deliver", courierA, null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("DELIVERED"));
        send("POST", path + "/deliver", courierA, null).andExpect(status().isOk());
        String done = body(send("GET", "/api/v1/food/orders/" + id, customer, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(done, "$.status")).isEqualTo("DELIVERED");
        assertThat((List<String>) JsonPath.read(done, "$.timeline[*].actor")).contains("COURIER");
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/executor/food/tasks/mine", courierA, null)), "$")).hasSize(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/executor/food/tasks/mine", courierB, null)), "$")).isEmpty();

        // A store that cancels a waiting order closes the task: nobody can take it any more.
        String id2 = JsonPath.read(placeGrocery("grocery-courier-00002", line(dish, "NONE")), "$.id");
        move(owner, id2, "ACCEPTED").andExpect(status().isOk());
        String prep2 = body(move(owner, id2, "PREPARING").andExpect(status().isOk()));
        send("POST", base() + "/orders/" + id2 + "/items/" + JsonPath.read(prep2, "$.order.items[0].itemId") + "/pick", owner, "{\"action\":\"PICKED\"}").andExpect(status().isOk());
        move(owner, id2, "READY_FOR_PICKUP").andExpect(status().isOk());
        String task2 = JsonPath.read(body(send("GET", "/api/v1/executor/food/tasks/open", courierB, null)), "$[0].id");
        send("POST", base() + "/orders/" + id2 + "/status", owner, "{\"status\":\"CANCELLED\",\"reason\":\"Магазин закрылся\"}").andExpect(status().isOk());
        send("POST", "/api/v1/executor/food/tasks/" + task2 + "/accept", courierB, null).andExpect(status().isConflict());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/executor/food/tasks/open", courierB, null)), "$")).isEmpty();
    }

    @Test
    void groceriesControlCenterIsScopedAndReportsRealNumbers() throws Exception {
        String loginBody = loginBody("+77000000426");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'GROCERIES_OPERATIONS', 'synthetic DEV admin')", subject(loginBody));
        String groceryAdmin = JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}")), "$.accessToken");
        String zero = body(send("GET", "/api/v1/admin/groceries/summary", groceryAdmin, null).andExpect(status().isOk()));
        assertThat(((Number) JsonPath.read(zero, "$.orders")).longValue()).isZero();
        assertThat((List<?>) JsonPath.read(zero, "$.categories")).isEmpty();

        // Scoped RBAC: each grant opens only its own center.
        send("GET", "/api/v1/admin/groceries/summary", admin, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/admin/food/summary", groceryAdmin, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/admin/groceries/summary", customer, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/admin/groceries/summary", null, null).andExpect(status().isUnauthorized());

        db.update("update marketplace.food_restaurants set vertical = 'GROCERY' where id = ?", restaurant);
        String dish = db.queryForObject("select id from marketplace.food_dishes d where d.restaurant_id = ? and d.available and d.unit = 'PIECE' "
                + "and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = d.id and g.min_select > 0) order by d.name limit 1", String.class, restaurant);
        db.update("update marketplace.food_dishes set grocery_category = 'dairy', stock_qty = 3 where id = ?::uuid", dish);
        String order = placeGrocery("grocery-admin-000001", line(dish, "NONE"));
        String id = JsonPath.read(order, "$.id");
        long total = ((Number) JsonPath.read(order, "$.totalMinor")).longValue();
        db.update("update transactions.food_order_items set fulfillment_status = 'OK', final_unit_price_minor = unit_price_minor, final_line_total_minor = line_total_minor where order_id = ?::uuid", id);
        db.update("update transactions.food_orders set status = 'DELIVERED', final_total_minor = total_minor where id = ?::uuid", id);

        String summary = body(send("GET", "/api/v1/admin/groceries/summary", groceryAdmin, null).andExpect(status().isOk()));
        assertThat(((Number) JsonPath.read(summary, "$.orders")).longValue()).isEqualTo(1);
        assertThat(((Number) JsonPath.read(summary, "$.deliveredOrders")).longValue()).isEqualTo(1);
        assertThat(((Number) JsonPath.read(summary, "$.revenueMinor")).longValue()).isEqualTo(total);
        assertThat((String) JsonPath.read(summary, "$.categories[0].category")).isEqualTo("dairy");
        assertThat(((Number) JsonPath.read(summary, "$.lowStockProducts")).longValue()).isEqualTo(1);
        assertThat((List<?>) JsonPath.read(summary, "$.perDay")).hasSize(7);
        String problems = body(send("GET", "/api/v1/admin/groceries/catalog/problems", groceryAdmin, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(problems, "$[?(@.id=='" + dish + "')].problem")).containsExactly("LOW_STOCK");

        // Orders carry no personal data; a delivered test-card order can be refunded once (idempotent) and the action is audited.
        String orders = body(send("GET", "/api/v1/admin/groceries/orders", groceryAdmin, null).andExpect(status().isOk()));
        assertThat(orders).doesNotContain("Алматы").doesNotContain("+7700");
        send("POST", "/api/v1/admin/groceries/orders/" + id + "/refund", groceryAdmin, "{\"reason\":\"Тест возврата\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.paymentStatus").value("REFUNDED")).andExpect(jsonPath("$.refundedMinor").value(total));
        send("POST", "/api/v1/admin/groceries/orders/" + id + "/refund", groceryAdmin, "{\"reason\":\"Повтор\"}").andExpect(status().isOk());
        send("POST", "/api/v1/admin/groceries/orders/" + UUID.randomUUID() + "/refund", groceryAdmin, "{\"reason\":\"Нет такого\"}").andExpect(status().isNotFound());

        // Store moderation: block hides the store from the catalog; the change needs a reason and is audited.
        send("POST", "/api/v1/admin/groceries/stores/" + restaurant + "/moderation", groceryAdmin, "{\"decision\":\"BLOCK\",\"reason\":\"x\"}").andExpect(status().isBadRequest());
        send("POST", "/api/v1/admin/groceries/stores/" + restaurant + "/moderation", groceryAdmin, "{\"decision\":\"BLOCK\",\"reason\":\"Проверка качества\"}").andExpect(status().isOk());
        assertThat((List<String>) JsonPath.read(body(send("GET", "/api/v1/admin/groceries/stores", groceryAdmin, null)), "$[*].moderationStatus")).contains("BLOCKED");
        send("POST", "/api/v1/admin/groceries/stores/" + restaurant + "/moderation", groceryAdmin, "{\"decision\":\"BLOCK\",\"reason\":\"Повтор\"}").andExpect(status().isConflict());
        send("POST", "/api/v1/admin/groceries/stores/" + restaurant + "/moderation", groceryAdmin, "{\"decision\":\"UNBLOCK\",\"reason\":\"Проверено\"}").andExpect(status().isOk());
        assertThat((List<String>) JsonPath.read(body(send("GET", "/api/v1/admin/groceries/audit", groceryAdmin, null)), "$[*].action"))
                .contains("ORDER_REFUNDED", "STORE_BLOCK", "STORE_UNBLOCK");
        // Food restaurants are outside the scope: a Food store id is not found for the Groceries center.
        String foodStore = db.queryForObject("select id::text from marketplace.food_restaurants where vertical = 'FOOD' limit 1", String.class);
        send("POST", "/api/v1/admin/groceries/stores/" + foodStore + "/moderation", groceryAdmin, "{\"decision\":\"BLOCK\",\"reason\":\"Не моё\"}").andExpect(status().isNotFound());
    }
}
