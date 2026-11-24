package kz.kunde.food;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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

/**
 * Food 2.0 over HTTP against PostgreSQL: pickup, server-side promo codes (limits, release on cancel), favorites persisted in
 * PostgreSQL, verified reviews with a computed average, catalog filters/sorting and the Admin Food permission gate.
 * Synthetic numbers only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.food.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000211,+77000000212",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FoodEngagementApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000211', '+77000000212')");
        FoodDemoSeeder seeder = new FoodDemoSeeder(db);
        try (var in = new ClassPathResource("food/demo-catalog.json").getInputStream()) {
            seeder.seed(new ObjectMapper().readTree(in));
        }
        seeder.seedPromotions();
        db.update("update marketplace.food_restaurants set min_order_minor = 0 where slug = 'pizza-alatau'");
    }

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
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

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        return send(method, path, token, json, null);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return JsonPath.read(body(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk())), "$.accessToken");
    }

    private String address(String token) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/me/addresses", token,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}", null)
                .andExpect(status().isCreated())), "$.id");
    }

    private String restaurantId(String slug) {
        return db.queryForObject("select id from marketplace.food_restaurants where slug = ?", String.class, slug);
    }

    private String firstDish(String slug) {
        return db.queryForObject("select d.id from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.slug = ? and d.available and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = d.id and g.min_select > 0) "
                + "order by d.price_minor desc limit 1", String.class, slug);
    }

    private String cart(String restaurant, String dish, int qty, String address, String payment, String type, String promo, Long expected) {
        return "{\"restaurantId\":\"" + restaurant + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":" + qty + ",\"optionIds\":[]}]"
                + (address == null ? "" : ",\"addressId\":\"" + address + "\"") + ",\"paymentMethod\":\"" + payment + "\""
                + (type == null ? "" : ",\"fulfillmentType\":\"" + type + "\"") + (promo == null ? "" : ",\"promoCode\":\"" + promo + "\"")
                + (expected == null ? "" : ",\"expectedTotalMinor\":" + expected) + "}";
    }

    @Test
    void pickupOrderNeedsNoAddressHasNoFeeAndFollowsThePickupFlow() throws Exception {
        String token = login("+77000000211");
        String restaurant = restaurantId("pizza-alatau");
        String dish = firstDish("pizza-alatau");
        String created = body(send("POST", "/api/v1/food/orders", token, cart(restaurant, dish, 1, null, "CASH_ON_DELIVERY", "PICKUP", null, null),
                "pickup-key-00000000001").andExpect(status().isCreated()).andExpect(jsonPath("$.fulfillmentType").value("PICKUP"))
                .andExpect(jsonPath("$.deliveryFeeMinor").value(0)).andExpect(jsonPath("$.addressLabel").value("Самовывоз")));
        String id = JsonPath.read(created, "$.id");
        // Simulated pickup: after the delivery window the order is handed over without ever being ON_THE_WAY.
        db.update("update transactions.food_orders set placed_at = now() - interval '1 hour' where id = ?::uuid", id);
        String done = body(send("GET", "/api/v1/food/orders/" + id, token, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(done, "$.status")).isEqualTo("DELIVERED");
        List<String> statuses = JsonPath.read(done, "$.timeline[*].status");
        assertThat(statuses).contains("READY_FOR_PICKUP").doesNotContain("ON_THE_WAY");
        // Delivery without an address is still refused.
        send("POST", "/api/v1/food/orders", token, cart(restaurant, dish, 1, null, "CASH_ON_DELIVERY", null, null, null),
                "pickup-key-00000000002").andExpect(status().isUnprocessableEntity());
        // A restaurant that does not offer pickup refuses it.
        db.update("update marketplace.food_restaurants set pickup_enabled = false where id = ?::uuid", restaurant);
        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 1, null, "CASH_ON_DELIVERY", "PICKUP", null, null))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PICKUP_UNAVAILABLE"));
    }

    @Test
    void promoDiscountIsComputedOnTheServerAndLimitsAreEnforced() throws Exception {
        String token = login("+77000000211");
        String address = address(token);
        String restaurant = restaurantId("pizza-alatau");
        String dish = firstDish("pizza-alatau");
        String quote = body(send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "welcome10", null))
                .andExpect(status().isOk()));
        int subtotal = JsonPath.read(quote, "$.subtotalMinor");
        int fee = JsonPath.read(quote, "$.deliveryFeeMinor");
        assertThat((Integer) JsonPath.read(quote, "$.discountMinor")).isEqualTo(subtotal / 10);
        assertThat((Integer) JsonPath.read(quote, "$.totalMinor")).isEqualTo(subtotal + fee - subtotal / 10);
        assertThat((String) JsonPath.read(quote, "$.promoCode")).isEqualTo("WELCOME10");

        // The client cannot claim a different total: a stale expectedTotalMinor is a price change.
        send("POST", "/api/v1/food/orders", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "WELCOME10", 1L), "promo-key-0000000001")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("FOOD_PRICE_CHANGED"));

        String order = body(send("POST", "/api/v1/food/orders", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "WELCOME10",
                (long) (subtotal + fee - subtotal / 10)), "promo-key-0000000002").andExpect(status().isCreated())
                .andExpect(jsonPath("$.discountMinor").value(subtotal / 10)));
        String orderId = JsonPath.read(order, "$.id");
        // per-user limit 1: the same user cannot reuse the code
        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "WELCOME10", null))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PROMO_ALREADY_USED"));
        // Cancelling releases the redemption.
        send("POST", "/api/v1/food/orders/" + orderId + "/cancel", token, null, null).andExpect(status().isOk());
        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "WELCOME10", null)).andExpect(status().isOk());

        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "NOPE", null))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PROMO_NOT_FOUND"));
        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "FIX500", null)).andExpect(status().isOk());
        db.update("update marketplace.food_promotions set ends_at = now() - interval '1 minute', starts_at = now() - interval '1 day' where code = 'FIX500'");
        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "FIX500", null))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PROMO_EXPIRED"));
        // Disabled promotions look missing.
        db.update("update marketplace.food_promotions set status = 'DISABLED' where code = 'WELCOME10'");
        send("POST", "/api/v1/food/cart/quote", token, cart(restaurant, dish, 2, address, "TEST_CARD", null, "WELCOME10", null))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("PROMO_NOT_FOUND"));
        String active = body(send("GET", "/api/v1/food/promotions", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(active, "$[?(@.code=='WELCOME10')]")).isEmpty();
    }

    @Test
    void favoritesPersistPerUser() throws Exception {
        String a = login("+77000000211");
        String b = login("+77000000212");
        String restaurant = restaurantId("pizza-alatau");
        send("GET", "/api/v1/food/favorites", null, null, null).andExpect(status().isUnauthorized());
        send("PUT", "/api/v1/food/favorites/" + restaurant, a, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.favorite").value(true));
        send("PUT", "/api/v1/food/favorites/" + restaurant, a, null, null).andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/favorites", a, null, null).andExpect(status().isOk())), "$")).hasSize(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/favorites", b, null, null).andExpect(status().isOk())), "$")).isEmpty();
        send("PUT", "/api/v1/food/favorites/" + java.util.UUID.randomUUID(), a, null, null).andExpect(status().isNotFound());
        send("DELETE", "/api/v1/food/favorites/" + restaurant, a, null, null).andExpect(status().isOk()).andExpect(jsonPath("$.favorite").value(false));
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/favorites", a, null, null)), "$")).isEmpty();
    }

    @Test
    void reviewsNeedADeliveredOrderAndFeedTheAverageRating() throws Exception {
        String a = login("+77000000211");
        String b = login("+77000000212");
        String restaurant = restaurantId("pizza-alatau");
        String dish = firstDish("pizza-alatau");
        String addrA = address(a);
        String orderA = JsonPath.read(body(send("POST", "/api/v1/food/orders", a, cart(restaurant, dish, 1, addrA, "CASH_ON_DELIVERY", null, null, null),
                "review-key-0000000001").andExpect(status().isCreated())), "$.id");
        send("POST", "/api/v1/food/orders/" + orderA + "/review", a, "{\"rating\":5}", null).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("REVIEW_NOT_ALLOWED"));
        db.update("update transactions.food_orders set status = 'DELIVERED' where id = ?::uuid", orderA);
        send("POST", "/api/v1/food/orders/" + orderA + "/review", b, "{\"rating\":5}", null).andExpect(status().isNotFound());
        send("POST", "/api/v1/food/orders/" + orderA + "/review", a, "{\"rating\":6}", null).andExpect(status().isBadRequest());
        String review = body(send("POST", "/api/v1/food/orders/" + orderA + "/review", a, "{\"rating\":4,\"comment\":\"Вкусно, но долго\"}", null)
                .andExpect(status().isCreated()));
        send("POST", "/api/v1/food/orders/" + orderA + "/review", a, "{\"rating\":1}", null).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("REVIEW_EXISTS"));
        String summary = body(send("GET", "/api/v1/food/restaurants/" + restaurant + "/reviews", null, null, null).andExpect(status().isOk()));
        assertThat((Double) JsonPath.read(summary, "$.average")).isEqualTo(4.0);
        assertThat((Integer) JsonPath.read(summary, "$.count")).isEqualTo(1);
        String list = body(send("GET", "/api/v1/food/restaurants", null, null, null).andExpect(status().isOk()));
        assertThat((List<Double>) JsonPath.read(list, "$[?(@.id=='" + restaurant + "')].ratingAvg")).containsExactly(4.0);
        // a hidden review no longer counts
        db.update("update marketplace.food_reviews set status = 'HIDDEN' where id = ?::uuid", (String) JsonPath.read(review, "$.id"));
        assertThat((Integer) JsonPath.read(body(send("GET", "/api/v1/food/restaurants/" + restaurant + "/reviews", null, null, null)), "$.count")).isZero();
        // complaints are idempotent per reporter
        db.update("update marketplace.food_reviews set status = 'VISIBLE' where order_id = ?::uuid", orderA);
        String reviewId = JsonPath.read(review, "$.id");
        send("POST", "/api/v1/food/reviews/" + reviewId + "/complaints", b, "{\"reason\":\"Неуместный отзыв\"}", null).andExpect(status().isAccepted());
        send("POST", "/api/v1/food/reviews/" + reviewId + "/complaints", b, "{\"reason\":\"Неуместный отзыв\"}", null).andExpect(status().isAccepted());
        assertThat(db.queryForObject("select count(*) from marketplace.food_review_complaints", Integer.class)).isEqualTo(1);
    }

    @Test
    void catalogFiltersAndSortingAreServerSide() throws Exception {
        String all = body(send("GET", "/api/v1/food/restaurants", null, null, null).andExpect(status().isOk()));
        int total = ((List<?>) JsonPath.read(all, "$")).size();
        db.update("update marketplace.food_restaurants set delivery_fee_minor = 0 where slug = 'pizza-alatau'");
        String free = body(send("GET", "/api/v1/food/restaurants?freeDelivery=true", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(free, "$")).isNotEmpty().hasSizeLessThan(total + 1);
        assertThat((List<Integer>) JsonPath.read(free, "$[*].deliveryFeeMinor")).containsOnly(0);
        String promo = body(send("GET", "/api/v1/food/restaurants?promo=true", null, null, null).andExpect(status().isOk()));
        assertThat((List<Boolean>) JsonPath.read(promo, "$[*].hasPromo")).containsOnly(true);
        String sorted = body(send("GET", "/api/v1/food/restaurants?sort=delivery_fee", null, null, null).andExpect(status().isOk()));
        List<Integer> fees = JsonPath.read(sorted, "$[?(@.open==true)].deliveryFeeMinor");
        assertThat(fees).isSorted();
        send("GET", "/api/v1/food/restaurants?sort=distance", null, null, null).andExpect(status().isBadRequest());
        String categories = body(send("GET", "/api/v1/food/categories", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(categories, "$")).isNotEmpty();
        // a blocked restaurant behaves as closed
        db.update("update marketplace.food_restaurants set moderation_status = 'BLOCKED' where slug = 'pizza-alatau'");
        String openOnly = body(send("GET", "/api/v1/food/restaurants?openNow=true", null, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(openOnly, "$[*].slug")).doesNotContain("pizza-alatau");
    }

    @Test
    void adminFoodRequiresTheFoodOperationsGrant() throws Exception {
        String token = login("+77000000211");
        send("GET", "/api/v1/admin/food/summary", token, null, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/admin/food/summary", null, null, null).andExpect(status().isUnauthorized());
    }
}
