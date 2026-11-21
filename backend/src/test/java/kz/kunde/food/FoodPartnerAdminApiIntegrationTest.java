package kz.kunde.food;

import static org.assertj.core.api.Assertions.assertThat;
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000421,+77000000422,+77000000423",
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
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000421','+77000000422','+77000000423')");
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
}
