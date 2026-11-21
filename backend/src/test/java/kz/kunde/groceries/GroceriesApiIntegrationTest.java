package kz.kunde.groceries;

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
import java.util.UUID;
import kz.kunde.food.FoodDemoSeeder;
import kz.kunde.platform.FeatureToggles;
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
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;

/**
 * KUNDE Groceries 1.0 over HTTP against PostgreSQL: categories, server-side search/filters/sorting, product page,
 * favorites, shopping lists, the server cart, ownership isolation, the GROCERIES switch and the hand-off to the shared
 * Food order engine. Synthetic numbers and the synthetic demo catalog only; the whole test rolls back.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.food.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000301,+77000000302",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class GroceriesApiIntegrationTest {
    private static final String API = "/api/v1/groceries";
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired FeatureToggles toggles;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000301', '+77000000302')");
        for (String file : new String[] {"food/demo-catalog.json", "food/grocery-demo-catalog.json", "food/groceries-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) {
                new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in));
            }
        }
        toggles.invalidate();
    }

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        MockHttpServletRequestBuilder request = switch (method) {
            case "GET" -> get(path);
            case "PUT" -> put(path);
            case "DELETE" -> delete(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }

    private String body(ResultActions result) throws Exception { return result.andReturn().getResponse().getContentAsString(); }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return JsonPath.read(body(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}").andExpect(status().isOk())), "$.accessToken");
    }

    /** First element of a filtered JsonPath result (filters always yield arrays). */
    @SuppressWarnings("unchecked")
    private static <T> T first(String json, String path) {
        List<T> list = JsonPath.read(json, path);
        assertThat(list).as(path).isNotEmpty();
        return list.get(0);
    }

    private String store(String slug) {
        return db.queryForObject("select id from marketplace.food_restaurants where slug = ?", String.class, slug);
    }

    private String product(String name) {
        return db.queryForObject("select d.id from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.slug = 'fresh-market-almaty' and d.name = ?", String.class, name);
    }

    private void switchOff() {
        UUID admin = db.queryForObject("select id from identity.users limit 1", UUID.class);
        db.update("insert into identity.feature_toggles(feature, enabled, reason, updated_by) values ('GROCERIES', false, 'test', ?)", admin);
        toggles.invalidate();
    }

    @Test
    void categoriesAndProductsAreServedFromTheDatabaseWithServerSideFilters() throws Exception {
        String categories = body(send("GET", API + "/categories", null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(categories, "$")).hasSize(12);
        assertThat((String) JsonPath.read(categories, "$[0].slug")).isEqualTo("fruit_veg");
        assertThat(GroceriesApiIntegrationTest.<Integer>first(categories, "$[?(@.slug=='fish')].products")).isGreaterThanOrEqualTo(2);
        assertThat(GroceriesApiIntegrationTest.<Integer>first(categories, "$[?(@.slug=='frozen')].products")).isGreaterThanOrEqualTo(3);

        String all = body(send("GET", API + "/products?limit=100", null, null).andExpect(status().isOk()));
        long total = ((Number) JsonPath.read(all, "$.total")).longValue();
        assertThat(total).isGreaterThanOrEqualTo(70);
        // Search by name, by brand and by category name; LIKE wildcards are literal.
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/products?q=айдаред", null, null)), "$.items")).hasSize(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/products?q=Алматинские", null, null)), "$.items")).hasSize(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/products?q=морепродукт", null, null)), "$.items")).hasSize(2);
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/products?q=%25", null, null)), "$.items")).isEmpty();
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/products?q=несуществующий-товар", null, null)), "$.items")).isEmpty();

        // Category, store, price range and brand filters.
        String fish = body(send("GET", API + "/products?category=fish", null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(fish, "$.items[*].category")).containsOnly("fish");
        String cheap = body(send("GET", API + "/products?maxPriceMinor=30000&sort=price_asc&limit=100", null, null));
        List<Integer> cheapPrices = JsonPath.read(cheap, "$.items[*].priceMinor");
        assertThat(cheapPrices).isNotEmpty().allMatch(p -> p <= 30000).isSorted();
        String ofStore = body(send("GET", API + "/products?storeId=" + store("fresh-market-almaty") + "&limit=100", null, null));
        assertThat((List<String>) JsonPath.read(ofStore, "$.items[*].storeName")).containsOnly("Фреш Маркет Алматы");
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/products?brand=Малыш", null, null)), "$.items")).hasSize(2);
        assertThat((List<String>) JsonPath.read(body(send("GET", API + "/brands?category=kids", null, null)), "$")).containsExactly("Малыш");

        // Sale and new filters rely on stored data only.
        String sale = body(send("GET", API + "/products?onSale=true&sort=discount", null, null));
        assertThat((List<Boolean>) JsonPath.read(sale, "$.items[*].onSale")).isNotEmpty().containsOnly(true);
        List<Integer> percents = JsonPath.read(sale, "$.items[*].discountPercent");
        assertThat(percents).isSortedAccordingTo(java.util.Comparator.reverseOrder());
        String fresh = body(send("GET", API + "/products?newOnly=true", null, null));
        assertThat((List<Boolean>) JsonPath.read(fresh, "$.items[*].isNew")).isNotEmpty().containsOnly(true);

        // Pagination keeps the total; an invalid sort or price range is a client error.
        String page = body(send("GET", API + "/products?limit=5&offset=5&sort=price_desc", null, null));
        assertThat((List<?>) JsonPath.read(page, "$.items")).hasSize(5);
        assertThat(((Number) JsonPath.read(page, "$.total")).longValue()).isEqualTo(total);
        send("GET", API + "/products?sort=rating", null, null).andExpect(status().isBadRequest());
        send("GET", API + "/products?minPriceMinor=500&maxPriceMinor=100", null, null).andExpect(status().isBadRequest());
        send("GET", API + "/products?limit=1000", null, null).andExpect(status().isBadRequest());
    }

    @Test
    void popularityComesFromRealOrdersAndUnavailableProductsSinkToTheEnd() throws Exception {
        String token = login("+77000000301");
        String store = store("fresh-market-almaty");
        String milk = product("Молоко 2,5% 1 л");
        String eggs = product("Яйца С1 (10 шт)");
        db.update("update marketplace.food_dishes set available = false where id = ?::uuid", eggs);
        String list = body(send("GET", API + "/products?storeId=" + store + "&category=dairy", null, null));
        List<Boolean> stock = JsonPath.read(list, "$.items[*].inStock");
        assertThat(stock.get(stock.size() - 1)).isFalse();
        // Order milk, then it is the most popular dairy product of the store.
        String address = JsonPath.read(body(send("POST", "/api/v1/me/addresses", token,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}")
                .andExpect(status().isCreated())), "$.id");
        http.perform(post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON).header("Authorization", "Bearer " + token)
                .header("Idempotency-Key", "grocery-order-000001")
                .content("{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + milk + "\",\"quantity\":5,\"optionIds\":[]}],"
                        + "\"addressId\":\"" + address + "\",\"paymentMethod\":\"TEST_CARD\"}"))
                .andExpect(status().isCreated());
        String popular = body(send("GET", API + "/products?storeId=" + store + "&category=dairy&sort=popularity", null, null));
        assertThat((String) JsonPath.read(popular, "$.items[0].id")).isEqualTo(milk);
    }

    @Test
    void productPageHasNutritionStorageRelatedItemsAndWeightRules() throws Exception {
        String apples = product("Яблоки Айдаред");
        String detail = body(send("GET", API + "/products/" + apples, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.product.unit").value("KG")).andExpect(jsonPath("$.product.onSale").value(true))
                .andExpect(jsonPath("$.originCountry").value("Казахстан")).andExpect(jsonPath("$.nutrition.kcal").value(52))
                .andExpect(jsonPath("$.minQuantity").value(100)).andExpect(jsonPath("$.quantityStep").value(100)));
        assertThat((Integer) JsonPath.read(detail, "$.product.discountPercent")).isEqualTo(25);
        assertThat((Integer) JsonPath.read(detail, "$.product.maxQuantity")).isEqualTo(5000);
        assertThat((List<?>) JsonPath.read(detail, "$.related")).isNotEmpty().hasSizeLessThanOrEqualTo(6);
        assertThat((List<String>) JsonPath.read(detail, "$.related[*].id")).doesNotContain(apples);
        // Photos added by the partner form the gallery in order; without photos the cover (if any) is the only image.
        db.update("insert into marketplace.food_dish_photos (dish_id, url, sort_order) values (?::uuid, 'https://img.example.test/1.jpg', 0), (?::uuid, 'https://img.example.test/2.jpg', 1)", apples, apples);
        assertThat((List<String>) JsonPath.read(body(send("GET", API + "/products/" + apples, null, null)), "$.images"))
                .containsExactly("https://img.example.test/1.jpg", "https://img.example.test/2.jpg");
        send("GET", API + "/products/" + UUID.randomUUID(), null, null).andExpect(status().isNotFound());
        // A product with a mandatory choice (fat content) is flagged so clients open the product page instead of quick-adding it.
        String choice = db.queryForObject("select d.id from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.slug = 'market-alatau' and d.name = 'Молоко 1 л'", String.class);
        send("GET", API + "/products/" + choice, null, null).andExpect(jsonPath("$.product.hasRequiredOptions").value(true));
        send("GET", API + "/products/" + apples, null, null).andExpect(jsonPath("$.product.hasRequiredOptions").value(false));
        // A restaurant dish is not a grocery product.
        String dish = db.queryForObject("select d.id from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.vertical = 'FOOD' limit 1", String.class);
        send("GET", API + "/products/" + dish, null, null).andExpect(status().isNotFound());
    }

    @Test
    void personalDataRequiresAuthentication() throws Exception {
        for (String path : new String[] {"/favorites", "/lists", "/cart"}) {
            send("GET", API + path, null, null).andExpect(status().isUnauthorized());
        }
        send("PUT", API + "/cart", null, "{\"restaurantId\":\"" + UUID.randomUUID() + "\",\"items\":[]}").andExpect(status().isUnauthorized());
        send("PUT", API + "/favorites/" + UUID.randomUUID(), null, null).andExpect(status().isUnauthorized());
    }

    @Test
    void favoritesAreStoredPerCustomer() throws Exception {
        String a = login("+77000000301");
        String b = login("+77000000302");
        String apples = product("Яблоки Айдаред");
        send("PUT", API + "/favorites/" + apples, a, null).andExpect(status().isOk()).andExpect(jsonPath("$.favorite").value(true));
        send("PUT", API + "/favorites/" + apples, a, null).andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/favorites", a, null)), "$")).hasSize(1);
        assertThat((List<String>) JsonPath.read(body(send("GET", API + "/favorites/ids", a, null)), "$")).containsExactly(apples);
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/favorites", b, null)), "$")).isEmpty();
        send("PUT", API + "/favorites/" + UUID.randomUUID(), a, null).andExpect(status().isNotFound());
        send("DELETE", API + "/favorites/" + apples, a, null).andExpect(status().isOk()).andExpect(jsonPath("$.favorite").value(false));
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/favorites", a, null)), "$")).isEmpty();
    }

    @Test
    void shoppingListsPersistAreOwnedAndFeedTheCart() throws Exception {
        String a = login("+77000000301");
        String b = login("+77000000302");
        String listId = JsonPath.read(body(send("POST", API + "/lists", a, "{\"name\":\"На неделю\"}").andExpect(status().isCreated())), "$.id");
        send("POST", API + "/lists", a, "{\"name\":\"  \"}").andExpect(status().isBadRequest());
        String apples = product("Яблоки Айдаред");
        String milk = product("Молоко 2,5% 1 л");
        String eggs = product("Яйца С1 (10 шт)");
        String frozen = product("Мороженое пломбир 450 г");
        // Weighed goods need 100 g steps, pieces at most 20.
        send("PUT", API + "/lists/" + listId + "/items/" + apples, a, "{\"quantity\":150}").andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("QUANTITY_INVALID"));
        send("PUT", API + "/lists/" + listId + "/items/" + milk, a, "{\"quantity\":21}").andExpect(status().isUnprocessableEntity());
        send("PUT", API + "/lists/" + listId + "/items/" + apples, a, "{\"quantity\":2000}").andExpect(status().isOk());
        send("PUT", API + "/lists/" + listId + "/items/" + milk, a, "{\"quantity\":3}").andExpect(status().isOk());
        send("PUT", API + "/lists/" + listId + "/items/" + eggs, a, "{\"quantity\":1}").andExpect(status().isOk());
        send("PUT", API + "/lists/" + listId + "/items/" + frozen, a, "{\"quantity\":1,\"checked\":true}").andExpect(status().isOk());
        // Another product of the same list is bought, one becomes unavailable.
        db.update("update marketplace.food_dishes set available = false where id = ?::uuid", eggs);
        String detail = body(send("GET", API + "/lists/" + listId, a, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(detail, "$.items")).hasSize(4);
        assertThat(GroceriesApiIntegrationTest.<Boolean>first(detail, "$.items[?(@.productId=='" + eggs + "')].inStock")).isFalse();
        assertThat(GroceriesApiIntegrationTest.<Boolean>first(detail, "$.items[?(@.productId=='" + frozen + "')].checked")).isTrue();

        // Ownership: another customer neither sees nor changes the list.
        send("GET", API + "/lists/" + listId, b, null).andExpect(status().isNotFound());
        send("PUT", API + "/lists/" + listId, b, "{\"name\":\"чужой\"}").andExpect(status().isNotFound());
        send("DELETE", API + "/lists/" + listId, b, null).andExpect(status().isNotFound());
        send("PUT", API + "/lists/" + listId + "/items/" + milk, b, "{\"quantity\":1}").andExpect(status().isNotFound());
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/lists", b, null)), "$")).isEmpty();

        // The list survives a new session and renames.
        String again = login("+77000000301");
        send("PUT", API + "/lists/" + listId, again, "{\"name\":\"Выходные\"}").andExpect(status().isOk()).andExpect(jsonPath("$.name").value("Выходные"));
        assertThat((Integer) JsonPath.read(body(send("GET", API + "/lists", again, null)), "$[0].items")).isEqualTo(4);

        // To cart: only available, not yet bought items are added; the others are reported.
        String result = body(send("POST", API + "/lists/" + listId + "/to-cart", again, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(result, "$.cart.lines[*].dishId")).containsExactlyInAnyOrder(apples, milk);
        assertThat((List<String>) JsonPath.read(result, "$.skipped[*].reason")).containsExactlyInAnyOrder("UNAVAILABLE", "ALREADY_BOUGHT");
        assertThat((Integer) JsonPath.read(result, "$.cart.subtotalMinor")).isEqualTo(118_000 + 3 * 69_000);

        send("DELETE", API + "/lists/" + listId + "/items/" + milk, again, null).andExpect(status().isOk());
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/lists/" + listId, again, null)), "$.items")).hasSize(3);
        send("DELETE", API + "/lists/" + listId, again, null).andExpect(status().isNoContent());
        send("GET", API + "/lists/" + listId, again, null).andExpect(status().isNotFound());
    }

    @Test
    void cartIsSavedOnTheServerRepricedAndHandedToCheckout() throws Exception {
        String a = login("+77000000301");
        String b = login("+77000000302");
        String store = store("fresh-market-almaty");
        String apples = product("Яблоки Айдаред");
        String milk = product("Молоко 2,5% 1 л");
        String put = "{\"restaurantId\":\"" + store + "\",\"items\":["
                + "{\"dishId\":\"" + apples + "\",\"quantity\":2000},{\"dishId\":\"" + milk + "\",\"quantity\":3}]}";
        String saved = body(send("PUT", API + "/cart", a, put).andExpect(status().isOk()));
        assertThat((Integer) JsonPath.read(saved, "$.subtotalMinor")).isEqualTo(118_000 + 207_000);
        assertThat((Integer) JsonPath.read(saved, "$.totalMinor")).isEqualTo(325_000);
        assertThat((Boolean) JsonPath.read(saved, "$.needsUpdate")).isFalse();
        assertThat((Integer) JsonPath.read(saved, "$.minOrderMinor")).isEqualTo(300_000);

        // Survives a new session, is private, and a promo code is evaluated by the server (WELCOME10 is seeded elsewhere).
        String again = login("+77000000301");
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/cart", again, null)), "$.lines")).hasSize(2);
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/cart", b, null)), "$.lines")).isEmpty();

        // The shop changes the price and runs out of stock: the customer sees it, totals use only valid lines.
        db.update("update marketplace.food_dishes set price_minor = 65000 where id = ?::uuid", apples);
        db.update("update marketplace.food_dishes set stock_qty = 2 where id = ?::uuid", milk);
        String changed = body(send("GET", API + "/cart", again, null).andExpect(status().isOk()));
        assertThat((Boolean) JsonPath.read(changed, "$.needsUpdate")).isTrue();
        assertThat(GroceriesApiIntegrationTest.<String>first(changed, "$.lines[?(@.dishId=='" + apples + "')].issue")).isEqualTo("PRICE_CHANGED");
        assertThat(GroceriesApiIntegrationTest.<Integer>first(changed, "$.lines[?(@.dishId=='" + apples + "')].previousUnitPriceMinor")).isEqualTo(59_000);
        assertThat(GroceriesApiIntegrationTest.<String>first(changed, "$.lines[?(@.dishId=='" + milk + "')].issue")).isEqualTo("STOCK_LOW");

        // Quantities are validated against the unit; unknown products and a restaurant dish are refused.
        send("PUT", API + "/cart", again, "{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + apples + "\",\"quantity\":50}]}")
                .andExpect(status().isUnprocessableEntity());
        send("PUT", API + "/cart", again, "{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + UUID.randomUUID() + "\",\"quantity\":1}]}")
                .andExpect(status().isNotFound());
        send("PUT", API + "/cart", again, "{\"restaurantId\":\"" + store("pizza-alatau") + "\",\"items\":[{\"dishId\":\"" + milk + "\",\"quantity\":1}]}")
                .andExpect(status().isNotFound());

        // Accepting the changes (saving again) clears the price warning; checkout then goes through the shared Food orders.
        db.update("update marketplace.food_dishes set stock_qty = 40 where id = ?::uuid", milk);
        send("PUT", API + "/cart", again, put).andExpect(status().isOk()).andExpect(jsonPath("$.needsUpdate").value(false))
                .andExpect(jsonPath("$.subtotalMinor").value(130_000 + 207_000));
        String address = JsonPath.read(body(send("POST", "/api/v1/me/addresses", again,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}")
                .andExpect(status().isCreated())), "$.id");
        String order = body(http.perform(post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON)
                .header("Authorization", "Bearer " + again).header("Idempotency-Key", "grocery-order-000002")
                .content("{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + apples + "\",\"quantity\":2000,\"optionIds\":[]},"
                        + "{\"dishId\":\"" + milk + "\",\"quantity\":3,\"optionIds\":[]}],\"addressId\":\"" + address
                        + "\",\"paymentMethod\":\"TEST_CARD\",\"expectedTotalMinor\":337000}"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.vertical").value("GROCERY")));
        assertThat((Integer) JsonPath.read(order, "$.totalMinor")).isEqualTo(337_000);

        // Clearing the cart.
        send("DELETE", API + "/cart", again, null).andExpect(status().isNoContent());
        assertThat((List<?>) JsonPath.read(body(send("GET", API + "/cart", again, null)), "$.lines")).isEmpty();
    }

    @Test
    void aCartHoldsOneStoreAndAListMovesItemsOfOneStoreAtATime() throws Exception {
        String a = login("+77000000301");
        String fresh = store("fresh-market-almaty");
        String alatau = store("market-alatau");
        String apples = product("Яблоки Айдаред");
        String listId = JsonPath.read(body(send("POST", API + "/lists", a, "{\"name\":\"Разные магазины\"}")), "$.id");
        String alatauMilk = db.queryForObject("select d.id from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id "
                + "where r.slug = 'market-alatau' and d.name = 'Кефир 0,9 л'", String.class);
        send("PUT", API + "/lists/" + listId + "/items/" + apples, a, "{\"quantity\":1000}").andExpect(status().isOk());
        send("PUT", API + "/lists/" + listId + "/items/" + alatauMilk, a, "{\"quantity\":2}").andExpect(status().isOk());
        // A cart of the first store blocks moving the list to another store unless it is replaced explicitly.
        send("PUT", API + "/cart", a, "{\"restaurantId\":\"" + alatau + "\",\"items\":[{\"dishId\":\"" + alatauMilk + "\",\"quantity\":1}]}")
                .andExpect(status().isOk());
        send("POST", API + "/lists/" + listId + "/to-cart?storeId=" + fresh, a, null).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("CART_STORE_CONFLICT"));
        String replaced = body(send("POST", API + "/lists/" + listId + "/to-cart?storeId=" + fresh + "&replace=true", a, null)
                .andExpect(status().isOk()));
        assertThat((String) JsonPath.read(replaced, "$.cart.restaurantName")).isEqualTo("Фреш Маркет Алматы");
        assertThat((List<String>) JsonPath.read(replaced, "$.skipped[*].reason")).containsExactly("OTHER_STORE");
    }

    @Test
    void theGroceriesSwitchStopsNewActivityButKeepsHistoryAndCleanup() throws Exception {
        String a = login("+77000000301");
        String store = store("fresh-market-almaty");
        String apples = product("Яблоки Айдаред");
        String milk = product("Молоко 2,5% 1 л");
        String address = JsonPath.read(body(send("POST", "/api/v1/me/addresses", a,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}")
                .andExpect(status().isCreated())), "$.id");
        String listId = JsonPath.read(body(send("POST", API + "/lists", a, "{\"name\":\"Список\"}")), "$.id");
        send("PUT", API + "/favorites/" + apples, a, null).andExpect(status().isOk());
        send("PUT", API + "/cart", a, "{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + milk + "\",\"quantity\":5}]}")
                .andExpect(status().isOk());
        String orderBody = "{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + milk + "\",\"quantity\":5,\"optionIds\":[]}],"
                + "\"addressId\":\"" + address + "\",\"paymentMethod\":\"TEST_CARD\"}";
        String placed = body(http.perform(post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON)
                .header("Authorization", "Bearer " + a).header("Idempotency-Key", "grocery-order-000003").content(orderBody))
                .andExpect(status().isCreated()));
        String orderId = JsonPath.read(placed, "$.id");

        switchOff();
        send("GET", "/api/v1/capabilities", null, null).andExpect(jsonPath("$.groceriesEnabled").value(false));
        for (String path : new String[] {"/categories", "/products", "/products/" + apples, "/brands"}) {
            send("GET", API + path, null, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("GROCERIES_DISABLED"));
        }
        send("GET", "/api/v1/food/restaurants?vertical=GROCERY", null, null).andExpect(status().isConflict());
        send("GET", "/api/v1/food/search?q=молоко&vertical=GROCERY", null, null).andExpect(status().isConflict());
        send("PUT", API + "/favorites/" + milk, a, null).andExpect(status().isConflict());
        send("POST", API + "/lists", a, "{\"name\":\"Новый\"}").andExpect(status().isConflict());
        send("PUT", API + "/lists/" + listId + "/items/" + milk, a, "{\"quantity\":1}").andExpect(status().isConflict());
        send("PUT", API + "/cart", a, "{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + milk + "\",\"quantity\":1}]}")
                .andExpect(status().isConflict());
        send("POST", "/api/v1/food/cart/quote", a, "{\"restaurantId\":\"" + store + "\",\"items\":[{\"dishId\":\"" + milk + "\",\"quantity\":5}]}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("GROCERIES_DISABLED"));
        http.perform(post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON).header("Authorization", "Bearer " + a)
                .header("Idempotency-Key", "grocery-order-000004").content(orderBody)).andExpect(status().isConflict());
        // History, the existing order, an idempotent replay, reading and removing own data keep working.
        send("GET", "/api/v1/food/orders/" + orderId, a, null).andExpect(status().isOk());
        http.perform(post("/api/v1/food/orders").contentType(MediaType.APPLICATION_JSON).header("Authorization", "Bearer " + a)
                .header("Idempotency-Key", "grocery-order-000003").content(orderBody)).andExpect(status().isOk());
        send("POST", "/api/v1/food/orders/" + orderId + "/cancel", a, null).andExpect(status().isOk());
        send("GET", API + "/favorites", a, null).andExpect(status().isOk());
        send("GET", API + "/lists/" + listId, a, null).andExpect(status().isOk());
        send("GET", API + "/cart", a, null).andExpect(status().isOk());
        send("DELETE", API + "/favorites/" + apples, a, null).andExpect(status().isOk());
        send("DELETE", API + "/cart", a, null).andExpect(status().isNoContent());
        send("DELETE", API + "/lists/" + listId, a, null).andExpect(status().isNoContent());
        // Restaurants are not affected by the Groceries switch.
        send("GET", "/api/v1/food/restaurants", null, null).andExpect(status().isOk());
    }

    @Test
    void capabilitiesReportGroceriesOnInTestEnvironments() throws Exception {
        send("GET", "/api/v1/capabilities", null, null).andExpect(jsonPath("$.groceriesEnabled").value(true));
    }
}
