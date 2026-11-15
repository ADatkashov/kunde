package kz.kunde.food;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
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
 * KUNDE Food over HTTP against PostgreSQL: public catalog, server-side pricing, idempotent checkout, persistence,
 * order history, mock fulfillment progress, cancellation rules and ownership isolation. Synthetic numbers and the
 * synthetic demo catalog only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.food.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000201,+77000000202",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FoodApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000201', '+77000000202')");
        try (var in = new ClassPathResource("food/demo-catalog.json").getInputStream()) {
            new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in));
        }
    }

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = (method.equals("GET") ? get(path) : post(path)).contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (key != null) { request.header("Idempotency-Key", key); }
        return http.perform(request);
    }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return JsonPath.read(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(), "$.accessToken");
    }

    private String address(String token) throws Exception {
        return JsonPath.read(send("POST", "/api/v1/me/addresses", token,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}", null)
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id");
    }

    private String body(ResultActions result) throws Exception { return result.andReturn().getResponse().getContentAsString(); }

    private String restaurantId(String slug) {
        return db.queryForObject("select id from marketplace.food_restaurants where slug = ?", String.class, slug);
    }

    private String dishId(String restaurant, String name) {
        return db.queryForObject("select d.id from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.slug = ? and d.name = ?", String.class, restaurant, name);
    }

    private String optionId(String dish, String name) {
        return db.queryForObject("select o.id from marketplace.food_options o join marketplace.food_option_groups g on g.id = o.group_id "
                + "where g.dish_id = ?::uuid and o.name = ?", String.class, dish, name);
    }

    private String order(String restaurant, String dish, String options, int qty, String address, String payment) {
        return "{\"restaurantId\":\"" + restaurant + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":" + qty
                + ",\"optionIds\":[" + options + "]}],\"addressId\":\"" + address + "\",\"paymentMethod\":\"" + payment
                + "\",\"comment\":\"Позвонить за 5 минут\"}";
    }

    @Test
    void catalogIsPublicAndComplete() throws Exception {
        String list = body(send("GET", "/api/v1/food/restaurants", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(list, "$")).hasSize(8);
        assertThat((Boolean) JsonPath.read(list, "$[0].synthetic")).isTrue();
        String detail = body(send("GET", "/api/v1/food/restaurants/" + restaurantId("pizza-alatau"), null, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.restaurant.name").value("Пицца Алатау")));
        assertThat((List<?>) JsonPath.read(detail, "$.sections")).isNotEmpty();
        assertThat((List<?>) JsonPath.read(detail, "$.sections[0].dishes[0].optionGroups")).isNotEmpty();
        send("GET", "/api/v1/food/restaurants/" + UUID.randomUUID(), null, null, null).andExpect(status().isNotFound());
        String found = body(send("GET", "/api/v1/food/search?q=пицц", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(found, "$.restaurants")).isNotEmpty();
        String dishes = body(send("GET", "/api/v1/food/search?q=маргарит", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(dishes, "$.dishes")).isNotEmpty();
        send("GET", "/api/v1/capabilities", null, null, null).andExpect(jsonPath("$.marketplaceEnabled").value(true));
    }

    @Test
    void ordersRequireAuthentication() throws Exception {
        send("GET", "/api/v1/food/orders", null, null, null).andExpect(status().isUnauthorized());
        send("POST", "/api/v1/food/orders", null, "{}", "abcdefghijklmnop").andExpect(status().isUnauthorized());
        send("POST", "/api/v1/food/cart/quote", null, "{}", null).andExpect(status().isUnauthorized());
    }

    @Test
    void checkoutPersistsAnIdempotentOrderWithServerSidePrices() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String restaurant = restaurantId("pizza-alatau");
        String dish = dishId("pizza-alatau", "Маргарита");
        String options = "\"" + optionId(dish, "30 см") + "\",\"" + optionId(dish, "Двойной сыр") + "\"";

        // 3500 + 1500 (30 cm) + 800 (double cheese) = 5800 KZT per pizza, x2, plus 600 delivery.
        String quote = body(send("POST", "/api/v1/food/cart/quote", token, order(restaurant, dish, options, 2, address, "TEST_CARD"), null)
                .andExpect(status().isOk()));
        assertThat((Integer) JsonPath.read(quote, "$.subtotalMinor")).isEqualTo(1_160_000);
        assertThat((Integer) JsonPath.read(quote, "$.totalMinor")).isEqualTo(1_220_000);

        String key = "order-key-0000000001";
        String created = body(send("POST", "/api/v1/food/orders", token, order(restaurant, dish, options, 2, address, "TEST_CARD"), key)
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("PLACED"))
                .andExpect(jsonPath("$.paymentStatus").value("TEST_PAID")).andExpect(jsonPath("$.cancellable").value(true))
                .andExpect(jsonPath("$.simulated").value(true)));
        String id = JsonPath.read(created, "$.id");
        assertThat((Integer) JsonPath.read(created, "$.totalMinor")).isEqualTo(1_220_000);
        assertThat((String) JsonPath.read(created, "$.items[0].optionsText")).contains("30 см").contains("Двойной сыр");
        assertThat((String) JsonPath.read(created, "$.addressText")).contains("Абая");

        // Replay with the same key returns the same order and creates no second one.
        send("POST", "/api/v1/food/orders", token, order(restaurant, dish, options, 2, address, "TEST_CARD"), key)
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        assertThat(db.queryForObject("select count(*) from transactions.food_orders where id = ?::uuid", Integer.class, id)).isEqualTo(1);
        assertThat(db.queryForObject("select count(*) from transactions.food_order_items where order_id = ?::uuid", Integer.class, id)).isEqualTo(1);
        // Same key for another restaurant is refused.
        send("POST", "/api/v1/food/orders", token, order(restaurantId("burger-tau"), dishId("burger-tau", "Классик"),
                "\"" + optionId(dishId("burger-tau", "Классик"), "Medium") + "\"", 1, address, "TEST_CARD"), key)
                .andExpect(status().isConflict());

        send("GET", "/api/v1/food/orders", token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(id)).andExpect(jsonPath("$[0].items[0].name").value("Маргарита"));
        send("GET", "/api/v1/food/orders/" + id, token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.timeline[0].status").value("PLACED"));
    }

    @Test
    void mockFulfillmentAdvancesAndCancellationIsOnlyFreeBeforeAcceptance() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String restaurant = restaurantId("shaurma-express");
        String dish = dishId("shaurma-express", "Шаурма с сыром");
        String created = body(send("POST", "/api/v1/food/orders", token, order(restaurant, dish, "", 2, address, "CASH_ON_DELIVERY"),
                "order-key-0000000002").andExpect(status().isCreated()).andExpect(jsonPath("$.paymentStatus").value("PAY_ON_RECEIPT")));
        String id = JsonPath.read(created, "$.id");

        db.update("update transactions.food_orders set placed_at = now() - interval '60 seconds' where id = ?::uuid", id);
        send("GET", "/api/v1/food/orders/" + id, token, null, null).andExpect(jsonPath("$.status").value("PREPARING"))
                .andExpect(jsonPath("$.cancellable").value(false))
                .andExpect(jsonPath("$.timeline.length()").value(3));
        send("POST", "/api/v1/food/orders/" + id + "/cancel", token, null, null).andExpect(status().isConflict());

        db.update("update transactions.food_orders set placed_at = now() - interval '10 minutes' where id = ?::uuid", id);
        send("GET", "/api/v1/food/orders", token, null, null).andExpect(jsonPath("$[0].status").value("DELIVERED"))
                .andExpect(jsonPath("$[0].timeline.length()").value(5));

        String fresh = body(send("POST", "/api/v1/food/orders", token, order(restaurant, dish, "", 1, address, "TEST_CARD"),
                "order-key-0000000003").andExpect(status().isCreated()));
        send("POST", "/api/v1/food/orders/" + JsonPath.read(fresh, "$.id") + "/cancel", token, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.paymentStatus").value("VOIDED"));
    }

    @Test
    void repeatReturnsTheStillOrderableItems() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String restaurant = restaurantId("burger-tau");
        String dish = dishId("burger-tau", "Классик");
        String options = "\"" + optionId(dish, "Medium") + "\"";
        String created = body(send("POST", "/api/v1/food/orders", token, order(restaurant, dish, options, 3, address, "TEST_CARD"),
                "order-key-0000000004").andExpect(status().isCreated()));
        String id = JsonPath.read(created, "$.id");
        send("GET", "/api/v1/food/orders/" + id + "/repeat", token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].dishId").value(dish)).andExpect(jsonPath("$.items[0].quantity").value(3))
                .andExpect(jsonPath("$.skipped.length()").value(0));
        db.update("update marketplace.food_dishes set available = false where id = ?::uuid", dish);
        send("GET", "/api/v1/food/orders/" + id + "/repeat", token, null, null)
                .andExpect(jsonPath("$.items.length()").value(0)).andExpect(jsonPath("$.skipped[0]").value("Классик"));
    }

    @Test
    void invalidRequestsAndForeignDataAreRefused() throws Exception {
        String token = login("+77000000201");
        String other = login("+77000000202");
        String address = address(token);
        String otherAddress = address(other);
        String restaurant = restaurantId("pizza-alatau");
        String dish = dishId("pizza-alatau", "Маргарита");
        String size = "\"" + optionId(dish, "25 см") + "\"";

        send("POST", "/api/v1/food/orders", token, order(restaurant, dish, size, 1, address, "TEST_CARD"), null)
                .andExpect(status().isBadRequest());
        send("POST", "/api/v1/food/orders", token, order(restaurant, dish, size, 1, address, "BITCOIN"), "order-key-0000000010")
                .andExpect(status().isUnprocessableEntity());
        send("POST", "/api/v1/food/orders", token, order(restaurant, dish, size, 1, otherAddress, "TEST_CARD"), "order-key-0000000011")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("ADDRESS_NOT_FOUND"));
        // A required option group (size) is missing.
        send("POST", "/api/v1/food/cart/quote", token, order(restaurant, dish, "", 1, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_OPTIONS_INVALID"));
        // An option of another dish is rejected.
        String foreign = "\"" + optionId(dishId("pizza-alatau", "Пепперони"), "25 см") + "\"";
        send("POST", "/api/v1/food/cart/quote", token, order(restaurant, dish, foreign, 1, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity());
        // Unavailable dish.
        send("POST", "/api/v1/food/cart/quote", token, order(restaurant, dishId("pizza-alatau", "Гавайская"),
                "\"" + optionId(dishId("pizza-alatau", "Гавайская"), "25 см") + "\"", 1, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_ITEM_UNAVAILABLE"));
        // Dish of another restaurant.
        send("POST", "/api/v1/food/cart/quote", token, order(restaurantId("burger-tau"), dish, size, 1, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity());
        // Quantity limits and minimum order.
        send("POST", "/api/v1/food/cart/quote", token, order(restaurant, dish, size, 0, address, "TEST_CARD"), null)
                .andExpect(status().isBadRequest());
        send("POST", "/api/v1/food/cart/quote", token, order(restaurantId("sushi-ki"), dishId("sushi-ki", "Соевый соус"), "", 1, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_MIN_ORDER_NOT_MET"));
        db.update("update marketplace.food_restaurants set is_open = false where slug = 'pizza-alatau'");
        send("POST", "/api/v1/food/cart/quote", token, order(restaurant, dish, size, 1, address, "TEST_CARD"), null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("RESTAURANT_CLOSED"));
        db.update("update marketplace.food_restaurants set is_open = true where slug = 'pizza-alatau'");

        // Ownership isolation: another user cannot read, cancel or repeat the order and does not see it in history.
        String created = body(send("POST", "/api/v1/food/orders", token, order(restaurant, dish, size, 2, address, "TEST_CARD"),
                "order-key-0000000012").andExpect(status().isCreated()));
        String id = JsonPath.read(created, "$.id");
        send("GET", "/api/v1/food/orders/" + id, other, null, null).andExpect(status().isNotFound());
        send("POST", "/api/v1/food/orders/" + id + "/cancel", other, null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/food/orders/" + id + "/repeat", other, null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/food/orders", other, null, null).andExpect(jsonPath("$.length()").value(0));
        // Same idempotency key from another user is independent.
        send("POST", "/api/v1/food/orders", other, order(restaurant, dish, size, 2, otherAddress, "TEST_CARD"), "order-key-0000000012")
                .andExpect(status().isCreated());
    }
}
