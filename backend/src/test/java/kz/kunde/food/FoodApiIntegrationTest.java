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
        for (String file : new String[] {"food/demo-catalog.json", "food/grocery-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) {
                new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in));
            }
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

    @Test
    void groceryStoresShareTheCatalogCartAndOrdersButStayASeparateVertical() throws Exception {
        String stores = body(send("GET", "/api/v1/food/restaurants?vertical=GROCERY", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(stores, "$")).hasSize(4);
        assertThat((String) JsonPath.read(stores, "$[0].vertical")).isEqualTo("GROCERY");
        // The default vertical is FOOD and never lists stores; an unknown vertical is a client error.
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/restaurants", null, null, null)), "$")).hasSize(8);
        send("GET", "/api/v1/food/restaurants?vertical=TAXI", null, null, null).andExpect(status().isBadRequest());
        String found = body(send("GET", "/api/v1/food/search?q=гауда&vertical=GROCERY", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(found, "$.dishes")).isNotEmpty();
        assertThat((List<?>) JsonPath.read(body(send("GET", "/api/v1/food/search?q=гауда", null, null, null)), "$.dishes")).isEmpty();

        String token = login("+77000000201");
        String address = address(token);
        String store = restaurantId("market-alatau");
        String milk = dishId("market-alatau", "Молоко 1 л");
        String fat = "\"" + optionId(milk, "2,5%") + "\"";
        // 3 x 620 KZT = 1860 is below the 4000 minimum; 8 x 620 = 4960 passes. Delivery 600.
        send("POST", "/api/v1/food/cart/quote", token, order(store, milk, fat, 3, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_MIN_ORDER_NOT_MET"));
        String created = body(send("POST", "/api/v1/food/orders", token, order(store, milk, fat, 8, address, "CASH_ON_DELIVERY"),
                "order-key-0000000020").andExpect(status().isCreated()).andExpect(jsonPath("$.vertical").value("GROCERY")));
        assertThat((Integer) JsonPath.read(created, "$.totalMinor")).isEqualTo(496_000 + 60_000);
        send("GET", "/api/v1/food/orders", token, null, null).andExpect(jsonPath("$[0].vertical").value("GROCERY"));
        // An unavailable product cannot be ordered.
        send("POST", "/api/v1/food/cart/quote", token, order(store, dishId("market-alatau", "Масло подсолнечное 1 л"), "", 5, address, "TEST_CARD"), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_ITEM_UNAVAILABLE"));
    }

    private String line(String dish, int quantity, String policy, String substitutes) {
        return "{\"dishId\":\"" + dish + "\",\"quantity\":" + quantity + ",\"optionIds\":[],\"substitution\":\"" + policy
                + "\",\"substituteDishIds\":[" + substitutes + "]}";
    }

    private String cart(String store, String address, String payment, String... lines) {
        return "{\"restaurantId\":\"" + store + "\",\"items\":[" + String.join(",", lines) + "],\"addressId\":\"" + address
                + "\",\"paymentMethod\":\"" + payment + "\"}";
    }

    private int stock(String store, String name) {
        return db.queryForObject("select d.stock_qty from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.slug = ? and d.name = ?", Integer.class, store, name);
    }

    @Test
    void weighedGoodsArePricedPerKilogramInGramsAndStockIsReservedAndReturned() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String farm = restaurantId("fermer-svezhest");
        String beef = dishId("fermer-svezhest", "Говядина вырезка");
        String catalog = body(send("GET", "/api/v1/food/restaurants/" + farm, null, null, null).andExpect(status().isOk()));
        List<?> beefDish = JsonPath.read(catalog, "$.sections[*].dishes[?(@.name=='Говядина вырезка')]");
        assertThat(((java.util.Map<?, ?>) beefDish.get(0)).get("unit")).isEqualTo("KG");
        assertThat(((java.util.Map<?, ?>) beefDish.get(0)).get("maxQuantity")).isEqualTo(3000);

        // 1.5 kg at 5990 KZT/kg = 8985 KZT.
        String quote = body(send("POST", "/api/v1/food/cart/quote", token, cart(farm, address, "TEST_CARD", line(beef, 1500, "NONE", "")), null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.lines[0].unit").value("KG")));
        assertThat((Integer) JsonPath.read(quote, "$.subtotalMinor")).isEqualTo(898_500);
        for (int bad : new int[] {50, 150, 6000}) {
            send("POST", "/api/v1/food/cart/quote", token, cart(farm, address, "TEST_CARD", line(beef, bad, "NONE", "")), null)
                    .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_QUANTITY_INVALID"));
        }
        send("POST", "/api/v1/food/cart/quote", token, cart(farm, address, "TEST_CARD", line(beef, 3100, "NONE", "")), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_STOCK_INSUFFICIENT"));

        String created = body(send("POST", "/api/v1/food/orders", token, cart(farm, address, "TEST_CARD", line(beef, 2000, "NONE", "")),
                "order-key-0000000030").andExpect(status().isCreated()));
        assertThat((Integer) JsonPath.read(created, "$.items[0].lineTotalMinor")).isEqualTo(1_198_000);
        assertThat(stock("fermer-svezhest", "Говядина вырезка")).isEqualTo(1000);
        send("POST", "/api/v1/food/cart/quote", token, cart(farm, address, "TEST_CARD", line(beef, 1100, "NONE", "")), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_STOCK_INSUFFICIENT"));
        send("POST", "/api/v1/food/orders/" + JsonPath.read(created, "$.id") + "/cancel", token, null, null).andExpect(status().isOk());
        assertThat(stock("fermer-svezhest", "Говядина вырезка")).isEqualTo(3000);
    }

    @Test
    void pieceStockLimitsTheCartAndTheLastUnitsCannotBeOrderedTwice() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String store = restaurantId("market-alatau");
        String cheese = dishId("market-alatau", "Сыр Гауда 200 г");
        send("POST", "/api/v1/food/cart/quote", token, cart(store, address, "TEST_CARD", line(cheese, 5, "NONE", "")), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_STOCK_INSUFFICIENT"));
        send("POST", "/api/v1/food/orders", token, cart(store, address, "TEST_CARD", line(cheese, 4, "NONE", "")),
                "order-key-0000000031").andExpect(status().isCreated());
        assertThat(stock("market-alatau", "Сыр Гауда 200 г")).isZero();
        send("POST", "/api/v1/food/orders", token, cart(store, address, "TEST_CARD", line(cheese, 1, "NONE", "")),
                "order-key-0000000032").andExpect(status().isUnprocessableEntity());
    }

    @Test
    void substitutionNeedsConsentAndOnlyAcceptsSameStoreAndUnit() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String store = restaurantId("market-alatau");
        String kefir = dishId("market-alatau", "Кефир 0,9 л");
        String milk = dishId("market-alatau", "Молоко 1 л");
        String alternatives = body(send("GET", "/api/v1/food/dishes/" + kefir + "/alternatives", null, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(alternatives, "$[?(@.id=='" + kefir + "')]")).isEmpty();
        assertThat((List<?>) JsonPath.read(alternatives, "$[?(@.name=='Молоко 1 л')]")).hasSize(1);
        assertThat((List<?>) JsonPath.read(alternatives, "$[?(@.name=='Масло подсолнечное 1 л')]")).isEmpty(); // unavailable

        send("POST", "/api/v1/food/cart/quote", token, cart(store, address, "TEST_CARD", line(kefir, 8, "CHOSEN", "")), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_SUBSTITUTION_INVALID"));
        String foreign = dishId("burger-tau", "Классик");
        send("POST", "/api/v1/food/cart/quote", token, cart(store, address, "TEST_CARD", line(kefir, 8, "CHOSEN", "\"" + foreign + "\"")), null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_SUBSTITUTION_INVALID"));
        send("POST", "/api/v1/food/cart/quote", token, cart(store, address, "TEST_CARD", line(kefir, 8, "SWAP", "")), null)
                .andExpect(status().isBadRequest());
        send("POST", "/api/v1/food/cart/quote", token, cart(store, address, "TEST_CARD", line(kefir, 8, "CHOSEN", "\"" + milk + "\"")), null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.lines[0].substitution").value("CHOSEN"));
    }

    @Test
    void unavailableProductsAreReplacedOnlyWithConsentAndRemovedOtherwise() throws Exception {
        String token = login("+77000000201");
        String address = address(token);
        String store = restaurantId("market-alatau");
        String kefir = dishId("market-alatau", "Кефир 0,9 л");
        String milk = dishId("market-alatau", "Молоко 1 л");
        String bread = dishId("market-alatau", "Хлеб белый");
        // Kefir x8 with the customer's chosen replacement, plus bread x20 that stays available.
        String chosen = body(send("POST", "/api/v1/food/orders", token, cart(store, address, "TEST_CARD",
                line(kefir, 8, "CHOSEN", "\"" + milk + "\""), line(bread, 20, "NONE", "")), "order-key-0000000033")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.hasChanges").value(false)));
        String chosenId = JsonPath.read(chosen, "$.id");
        String declined = body(send("POST", "/api/v1/food/orders", token, cart(store, address, "CASH_ON_DELIVERY",
                line(kefir, 8, "NONE", ""), line(bread, 20, "NONE", "")), "order-key-0000000034").andExpect(status().isCreated()));
        String declinedId = JsonPath.read(declined, "$.id");

        db.update("update marketplace.food_dishes set available = false where id = ?::uuid", kefir);
        db.update("update transactions.food_orders set placed_at = now() - interval '60 seconds' where id in (?::uuid, ?::uuid)", chosenId, declinedId);

        // Replacement was agreed: milk costs more per unit (620 vs 540), so the customer is charged the original price.
        String replaced = body(send("GET", "/api/v1/food/orders/" + chosenId, token, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.hasChanges").value(true)).andExpect(jsonPath("$.status").value("PREPARING")));
        assertThat((String) JsonPath.read(replaced, "$.items[0].fulfillmentStatus")).isEqualTo("SUBSTITUTED");
        assertThat((String) JsonPath.read(replaced, "$.items[0].replacedByName")).isEqualTo("Молоко 1 л");
        assertThat((Integer) JsonPath.read(replaced, "$.items[0].finalLineTotalMinor")).isEqualTo(8 * 54_000);
        assertThat((String) JsonPath.read(replaced, "$.items[1].fulfillmentStatus")).isEqualTo("OK");
        assertThat((Integer) JsonPath.read(replaced, "$.finalTotalMinor")).isEqualTo((Integer) JsonPath.read(replaced, "$.totalMinor"));

        // No consent: the line is removed, never swapped, and the total shrinks.
        String removed = body(send("GET", "/api/v1/food/orders/" + declinedId, token, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(removed, "$.items[0].fulfillmentStatus")).isEqualTo("REMOVED");
        assertThat((String) JsonPath.read(removed, "$.items[0].replacedByName")).isNull();
        assertThat((Boolean) JsonPath.read(removed, "$.hasChanges")).isTrue();
        assertThat((Integer) JsonPath.read(removed, "$.finalTotalMinor")).isEqualTo(520_000 + 60_000);

        // A product that is unavailable now cannot be ordered at all.
        send("POST", "/api/v1/food/orders", token, cart(store, address, "TEST_CARD", line(kefir, 8, "NONE", "")), "order-key-0000000035")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FOOD_ITEM_UNAVAILABLE"));
    }
}
