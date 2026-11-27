package kz.kunde.flowers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
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

/** Flowers courier hand-off: shop-side steps, atomic claim, pick-up, delivery, estimate and the customer's view. Rolls back. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.flowers.enabled=true",
        "app.flowers.simulation-step-seconds=1",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000311,+77000000312,+77000000313",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FlowersCourierApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired FlowersFulfillmentService fulfillment;

    String shop;
    String rose;

    @BeforeEach
    void seed() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000311', '+77000000312', '+77000000313')");
        db.update("delete from transactions.flowers_courier_tasks");
        db.update("delete from transactions.flowers_order_items");
        db.update("delete from transactions.flowers_orders");
        db.update("delete from marketplace.flowers_products");
        db.update("delete from marketplace.flowers_shops");
        new FlowersDemoSeeder(db).seed();
        shop = db.queryForObject("select id::text from marketplace.flowers_shops where slug = 'flowers-demo-lavka'", String.class);
        db.update("update marketplace.flowers_shops set address_text = 'Алматы, ул. Тестовая 1 (демо)', eta_min_minutes = 30 where id = ?::uuid", shop);
        rose = db.queryForObject("select id::text from marketplace.flowers_products where name = 'Букет «Классика»'", String.class);
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

    private UUID subject(String token) throws Exception {
        return UUID.fromString(JsonPath.read(body(send("GET", "/api/v1/me", token, null, null).andExpect(status().isOk())), "$.id"));
    }

    private void approvedCourier(String token) throws Exception {
        db.update("insert into transactions.delivery_couriers (user_id, display_name, vehicle, status, online, max_grams, max_side_cm) values (?, 'Курьер DEV', 'CAR', 'APPROVED', true, 20000, 100)", subject(token));
    }

    private String placeOrder(String token, String key) throws Exception {
        String json = "{\"shopId\":\"" + shop + "\",\"items\":[{\"productId\":\"" + rose + "\",\"quantity\":1}],\"deliveryMode\":\"ASAP\","
                + "\"addressText\":\"Алматы, ул. Абая 150, кв. 45 (тест)\",\"recipientName\":\"Айгуль\",\"expectedTotalMinor\":1890000}";
        return JsonPath.read(body(send("POST", "/api/v1/flowers/orders", token, json, key).andExpect(status().isCreated())), "$.id");
    }

    @Test
    void anOrderGoesFromTheShopThroughTheCourierToDelivered() throws Exception {
        String customer = login("+77000000311");
        String courier = login("+77000000312");
        approvedCourier(courier);
        String order = placeOrder(customer, "c-1");

        // nothing to take until the shop has assembled the order
        send("GET", "/api/v1/executor/flowers/tasks/open", courier, null, null).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(0)));
        UUID id = UUID.fromString(order);
        fulfillment.accept(id, "SHOP", null);
        send("GET", "/api/v1/executor/flowers/tasks/open", courier, null, null).andExpect(jsonPath("$", hasSize(0)));
        fulfillment.startAssembling(id, "SHOP", null);

        String task = JsonPath.read(body(send("GET", "/api/v1/executor/flowers/tasks/open", courier, null, null)
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].storeAddress").value("Алматы, ул. Тестовая 1 (демо)"))
                .andExpect(jsonPath("$[0].deliveryAddress").doesNotExist())
                .andExpect(jsonPath("$[0].recipientName").doesNotExist())), "$[0].id");

        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null)
                .andExpect(jsonPath("$.status").value("ASSEMBLING")).andExpect(jsonPath("$.courierAssigned").value(false))
                .andExpect(jsonPath("$.etaMinutes").doesNotExist());

        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/accept", courier, null, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ASSIGNED"))
                .andExpect(jsonPath("$.deliveryAddress").value("Алматы, ул. Абая 150, кв. 45 (тест)"))
                .andExpect(jsonPath("$.recipientName").value("Айгуль"));
        // a replay by the winner is the same task
        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/accept", courier, null, null).andExpect(jsonPath("$.status").value("ASSIGNED"));
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null).andExpect(jsonPath("$.courierAssigned").value(true));
        // delivering before picking up is refused
        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/deliver", courier, null, null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TASK_STATE_INVALID"));

        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/pickup", courier, null, null).andExpect(jsonPath("$.status").value("PICKED_UP"));
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null)
                .andExpect(jsonPath("$.status").value("ON_THE_WAY")).andExpect(jsonPath("$.etaMinutes").value(30))
                .andExpect(jsonPath("$.events", hasSize(4)));
        // the estimate counts down from the pick-up and never goes below one minute
        db.update("update transactions.flowers_courier_tasks set picked_up_at = now() - interval '12 minutes'");
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null).andExpect(jsonPath("$.etaMinutes").value(18));
        db.update("update transactions.flowers_courier_tasks set picked_up_at = now() - interval '5 hours'");
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null).andExpect(jsonPath("$.etaMinutes").value(1));
        // a started order can no longer be cancelled for free
        send("POST", "/api/v1/flowers/orders/" + order + "/cancel", customer, null, null).andExpect(status().isConflict());

        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/deliver", courier, null, null).andExpect(jsonPath("$.status").value("DELIVERED"));
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null)
                .andExpect(jsonPath("$.status").value("DELIVERED")).andExpect(jsonPath("$.etaMinutes").doesNotExist());
        send("GET", "/api/v1/executor/flowers/tasks/mine", courier, null, null)
                .andExpect(jsonPath("$", hasSize(1))).andExpect(jsonPath("$[0].status").value("DELIVERED"));
    }

    @Test
    void onlyOneCourierWinsATaskAndOnlyApprovedOnlineCouriersSeeTasks() throws Exception {
        String customer = login("+77000000311");
        String first = login("+77000000312");
        String second = login("+77000000313");
        send("GET", "/api/v1/executor/flowers/tasks/open", first, null, null)
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("COURIER_NOT_APPROVED"));
        approvedCourier(first);
        approvedCourier(second);
        UUID id = UUID.fromString(placeOrder(customer, "c-2"));
        fulfillment.accept(id, "SHOP", null);
        fulfillment.startAssembling(id, "SHOP", null);
        String task = db.queryForObject("select id::text from transactions.flowers_courier_tasks", String.class);

        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/accept", first, null, null).andExpect(status().isOk());
        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/accept", second, null, null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("TASK_UNAVAILABLE"));
        send("POST", "/api/v1/executor/flowers/tasks/" + task + "/pickup", second, null, null).andExpect(status().isNotFound());
        send("GET", "/api/v1/executor/flowers/tasks/open", second, null, null).andExpect(jsonPath("$", hasSize(0)));
        // offline couriers do not see open tasks
        db.update("update transactions.delivery_couriers set online = false where user_id = ?", subject(second));
        send("GET", "/api/v1/executor/flowers/tasks/open", second, null, null).andExpect(status().isForbidden());
        send("GET", "/api/v1/executor/flowers/tasks/mine", second, null, null).andExpect(status().isOk());
    }

    @Test
    void orderOfADemoShopAdvancesOnItsOwnAndOpensTheCourierTask() throws Exception {
        String customer = login("+77000000311");
        String order = placeOrder(customer, "c-3");
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null).andExpect(jsonPath("$.status").value("PLACED"));
        db.update("update transactions.flowers_orders set placed_at = now() - interval '90 seconds'");
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null)
                .andExpect(jsonPath("$.status").value("ASSEMBLING")).andExpect(jsonPath("$.events", hasSize(3)));
        assertThat(db.queryForObject("select count(*) from transactions.flowers_courier_tasks where status = 'OPEN'", Long.class)).isEqualTo(1);
        // reading again changes nothing
        send("GET", "/api/v1/flowers/orders/" + order, customer, null, null).andExpect(jsonPath("$.events", hasSize(3)));
        // a shop run by a real partner is never simulated
        String real = placeOrder(customer, "c-4");
        db.update("update marketplace.flowers_shops set is_synthetic = false where id = ?::uuid", shop);
        db.update("update transactions.flowers_orders set placed_at = now() - interval '900 seconds' where id = ?::uuid", real);
        fulfillment.advance(UUID.fromString(real));
        assertThat(db.queryForObject("select status from transactions.flowers_orders where id = ?::uuid", String.class, real)).isEqualTo("PLACED");
    }

    @Test
    void shopSideStepsMustFollowTheOrder() throws Exception {
        String customer = login("+77000000311");
        UUID id = UUID.fromString(placeOrder(customer, "c-5"));
        org.assertj.core.api.Assertions.assertThatThrownBy(() -> fulfillment.startAssembling(id, "SHOP", null))
                .hasMessageContaining("cannot be assembled");
        fulfillment.accept(id, "SHOP", null);
        org.assertj.core.api.Assertions.assertThatThrownBy(() -> fulfillment.accept(id, "SHOP", null))
                .hasMessageContaining("cannot be accepted");
    }
}
