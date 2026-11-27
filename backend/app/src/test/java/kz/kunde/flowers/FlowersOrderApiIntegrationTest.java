package kz.kunde.flowers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/** Flowers cart quote, delivery windows, idempotent checkout, stock, history, cancellation and ownership over HTTP. Rolls back. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.flowers.enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000301,+77000000302",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FlowersOrderApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    String shop;
    String rose;
    String card;

    @BeforeEach
    void seed() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000301', '+77000000302')");
        db.update("delete from transactions.flowers_order_items");
        db.update("delete from transactions.flowers_orders");
        db.update("delete from marketplace.flowers_products");
        db.update("delete from marketplace.flowers_shops");
        new FlowersDemoSeeder(db).seed();
        shop = db.queryForObject("select id::text from marketplace.flowers_shops where slug = 'flowers-demo-lavka'", String.class);
        rose = db.queryForObject("select id::text from marketplace.flowers_products where name = 'Букет «Классика»'", String.class);
        db.update("update marketplace.flowers_products set stock_qty = 3 where id = ?::uuid", rose);
        card = db.queryForObject("select id::text from marketplace.flowers_products where name = 'Набор конфет'", String.class);
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
        return JsonPath.read(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null)
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(), "$.accessToken");
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String order(String shopId, String productId, int qty, String mode, String from, long expected) {
        return "{\"shopId\":\"" + shopId + "\",\"items\":[{\"productId\":\"" + productId + "\",\"quantity\":" + qty + "}],\"deliveryMode\":\"" + mode + "\""
                + (from == null ? "" : ",\"scheduledFrom\":\"" + from + "\"") + ",\"addressLabel\":\"Дом\",\"addressText\":\"Алматы, ул. Абая 150, кв. 45 (тест)\","
                + "\"recipientName\":\"Айгуль\",\"cardText\":\"С днём рождения!\",\"comment\":\"Позвонить за 10 минут\",\"expectedTotalMinor\":" + expected + "}";
    }

    private String futureSlot() throws Exception {
        String date = LocalDate.now(ZoneId.of("Asia/Almaty")).plusDays(3).toString();
        return JsonPath.read(body(send("GET", "/api/v1/flowers/delivery-slots?date=" + date, null, null, null).andExpect(status().isOk())), "$[2].startsAt");
    }

    @Test
    void deliverySlotsArePublicTwoHourWindowsWithALeadTime() throws Exception {
        String date = LocalDate.now(ZoneId.of("Asia/Almaty")).plusDays(3).toString();
        send("GET", "/api/v1/flowers/delivery-slots?date=" + date, null, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(5)));
        String yesterday = LocalDate.now(ZoneId.of("Asia/Almaty")).minusDays(1).toString();
        send("GET", "/api/v1/flowers/delivery-slots?date=" + yesterday, null, null, null).andExpect(jsonPath("$", hasSize(0)));
        String far = LocalDate.now(ZoneId.of("Asia/Almaty")).plusDays(60).toString();
        send("GET", "/api/v1/flowers/delivery-slots?date=" + far, null, null, null).andExpect(jsonPath("$", hasSize(0)));
        // unit view of the lead rule: at 09:00 local time the 10:00 window is too close, 12:00 is the first one
        var service = new FlowersOrderService(null, null);
        Instant nineLocal = LocalDate.now(ZoneId.of("Asia/Almaty")).plusDays(1).atTime(9, 0).atZone(ZoneId.of("Asia/Almaty")).toInstant();
        var slots = service.slots(nineLocal.atZone(ZoneId.of("Asia/Almaty")).toLocalDate(), nineLocal);
        assertThat(slots).hasSize(4);
        assertThat(slots.get(0).startsAt().atZone(ZoneId.of("Asia/Almaty")).getHour()).isEqualTo(12);
    }

    @Test
    void checkoutNeedsSignInAndAnIdempotencyKey() throws Exception {
        send("POST", "/api/v1/flowers/orders", null, order(shop, rose, 1, "ASAP", null, 1890000), "k1").andExpect(status().isUnauthorized());
        String token = login("+77000000301");
        send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 1, "ASAP", null, 1890000), null)
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REQUIRED"));
    }

    @Test
    void quotePricesOnTheServerAndRejectsBadCarts() throws Exception {
        String token = login("+77000000301");
        send("POST", "/api/v1/flowers/cart/quote", token,
                "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + rose + "\",\"quantity\":2}],\"deliveryMode\":\"ASAP\"}", null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.subtotalMinor").value(3580000))
                .andExpect(jsonPath("$.deliveryFeeMinor").value(100000))
                .andExpect(jsonPath("$.totalMinor").value(3680000))
                .andExpect(jsonPath("$.lines[0].lineTotalMinor").value(3580000));
        // more than the stock
        send("POST", "/api/v1/flowers/cart/quote", token,
                "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + rose + "\",\"quantity\":4}],\"deliveryMode\":\"ASAP\"}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("FLOWERS_STOCK_INSUFFICIENT"));
        // a product of another shop
        send("POST", "/api/v1/flowers/cart/quote", token,
                "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + card + "\",\"quantity\":1}],\"deliveryMode\":\"ASAP\"}", null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FLOWERS_PRODUCT_UNAVAILABLE"));
        send("POST", "/api/v1/flowers/cart/quote", token,
                "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + rose + "\",\"quantity\":1}],\"deliveryMode\":\"SOMETIME\"}", null)
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("FLOWERS_DELIVERY_MODE_INVALID"));
        send("POST", "/api/v1/flowers/cart/quote", token,
                "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + rose + "\",\"quantity\":1}],\"deliveryMode\":\"SCHEDULED\",\"scheduledFrom\":\"2020-01-01T10:00:00+05:00\"}", null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FLOWERS_SLOT_UNAVAILABLE"));
        db.update("update marketplace.flowers_shops set is_open = false where id = ?::uuid", shop);
        send("POST", "/api/v1/flowers/cart/quote", token,
                "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + rose + "\",\"quantity\":1}],\"deliveryMode\":\"ASAP\"}", null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("FLOWERS_SHOP_CLOSED"));
    }

    @Test
    void asapOrderIsIdempotentReservesStockAndAppearsInHistoryOnlyForItsOwner() throws Exception {
        String token = login("+77000000301");
        String first = body(send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 2, "ASAP", null, 3680000), "key-1")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("PLACED"))
                .andExpect(jsonPath("$.paymentMethod").value("DEV_NO_PAYMENT"))
                .andExpect(jsonPath("$.totalMinor").value(3680000))
                .andExpect(jsonPath("$.recipientName").value("Айгуль"))
                .andExpect(jsonPath("$.items", hasSize(1))).andExpect(jsonPath("$.events", hasSize(1))));
        String id = JsonPath.read(first, "$.id");
        assertThat(db.queryForObject("select stock_qty from marketplace.flowers_products where id = ?::uuid", Integer.class, rose)).isEqualTo(1);

        send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 2, "ASAP", null, 3680000), "key-1")
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        assertThat(db.queryForObject("select stock_qty from marketplace.flowers_products where id = ?::uuid", Integer.class, rose)).isEqualTo(1);
        String otherShop = db.queryForObject("select id::text from marketplace.flowers_shops where slug = 'flowers-demo-gifts'", String.class);
        send("POST", "/api/v1/flowers/orders", token, order(otherShop, card, 1, "ASAP", null, 750000), "key-1")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REUSED"));

        send("GET", "/api/v1/flowers/orders", token, null, null).andExpect(jsonPath("$", hasSize(1))).andExpect(jsonPath("$[0].id").value(id));
        send("GET", "/api/v1/flowers/orders/" + id, token, null, null).andExpect(status().isOk());
        String other = login("+77000000302");
        send("GET", "/api/v1/flowers/orders/" + id, other, null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/flowers/orders", other, null, null).andExpect(jsonPath("$", hasSize(0)));
        send("POST", "/api/v1/flowers/orders/" + id + "/cancel", other, null, null).andExpect(status().isNotFound());
    }

    @Test
    void aChangedTotalOrStockIsRefusedAndNothingIsReserved() throws Exception {
        String token = login("+77000000301");
        send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 1, "ASAP", null, 1), "key-2")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("FLOWERS_PRICE_CHANGED"));
        send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 5, "ASAP", null, 9450000), "key-3")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("FLOWERS_STOCK_INSUFFICIENT"));
        assertThat(db.queryForObject("select stock_qty from marketplace.flowers_products where id = ?::uuid", Integer.class, rose)).isEqualTo(3);
        assertThat(db.queryForObject("select count(*) from transactions.flowers_orders", Long.class)).isZero();
    }

    @Test
    void scheduledOrderKeepsItsWindowAndCancellationReturnsStockOnce() throws Exception {
        String token = login("+77000000301");
        String slot = futureSlot();
        String created = body(send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 1, "SCHEDULED", slot, 1890000), "key-4")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.deliveryMode").value("SCHEDULED")));
        String id = JsonPath.read(created, "$.id");
        assertThat(Instant.parse(JsonPath.read(created, "$.scheduledFrom"))).isEqualTo(Instant.parse(slot));
        assertThat(db.queryForObject("select stock_qty from marketplace.flowers_products where id = ?::uuid", Integer.class, rose)).isEqualTo(2);

        send("POST", "/api/v1/flowers/orders/" + id + "/cancel", token, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED")).andExpect(jsonPath("$.events", hasSize(2)));
        assertThat(db.queryForObject("select stock_qty from marketplace.flowers_products where id = ?::uuid", Integer.class, rose)).isEqualTo(3);
        send("POST", "/api/v1/flowers/orders/" + id + "/cancel", token, null, null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ORDER_NOT_CANCELLABLE"));
        assertThat(db.queryForObject("select stock_qty from marketplace.flowers_products where id = ?::uuid", Integer.class, rose)).isEqualTo(3);
        // an accepted order can no longer be cancelled for free
        send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 1, "ASAP", null, 1890000), "key-5").andExpect(status().isCreated());
        String accepted = db.queryForObject("select id::text from transactions.flowers_orders where status = 'PLACED'", String.class);
        db.update("update transactions.flowers_orders set status = 'ACCEPTED' where id = ?::uuid", accepted);
        send("POST", "/api/v1/flowers/orders/" + accepted + "/cancel", token, null, null).andExpect(status().isConflict());
    }

    @Test
    void anAddressIsRequired() throws Exception {
        String token = login("+77000000301");
        send("POST", "/api/v1/flowers/orders", token, order(shop, rose, 1, "ASAP", null, 1890000).replace("Алматы, ул. Абая 150, кв. 45 (тест)", "ул"), "key-6")
                .andExpect(status().isBadRequest());
    }
}
