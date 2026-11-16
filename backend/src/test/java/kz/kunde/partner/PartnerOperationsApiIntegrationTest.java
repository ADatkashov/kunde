package kz.kunde.partner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import kz.kunde.booking.BookingDemoSeeder;
import kz.kunde.food.FoodDemoSeeder;
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
 * Partner Operations over HTTP against PostgreSQL: a customer orders/books at a partner-managed synthetic restaurant/venue,
 * the partner sees, accepts/rejects and completes it, the customer sees the result. Covers ownership isolation (another
 * partner, a plain customer, an operator's role limits), server-side state machine, idempotent repeats, availability and
 * schedule conflicts and the audit trail. Synthetic numbers and data only; the whole test rolls back.
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000401,+77000000402,+77000000403",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class PartnerOperationsApiIntegrationTest {
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    String ownerToken;   // partner A owner (+77000000002)
    String otherToken;   // partner B owner (+77000000003)
    String customer;     // plain customer, no partner scope
    UUID partnerA;
    UUID restaurant;
    UUID venue;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000401','+77000000402','+77000000403')");
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) {
                new FoodDemoSeeder(db).seed(new ObjectMapper().readTree(in));
            }
        }
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) {
                new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in));
            }
        }
        partnerA = new PartnerOpsDemoSeeder(db, auth, env).seed();
        ownerToken = login("+77000000002");
        otherToken = login("+77000000003");
        customer = login("+77000000401");
        restaurant = UUID.fromString(db.queryForObject("select id from marketplace.food_restaurants where slug = 'partner-kitchen-demo'", String.class));
        venue = UUID.fromString(db.queryForObject("select id from marketplace.booking_venues where slug = 'partner-salon-demo'", String.class));
    }

    // ---- helpers -------------------------------------------------------------------------------

    private ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
            case "PATCH" -> patch(path);
            case "PUT" -> put(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (key != null) { request.header("Idempotency-Key", key); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    /** Logs in; the access token's scope reflects partner membership at issue time. */
    private String login(String phone) throws Exception {
        return JsonPath.read(loginBody(phone), "$.accessToken");
    }

    private String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk()));
    }

    private String address(String token) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/me/addresses", token,
                "{\"label\":\"Дом\",\"formattedAddress\":\"Алматы, пр. Абая 10 (тестовый адрес)\",\"latitude\":43.238,\"longitude\":76.945}", null)
                .andExpect(status().isCreated())), "$.id");
    }

    private String dishId(String name) {
        return db.queryForObject("select id from marketplace.food_dishes where restaurant_id = ? and name = ?", String.class, restaurant, name);
    }

    private String placeOrder(String token, String dish, int qty, String key) throws Exception {
        String json = "{\"restaurantId\":\"" + restaurant + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":" + qty
                + ",\"optionIds\":[]}],\"addressId\":\"" + address(token) + "\",\"paymentMethod\":\"CASH_ON_DELIVERY\"}";
        return JsonPath.read(body(send("POST", "/api/v1/food/orders", token, json, key).andExpect(status().isCreated())), "$.id");
    }

    private String foodBase() { return "/api/v1/partner/partners/" + partnerA + "/food"; }
    private String bookingBase() { return "/api/v1/partner/partners/" + partnerA + "/booking"; }

    private ResultActions setStatus(String token, String order, String to, String reason) throws Exception {
        return send("POST", foodBase() + "/orders/" + order + "/status", token,
                "{\"status\":\"" + to + "\"" + (reason == null ? "" : ",\"reason\":\"" + reason + "\"") + "}", null);
    }

    private int events(String order) {
        return db.queryForObject("select count(*) from transactions.food_order_events where order_id = ?::uuid", Integer.class, order);
    }

    // ---- access control ------------------------------------------------------------------------

    @Test
    void partnerEndpointsRejectCustomersAnonymousAndStrangers() throws Exception {
        send("GET", foodBase() + "/orders", null, null, null).andExpect(status().isUnauthorized());
        send("GET", foodBase() + "/orders", customer, null, null).andExpect(status().isForbidden());
        send("GET", bookingBase() + "/bookings", customer, null, null).andExpect(status().isForbidden());
        // Partner B is a partner, but not a member of partner A: 404, existence is not revealed.
        send("GET", foodBase() + "/orders", otherToken, null, null).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("PARTNER_NOT_FOUND"));
        send("GET", bookingBase() + "/bookings", otherToken, null, null).andExpect(status().isNotFound());
        send("GET", foodBase() + "/orders?scope=oops", ownerToken, null, null).andExpect(status().isBadRequest());
        send("GET", foodBase() + "/orders", ownerToken, null, null).andExpect(status().isOk());
    }

    @Test
    void anotherPartnerCannotReadOrActOnMyOrderEvenViaItsOwnPath() throws Exception {
        String order = placeOrder(customer, dishId("Плов с говядиной"), 1, "key-isolation-0001");
        UUID partnerB = db.queryForObject("select id from marketplace.partners where display_name like 'Демо-партнёр Б%'", UUID.class);
        String pathB = "/api/v1/partner/partners/" + partnerB + "/food";
        send("GET", pathB + "/orders/" + order, otherToken, null, null).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("ORDER_NOT_FOUND"));
        send("POST", pathB + "/orders/" + order + "/status", otherToken, "{\"status\":\"ACCEPTED\"}", null).andExpect(status().isNotFound());
        assertThat(body(send("GET", pathB + "/orders", otherToken, null, null).andExpect(status().isOk()))).isEqualTo("[]");
        assertThat(db.queryForObject("select status from transactions.food_orders where id = ?::uuid", String.class, order)).isEqualTo("PLACED");
        // The partner's own restaurant list does not leak to B either.
        send("GET", pathB + "/restaurants/" + restaurant + "/dishes", otherToken, null, null).andExpect(status().isNotFound());
        send("PATCH", pathB + "/restaurants/" + restaurant, otherToken, "{\"open\":false}", null).andExpect(status().isNotFound());
    }

    @Test
    void unapprovedPartnerAndRevokedStaffAreRefused() throws Exception {
        db.update("update marketplace.partners set verification_status = 'SUSPENDED' where id = ?", partnerA);
        send("GET", foodBase() + "/orders", ownerToken, null, null).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("PARTNER_NOT_APPROVED"));
        db.update("update marketplace.partners set verification_status = 'APPROVED' where id = ?", partnerA);
        send("GET", foodBase() + "/orders", ownerToken, null, null).andExpect(status().isOk());
        UUID owner = db.queryForObject("select user_id from marketplace.partner_staff where partner_id = ?", UUID.class, partnerA);
        db.update("update marketplace.partner_staff set status = 'REVOKED', revoked_by_user_id = ?, revoked_at = now() where partner_id = ?", owner, partnerA);
        send("GET", foodBase() + "/orders", ownerToken, null, null).andExpect(status().isNotFound());
    }

    @Test
    void operatorMayProcessButNotManage() throws Exception {
        String loginBody = loginBody("+77000000402");
        UUID operatorUser = db.queryForObject("select user_id from identity.phone_identities where phone_e164 = '+77000000402'", UUID.class);
        UUID owner = db.queryForObject("select user_id from marketplace.partner_staff where partner_id = ?", UUID.class, partnerA);
        db.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'OPERATOR', ?)", partnerA, operatorUser, owner);
        // Scope is derived at token issue: a refresh after the grant yields a token with kunde.partner.
        String token = JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}", null).andExpect(status().isOk())), "$.accessToken");
        send("GET", foodBase() + "/orders", token, null, null).andExpect(status().isOk());
        send("PATCH", foodBase() + "/restaurants/" + restaurant, token, "{\"open\":false}", null).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("PARTNER_ROLE_FORBIDDEN"));
        send("PUT", bookingBase() + "/venues/" + venue + "/masters/" + masterId() + "/hours", token, "{\"hours\":[]}", null)
                .andExpect(status().isForbidden());
    }

    // ---- food ----------------------------------------------------------------------------------

    @Test
    void orderAppearsForPartnerAndCustomerSeesEachStatusWithHistory() throws Exception {
        String order = placeOrder(customer, dishId("Плов с говядиной"), 2, "key-order-flow-0001");
        // A partner-managed order is not advanced by the DEV simulator, however long it waits inside the response window.
        db.update("update transactions.food_orders set placed_at = now() - interval '4 minutes' where id = ?::uuid", order);
        send("GET", "/api/v1/food/orders/" + order, customer, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PLACED")).andExpect(jsonPath("$.simulated").value(false))
                .andExpect(jsonPath("$.cancellable").value(true));

        String inbox = body(send("GET", foodBase() + "/orders", ownerToken, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(inbox, "$")).hasSize(1);
        assertThat((String) JsonPath.read(inbox, "$[0].order.id")).isEqualTo(order);
        assertThat((List<String>) JsonPath.read(inbox, "$[0].allowedNext")).containsExactly("ACCEPTED", "CANCELLED");
        assertThat((String) JsonPath.read(inbox, "$[0].customerRef")).hasSize(8);
        assertThat((String) JsonPath.read(inbox, "$[0].respondBy")).isNotBlank();
        assertThat((String) JsonPath.read(inbox, "$[0].reminderAt")).isNotBlank();

        setStatus(ownerToken, order, "ACCEPTED", null).andExpect(status().isOk()).andExpect(jsonPath("$.order.status").value("ACCEPTED"));
        int afterAccept = events(order);
        // Replaying the request does not duplicate the action.
        setStatus(ownerToken, order, "ACCEPTED", null).andExpect(status().isOk()).andExpect(jsonPath("$.order.status").value("ACCEPTED"));
        assertThat(events(order)).isEqualTo(afterAccept);
        send("GET", "/api/v1/food/orders/" + order, customer, null, null).andExpect(jsonPath("$.status").value("ACCEPTED"))
                .andExpect(jsonPath("$.cancellable").value(false));
        // Skipping a step or going backwards is refused by the server.
        setStatus(ownerToken, order, "DELIVERED", null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ORDER_TRANSITION_INVALID"));
        setStatus(ownerToken, order, "PLACED", null).andExpect(status().isBadRequest());
        // The customer cannot cancel any more (D-06).
        send("POST", "/api/v1/food/orders/" + order + "/cancel", customer, null, null).andExpect(status().isConflict());

        setStatus(ownerToken, order, "PREPARING", null).andExpect(status().isOk());
        setStatus(ownerToken, order, "ON_THE_WAY", null).andExpect(status().isOk());
        setStatus(ownerToken, order, "DELIVERED", null).andExpect(status().isOk());
        setStatus(ownerToken, order, "CANCELLED", "поздно отменять").andExpect(status().isConflict());

        String mine = body(send("GET", "/api/v1/food/orders/" + order, customer, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(mine, "$.status")).isEqualTo("DELIVERED");
        assertThat((List<String>) JsonPath.read(mine, "$.timeline[*].status"))
                .containsExactly("PLACED", "ACCEPTED", "PREPARING", "ON_THE_WAY", "DELIVERED");
        assertThat((List<String>) JsonPath.read(mine, "$.timeline[*].actor"))
                .containsExactly("CUSTOMER", "PARTNER", "PARTNER", "PARTNER", "PARTNER");
        // History scope contains it, the active inbox does not.
        assertThat((List<?>) JsonPath.read(body(send("GET", foodBase() + "/orders?scope=history", ownerToken, null, null)), "$")).hasSize(1);
        assertThat((List<?>) JsonPath.read(body(send("GET", foodBase() + "/orders", ownerToken, null, null)), "$")).isEmpty();
        // The audit trail names the acting staff user.
        assertThat(db.queryForObject("select count(*) from transactions.food_order_events where order_id = ?::uuid and actor_user_id is not null and actor_type = 'PARTNER'",
                Integer.class, order)).isEqualTo(4);
    }

    @Test
    void rejectNeedsAReasonVoidsPaymentRestoresStockAndCustomerSeesIt() throws Exception {
        String dish = dishId("Лагман");
        db.update("update marketplace.food_dishes set stock_qty = 5 where id = ?::uuid", dish);
        String order = placeOrder(customer, dish, 2, "key-order-reject-001");
        assertThat(db.queryForObject("select stock_qty from marketplace.food_dishes where id = ?::uuid", Integer.class, dish)).isEqualTo(3);
        setStatus(ownerToken, order, "CANCELLED", null).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("REASON_REQUIRED"));
        setStatus(ownerToken, order, "CANCELLED", "нет продуктов").andExpect(status().isOk())
                .andExpect(jsonPath("$.order.status").value("CANCELLED")).andExpect(jsonPath("$.order.cancelledBy").value("PARTNER"));
        int events = events(order);
        setStatus(ownerToken, order, "CANCELLED", "нет продуктов").andExpect(status().isOk());
        assertThat(events(order)).isEqualTo(events);
        assertThat(db.queryForObject("select stock_qty from marketplace.food_dishes where id = ?::uuid", Integer.class, dish)).isEqualTo(5);
        send("GET", "/api/v1/food/orders/" + order, customer, null, null).andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.paymentStatus").value("VOIDED")).andExpect(jsonPath("$.cancelReason").value("нет продуктов"))
                .andExpect(jsonPath("$.timeline[1].reason").value("нет продуктов"));
        setStatus(ownerToken, order, "ACCEPTED", null).andExpect(status().isConflict());
    }

    @Test
    void unansweredOrderIsCancelledBySystemAfterTheResponseWindow() throws Exception {
        UUID dishId = UUID.fromString(dishId("Лагман"));
        db.update("update marketplace.food_dishes set stock_qty = 5 where id = ?", dishId);
        String order = placeOrder(customer, dishId.toString(), 2, "key-order-timeout-01");
        db.update("update transactions.food_orders set placed_at = now() - interval '6 minutes' where id = ?::uuid", order);
        // The partner's late accept is refused: the system already cancelled and voided the order.
        setStatus(ownerToken, order, "ACCEPTED", null).andExpect(status().isConflict());
        send("GET", "/api/v1/food/orders/" + order, customer, null, null).andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.cancelledBy").value("SYSTEM")).andExpect(jsonPath("$.cancelReason").value("PARTNER_TIMEOUT"))
                .andExpect(jsonPath("$.paymentStatus").value("VOIDED"));
        assertThat(db.queryForObject("select stock_qty from marketplace.food_dishes where id = ?", Integer.class, dishId)).isEqualTo(5);
        assertThat(db.queryForObject("select count(*) from transactions.food_order_events where order_id = ?::uuid and actor_type = 'SYSTEM'",
                Integer.class, order)).isEqualTo(1);
        // Listing alone also applies the timeout, so the partner's inbox never shows an expired order as new.
        String second = placeOrder(customer, dishId("Самса с мясом"), 2, "key-order-timeout-02");
        db.update("update transactions.food_orders set placed_at = now() - interval '10 minutes' where id = ?::uuid", second);
        assertThat((List<?>) JsonPath.read(body(send("GET", foodBase() + "/orders", ownerToken, null, null)), "$")).isEmpty();
        assertThat(db.queryForObject("select status from transactions.food_orders where id = ?::uuid", String.class, second)).isEqualTo("CANCELLED");
    }

    @Test
    void customerCancelBeforeAcceptanceAndPartnerRaceLeaveOneOutcome() throws Exception {
        String order = placeOrder(customer, dishId("Самса с мясом"), 2, "key-order-race-0001");
        send("POST", "/api/v1/food/orders/" + order + "/cancel", customer, null, null).andExpect(status().isOk());
        setStatus(ownerToken, order, "ACCEPTED", null).andExpect(status().isConflict());
        assertThat(db.queryForObject("select cancelled_by from transactions.food_orders where id = ?::uuid", String.class, order)).isEqualTo("CUSTOMER");
    }

    @Test
    void availabilityAndStockChangesApplyToCustomersAndAreAudited() throws Exception {
        String dish = dishId("Компот");
        String list = body(send("GET", foodBase() + "/restaurants/" + restaurant + "/dishes", ownerToken, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(list, "$")).hasSize(5);
        send("PATCH", foodBase() + "/restaurants/" + restaurant + "/dishes/" + dish, ownerToken, "{\"available\":false,\"stockQty\":7}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.available").value(false)).andExpect(jsonPath("$.stockQty").value(7));
        send("PATCH", foodBase() + "/restaurants/" + restaurant + "/dishes/" + dish, ownerToken, "{\"stockQty\":-1}", null).andExpect(status().isBadRequest());
        send("PATCH", foodBase() + "/restaurants/" + restaurant + "/dishes/" + UUID.randomUUID(), ownerToken, "{\"available\":true}", null)
                .andExpect(status().isNotFound());
        // A customer cannot order an unavailable dish.
        String json = "{\"restaurantId\":\"" + restaurant + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":3,\"optionIds\":[]}]}";
        send("POST", "/api/v1/food/cart/quote", customer, json, null).andExpect(status().is4xxClientError());
        send("PATCH", foodBase() + "/restaurants/" + restaurant + "/dishes/" + dish, ownerToken, "{\"available\":true,\"clearStock\":true}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.stockQty").doesNotExist());
        send("POST", "/api/v1/food/cart/quote", customer, json, null).andExpect(status().isOk());
        // Repeating an identical change writes no new audit row.
        int audit = db.queryForObject("select count(*) from marketplace.partner_catalog_events", Integer.class);
        send("PATCH", foodBase() + "/restaurants/" + restaurant + "/dishes/" + dish, ownerToken, "{\"available\":true}", null).andExpect(status().isOk());
        assertThat(db.queryForObject("select count(*) from marketplace.partner_catalog_events", Integer.class)).isEqualTo(audit);
        assertThat(audit).isEqualTo(4);

        send("PATCH", foodBase() + "/restaurants/" + restaurant, ownerToken, "{\"open\":false}", null).andExpect(status().isOk())
                .andExpect(jsonPath("$.open").value(false));
    }

    @Test
    void restaurantsWithoutAPartnerKeepTheDevSimulation() throws Exception {
        UUID other = UUID.fromString(db.queryForObject("select id from marketplace.food_restaurants where slug = 'pizza-alatau'", String.class));
        String dish = db.queryForObject("select d.id from marketplace.food_dishes d where d.restaurant_id = ? and d.available and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = d.id and g.min_select > 0) order by d.price_minor desc limit 1", String.class, other);
        String json = "{\"restaurantId\":\"" + other + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":6,\"optionIds\":[]}],\"addressId\":\""
                + address(customer) + "\",\"paymentMethod\":\"CASH_ON_DELIVERY\"}";
        String id = JsonPath.read(body(send("POST", "/api/v1/food/orders", customer, json, "key-simulated-order-1").andExpect(status().isCreated())), "$.id");
        send("GET", "/api/v1/food/orders/" + id, customer, null, null).andExpect(jsonPath("$.simulated").value(true));
        assertThat((List<?>) JsonPath.read(body(send("GET", foodBase() + "/orders", ownerToken, null, null)), "$")).isEmpty();
    }

    // ---- booking -------------------------------------------------------------------------------

    private String masterId() {
        return db.queryForObject("select id from marketplace.booking_masters where venue_id = ?", String.class, venue);
    }

    private String serviceId(String name) {
        return db.queryForObject("select id from marketplace.booking_services where venue_id = ? and name = ?", String.class, venue, name);
    }

    private String tomorrow() { return LocalDate.now(ALMATY).plusDays(1).toString(); }

    private List<Map<String, Object>> slots(String service) throws Exception {
        return JsonPath.read(body(send("GET", "/api/v1/booking/slots?venueId=" + venue + "&serviceId=" + serviceId(service)
                + "&masterId=" + masterId() + "&date=" + tomorrow(), null, null, null).andExpect(status().isOk())), "$");
    }

    private ResultActions book(String token, String startsAt, String key) throws Exception {
        return send("POST", "/api/v1/booking/bookings", token, "{\"venueId\":\"" + venue + "\",\"serviceId\":\"" + serviceId("Мужская стрижка")
                + "\",\"masterId\":\"" + masterId() + "\",\"startsAt\":\"" + startsAt + "\",\"comment\":\"Тестовая запись\"}", key);
    }

    private ResultActions act(String token, String booking, String action, String reason) throws Exception {
        return send("POST", bookingBase() + "/bookings/" + booking + "/action", token,
                "{\"action\":\"" + action + "\"" + (reason == null ? "" : ",\"reason\":\"" + reason + "\"") + "}", null);
    }

    @Test
    void bookingRequestIsHeldConfirmedAndSeenByTheCustomer() throws Exception {
        var free = slots("Мужская стрижка");
        assertThat(free).isNotEmpty();
        String start = (String) free.get(0).get("startsAt");
        String created = body(book(customer, start, "key-booking-partner-001").andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("PENDING")).andExpect(jsonPath("$.confirmation").value("PARTNER"))
                .andExpect(jsonPath("$.cancellable").value(true)));
        String id = JsonPath.read(created, "$.id");
        // The request holds the slot: it is no longer offered and a second request is refused.
        assertThat(slots("Мужская стрижка").stream().map(s -> s.get("startsAt"))).doesNotContain(start);
        book(login("+77000000403"), start, "key-booking-partner-002").andExpect(status().isConflict());

        String inbox = body(send("GET", bookingBase() + "/bookings", ownerToken, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(inbox, "$")).hasSize(1);
        assertThat((List<String>) JsonPath.read(inbox, "$[0].allowedActions")).containsExactly("CONFIRM", "REJECT");
        assertThat((String) JsonPath.read(inbox, "$[0].serviceName")).isEqualTo("Мужская стрижка");
        assertThat((String) JsonPath.read(inbox, "$[0].comment")).isEqualTo("Тестовая запись");
        // Another partner cannot see or act on it.
        UUID partnerB = db.queryForObject("select id from marketplace.partners where display_name like 'Демо-партнёр Б%'", UUID.class);
        send("POST", "/api/v1/partner/partners/" + partnerB + "/booking/bookings/" + id + "/action", otherToken,
                "{\"action\":\"CONFIRM\"}", null).andExpect(status().isNotFound());

        act(ownerToken, id, "CONFIRM", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CONFIRMED"));
        int events = db.queryForObject("select count(*) from transactions.booking_events where booking_id = ?::uuid", Integer.class, id);
        act(ownerToken, id, "CONFIRM", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CONFIRMED"));
        assertThat(db.queryForObject("select count(*) from transactions.booking_events where booking_id = ?::uuid", Integer.class, id)).isEqualTo(events);
        act(ownerToken, id, "REJECT", "не подходит").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BOOKING_TRANSITION_INVALID"));
        act(ownerToken, id, "COMPLETE", null).andExpect(status().isConflict());
        send("GET", "/api/v1/booking/bookings/" + id, customer, null, null).andExpect(jsonPath("$.status").value("CONFIRMED"));
        assertThat((List<?>) JsonPath.read(body(send("GET", bookingBase() + "/bookings?scope=upcoming", ownerToken, null, null)), "$")).hasSize(1);

        // Partner cancels an upcoming confirmed booking with a reason: the slot is free again and the customer sees why.
        act(ownerToken, id, "CANCEL", null).andExpect(status().isBadRequest());
        act(ownerToken, id, "CANCEL", "мастер заболел").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        send("GET", "/api/v1/booking/bookings/" + id, customer, null, null).andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.cancelledBy").value("PARTNER")).andExpect(jsonPath("$.cancelReason").value("мастер заболел"));
        assertThat(slots("Мужская стрижка").stream().map(s -> s.get("startsAt"))).contains(start);
    }

    @Test
    void rejectFreesTheSlotAndCompletionFollowsTheVisit() throws Exception {
        var free = slots("Мужская стрижка");
        String id = JsonPath.read(body(book(customer, (String) free.get(0).get("startsAt"), "key-booking-reject-001").andExpect(status().isCreated())), "$.id");
        act(ownerToken, id, "REJECT", "нет времени").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        act(ownerToken, id, "REJECT", "нет времени").andExpect(status().isOk());
        act(ownerToken, id, "CONFIRM", null).andExpect(status().isConflict());
        assertThat(slots("Мужская стрижка")).hasSameSizeAs(free);

        // A past confirmed visit can be marked completed by the partner; a confirmed future one cannot.
        String id2 = JsonPath.read(body(book(customer, (String) free.get(1).get("startsAt"), "key-booking-complete-1").andExpect(status().isCreated())), "$.id");
        act(ownerToken, id2, "CONFIRM", null).andExpect(status().isOk());
        db.update("alter table transactions.bookings disable trigger user");
        db.update("update transactions.bookings set starts_at = now() - interval '30 minutes', ends_at = now() + interval '15 minutes' where id = ?::uuid", id2);
        send("GET", bookingBase() + "/bookings/" + id2, ownerToken, null, null).andExpect(jsonPath("$.allowedActions[0]").value("COMPLETE"));
        act(ownerToken, id2, "COMPLETE", null).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        act(ownerToken, id2, "COMPLETE", null).andExpect(status().isOk());
        act(ownerToken, id2, "CANCEL", "поздно").andExpect(status().isConflict());
    }

    @Test
    void unansweredRequestExpiresAtTheStartTime() throws Exception {
        var free = slots("Мужская стрижка");
        String id = JsonPath.read(body(book(customer, (String) free.get(0).get("startsAt"), "key-booking-expire-001").andExpect(status().isCreated())), "$.id");
        db.update("update transactions.bookings set starts_at = now() - interval '5 minutes', ends_at = now() + interval '40 minutes' where id = ?::uuid", id);
        send("GET", "/api/v1/booking/bookings/" + id, customer, null, null).andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.cancelledBy").value("SYSTEM"));
    }

    @Test
    void customerCanCancelAPendingRequest() throws Exception {
        var free = slots("Мужская стрижка");
        String id = JsonPath.read(body(book(customer, (String) free.get(0).get("startsAt"), "key-booking-custcancel1").andExpect(status().isCreated())), "$.id");
        send("POST", "/api/v1/booking/bookings/" + id + "/cancel", customer, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CANCELLED")).andExpect(jsonPath("$.cancelledBy").value("CUSTOMER"));
        act(ownerToken, id, "CONFIRM", null).andExpect(status().isConflict());
    }

    @Test
    void venuesWithoutAPartnerStillConfirmInstantly() throws Exception {
        UUID plain = UUID.fromString(db.queryForObject("select id from marketplace.booking_venues where slug = 'barber-alatau'", String.class));
        String service = db.queryForObject("select id from marketplace.booking_services where venue_id = ? and name = 'Мужская стрижка'", String.class, plain);
        String master = db.queryForObject("select m.id from marketplace.booking_masters m where m.venue_id = ? and m.name = 'Арман'", String.class, plain);
        var free = (List<Map<String, Object>>) JsonPath.read(body(send("GET", "/api/v1/booking/slots?venueId=" + plain + "&serviceId=" + service
                + "&masterId=" + master + "&date=" + tomorrow(), null, null, null)), "$");
        send("POST", "/api/v1/booking/bookings", customer, "{\"venueId\":\"" + plain + "\",\"serviceId\":\"" + service + "\",\"masterId\":\"" + master
                + "\",\"startsAt\":\"" + free.get(0).get("startsAt") + "\"}", "key-booking-plain-00001").andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("CONFIRMED")).andExpect(jsonPath("$.confirmation").value("DEV_MOCK"));
    }

    @Test
    void availabilityAndScheduleAreManagedWithConflictProtection() throws Exception {
        String masters = body(send("GET", bookingBase() + "/venues/" + venue + "/masters", ownerToken, null, null).andExpect(status().isOk()));
        assertThat((List<?>) JsonPath.read(masters, "$[0].hours")).hasSize(7);
        String hoursPath = bookingBase() + "/venues/" + venue + "/masters/" + masterId() + "/hours";
        // Book tomorrow's first slot; narrowing the day so that it no longer fits must be refused.
        var free = slots("Мужская стрижка");
        String start = (String) free.get(0).get("startsAt");
        book(customer, start, "key-booking-schedule-01").andExpect(status().isCreated());
        int weekday = LocalDate.now(ALMATY).plusDays(1).getDayOfWeek().getValue();
        String dayOff = "{\"hours\":[" + hoursJson(weekday == 1 ? 2 : 1) + "]}";   // every other weekday off, tomorrow off
        send("PUT", hoursPath, ownerToken, dayOff, null).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SCHEDULE_CONFLICT"));
        send("PUT", hoursPath, ownerToken, "{\"hours\":[{\"day\":" + weekday + ",\"from\":\"20:00\",\"to\":\"09:00\"}]}", null)
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("HOURS_INVALID"));
        // A schedule that still contains the booking is accepted and audited; slots follow it.
        send("PUT", hoursPath, ownerToken, "{\"hours\":[{\"day\":" + weekday + ",\"from\":\"09:00\",\"to\":\"20:00\"}]}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.hours.length()").value(1));
        assertThat(db.queryForObject("select count(*) from marketplace.partner_catalog_events where field = 'hours'", Integer.class)).isEqualTo(1);

        String service = serviceId("Оформление бороды");
        send("PATCH", bookingBase() + "/venues/" + venue + "/services/" + service, ownerToken, "{\"available\":false}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.available").value(false));
        String detail = body(send("GET", "/api/v1/booking/venues/" + venue, null, null, null).andExpect(status().isOk()));
        assertThat((List<Boolean>) JsonPath.read(detail, "$.services[*].available")).containsExactlyInAnyOrder(true, false);
        send("PATCH", bookingBase() + "/venues/" + venue + "/masters/" + masterId(), ownerToken, "{\"active\":false}", null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.active").value(false));
        send("PATCH", bookingBase() + "/venues/" + venue, ownerToken, "{\"open\":false}", null).andExpect(status().isOk());
        send("PATCH", bookingBase() + "/venues/" + UUID.randomUUID(), ownerToken, "{\"open\":false}", null).andExpect(status().isNotFound());
    }

    private static String hoursJson(int day) {
        return "{\"day\":" + day + ",\"from\":\"09:00\",\"to\":\"20:00\"}";
    }
}
