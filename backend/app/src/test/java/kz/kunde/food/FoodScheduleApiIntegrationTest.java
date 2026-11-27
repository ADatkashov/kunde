package kz.kunde.food;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;
import java.time.ZoneId;
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
 * Food restaurant location and weekly hours against PostgreSQL (Flyway V72): the schedule function at fixed instants
 * (open boundaries, overnight and 24:00 slots, no schedule = unrestricted), partner edit rules and isolation, effective
 * "closed outside hours" in the catalog and at checkout, straight-line distance, distance sort and filter, and the
 * idempotent synthetic location seed. Synthetic data only; rolls back.
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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000431",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FoodScheduleApiIntegrationTest {
    private static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;

    String owner;
    String otherOwner;
    String customer;
    UUID partner;
    UUID restaurant;
    UUID farRestaurant;

    @BeforeEach
    void seed() throws Exception {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000431')");
        FoodDemoSeeder seeder = new FoodDemoSeeder(db);
        for (String file : new String[] {"food/demo-catalog.json", "food/partner-demo-catalog.json"}) {
            try (var in = new ClassPathResource(file).getInputStream()) {
                seeder.seed(new ObjectMapper().readTree(in));
            }
        }
        partner = new PartnerOpsDemoSeeder(db, auth, env).seed();
        owner = login("+77000000002");
        otherOwner = login("+77000000003");
        customer = login("+77000000431");
        restaurant = UUID.fromString(db.queryForObject("select id from marketplace.food_restaurants where slug = 'partner-kitchen-demo'", String.class));
        farRestaurant = UUID.fromString(db.queryForObject(
                "select id from marketplace.food_restaurants where vertical = 'FOOD' and id <> ? order by slug limit 1", String.class, restaurant));
        db.update("update marketplace.food_restaurants set min_order_minor = 0, is_open = true where id in (?, ?)", restaurant, farRestaurant);
    }

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
            case "PUT" -> put(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        return http.perform(request);
    }

    private String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return JsonPath.read(body(send("POST", "/api/v1/auth/otp/verify", null,
                "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}").andExpect(status().isOk())), "$.accessToken");
    }

    private String base() { return "/api/v1/partner/partners/" + partner + "/food/restaurants/" + restaurant; }

    private boolean inHours(UUID id, String localDateTime) {
        return Boolean.TRUE.equals(db.queryForObject(
                "select marketplace.food_in_hours_at(?, (?::timestamp) at time zone 'Asia/Almaty')", Boolean.class, id, localDateTime));
    }

    private static String slot(int day, String opens, String closes) {
        return "{\"dayOfWeek\":" + day + ",\"opensAt\":\"" + opens + "\",\"closesAt\":\"" + closes + "\"}";
    }

    private String hours(String... slots) { return "{\"hours\":[" + String.join(",", slots) + "]}"; }

    private String quote() throws Exception {
        String dish = db.queryForObject("select id from marketplace.food_dishes where restaurant_id = ? and available "
                + "and not exists (select 1 from marketplace.food_option_groups g where g.dish_id = food_dishes.id and g.min_select > 0) limit 1",
                String.class, restaurant);
        return "{\"restaurantId\":\"" + restaurant + "\",\"items\":[{\"dishId\":\"" + dish + "\",\"quantity\":1,\"optionIds\":[]}],"
                + "\"fulfillmentType\":\"PICKUP\",\"paymentMethod\":\"TEST_CARD\"}";
    }

    @Test
    void scheduleFunctionHonoursBoundariesOvernightAndFullDaySlots() throws Exception {
        assertThat(inHours(restaurant, "2026-11-23 03:00")).as("no schedule means unrestricted").isTrue();

        send("PUT", base() + "/hours", owner, hours(slot(1, "10:00", "22:00"), slot(5, "18:00", "02:00"), slot(7, "00:00", "24:00")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.hours.length()").value(3));

        // 2026-11-23 is a Monday.
        assertThat(inHours(restaurant, "2026-11-23 09:59")).isFalse();
        assertThat(inHours(restaurant, "2026-11-23 10:00")).isTrue();
        assertThat(inHours(restaurant, "2026-11-23 21:59")).isTrue();
        assertThat(inHours(restaurant, "2026-11-23 22:00")).isFalse();
        assertThat(inHours(restaurant, "2026-11-24 12:00")).as("no Tuesday slot").isFalse();
        // Friday 18:00 - Saturday 02:00 (overnight).
        assertThat(inHours(restaurant, "2026-11-27 17:59")).isFalse();
        assertThat(inHours(restaurant, "2026-11-27 18:00")).isTrue();
        assertThat(inHours(restaurant, "2026-11-27 23:59")).isTrue();
        assertThat(inHours(restaurant, "2026-11-28 01:59")).isTrue();
        assertThat(inHours(restaurant, "2026-11-28 02:00")).isFalse();
        assertThat(inHours(restaurant, "2026-11-28 18:00")).as("overnight slot does not repeat on Saturday").isFalse();
        // Sunday is open all day; Monday 00:00 is closed again (Monday slot starts at 10:00, Sunday ends at 24:00).
        assertThat(inHours(restaurant, "2026-11-29 00:00")).isTrue();
        assertThat(inHours(restaurant, "2026-11-29 23:59")).isTrue();
        assertThat(inHours(restaurant, "2026-11-30 00:00")).isFalse();

        // Clearing the schedule removes the restriction again.
        send("PUT", base() + "/hours", owner, hours()).andExpect(status().isOk()).andExpect(jsonPath("$.hours.length()").value(0));
        assertThat(inHours(restaurant, "2026-11-24 03:00")).isTrue();
    }

    @Test
    void partnerHoursAreValidatedAuditedAndIsolated() throws Exception {
        for (String bad : new String[] {hours(slot(8, "10:00", "22:00")), hours(slot(0, "10:00", "22:00")),
                hours(slot(1, "25:00", "22:00")), hours(slot(1, "10:00", "22:60")), hours(slot(1, "10:00", "10:00")),
                hours(slot(1, "24:00", "02:00")), hours(slot(1, "10:00", "12:00"), slot(1, "10:00", "14:00")), "{\"hours\":null}"}) {
            send("PUT", base() + "/hours", owner, bad).andExpect(status().isBadRequest());
        }
        assertThat(db.queryForObject("select count(*) from marketplace.food_restaurant_hours where restaurant_id = ?", Integer.class, restaurant)).isZero();

        send("PUT", base() + "/hours", owner, hours(slot(2, "09:00", "21:30"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.hours[0].opensAt").value("09:00")).andExpect(jsonPath("$.hours[0].closesAt").value("21:30"));
        send("PUT", base() + "/hours", owner, hours(slot(2, "09:00", "24:00"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.hours[0].closesAt").value("24:00"));

        // Another partner, a customer and an anonymous caller cannot change it; the data stays.
        assertThat(body(send("PUT", base() + "/hours", otherOwner, hours(slot(3, "01:00", "02:00")))
                .andExpect(status().is4xxClientError()))).doesNotContain("01:00");
        send("PUT", base() + "/hours", customer, hours(slot(3, "01:00", "02:00"))).andExpect(status().isForbidden());
        send("PUT", base() + "/hours", null, hours()).andExpect(status().isUnauthorized());
        assertThat(db.queryForObject("select count(*) from marketplace.food_restaurant_hours where restaurant_id = ?", Integer.class, restaurant)).isEqualTo(1);
        assertThat(db.queryForObject("select count(*) from marketplace.partner_catalog_events where entity_id = ? and field = 'hours'", Integer.class, restaurant))
                .isEqualTo(2);
        send("GET", base() + "/schedule", otherOwner, null).andExpect(status().is4xxClientError());
        send("GET", base() + "/schedule", owner, null).andExpect(status().isOk()).andExpect(jsonPath("$.hours.length()").value(1));
    }

    @Test
    void closedOutsideHoursEverywhereAndOpenInsideThem() throws Exception {
        int tomorrow = LocalDate.now(ALMATY).plusDays(1).getDayOfWeek().getValue();
        send("PUT", base() + "/hours", owner, hours(slot(tomorrow, "10:00", "11:00"))).andExpect(status().isOk())
                .andExpect(jsonPath("$.openNow").value(false));
        send("GET", "/api/v1/food/restaurants/" + restaurant, null, null).andExpect(status().isOk())
                .andExpect(jsonPath("$.restaurant.open").value(false)).andExpect(jsonPath("$.hours[0].dayOfWeek").value(tomorrow));
        List<String> openIds = JsonPath.read(body(send("GET", "/api/v1/food/restaurants?openNow=true&limit=100", null, null).andExpect(status().isOk())), "$[*].id");
        assertThat(openIds).doesNotContain(restaurant.toString()).contains(farRestaurant.toString());
        send("POST", "/api/v1/food/cart/quote", customer, quote()).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("RESTAURANT_CLOSED"));

        StringBuilder week = new StringBuilder();
        String[] days = new String[7];
        for (int d = 1; d <= 7; d++) { days[d - 1] = slot(d, "00:00", "24:00"); }
        send("PUT", base() + "/hours", owner, hours(days)).andExpect(status().isOk()).andExpect(jsonPath("$.openNow").value(true));
        send("POST", "/api/v1/food/cart/quote", customer, quote()).andExpect(status().isOk());

        // The manual switch still wins inside the schedule.
        db.update("update marketplace.food_restaurants set is_open = false where id = ?", restaurant);
        send("POST", "/api/v1/food/cart/quote", customer, quote()).andExpect(status().isConflict());
    }

    @Test
    void distanceIsStraightLineSortableAndFilterable() throws Exception {
        // Origin: centre of Almaty. Near point ~1 km east, far point ~20 km north-east. Nothing is invented without coordinates.
        send("PUT", base() + "/location", owner, "{\"latitude\":43.2389,\"longitude\":76.9017}").andExpect(status().isOk())
                .andExpect(jsonPath("$.latitude").value(43.2389));
        db.update("update marketplace.food_restaurants set latitude = 43.4, longitude = 77.1 where id = ?", farRestaurant);
        db.update("update marketplace.food_restaurants set latitude = null, longitude = null where id not in (?, ?)", restaurant, farRestaurant);

        double expectedNear = haversine(43.2389, 76.8897, 43.2389, 76.9017);
        double expectedFar = haversine(43.2389, 76.8897, 43.4, 77.1);
        String list = body(send("GET", "/api/v1/food/restaurants?lat=43.2389&lon=76.8897&sort=distance&limit=100", null, null).andExpect(status().isOk()));
        List<String> ids = JsonPath.read(list, "$[*].id");
        assertThat(((Number) ((List<?>) JsonPath.read(list, "$[?(@.id=='" + restaurant + "')].distanceMeters")).get(0)).doubleValue())
                .isCloseTo(expectedNear, org.assertj.core.data.Offset.offset(2.0));
        assertThat(((Number) ((List<?>) JsonPath.read(list, "$[?(@.id=='" + farRestaurant + "')].distanceMeters")).get(0)).doubleValue())
                .isCloseTo(expectedFar, org.assertj.core.data.Offset.offset(2.0));
        assertThat(ids.indexOf(restaurant.toString())).isLessThan(ids.indexOf(farRestaurant.toString()));
        List<Object> unknown = JsonPath.read(list, "$[?(@.id!='" + restaurant + "' && @.id!='" + farRestaurant + "')].distanceMeters");
        assertThat(unknown).as("restaurants without coordinates get no distance").allMatch(java.util.Objects::isNull);
        assertThat(ids.indexOf(farRestaurant.toString())).isLessThan(ids.size() - unknown.size() + 1);

        List<String> within = JsonPath.read(body(send("GET", "/api/v1/food/restaurants?lat=43.2389&lon=76.8897&maxDistanceMeters=3000", null, null)
                .andExpect(status().isOk())), "$[*].id");
        assertThat(within).containsExactly(restaurant.toString());

        // Without a location the field is simply absent and the feature is refused instead of guessed.
        assertThat(body(send("GET", "/api/v1/food/restaurants", null, null))).doesNotContain("\"distanceMeters\":1").contains("\"distanceMeters\":null");
        send("GET", "/api/v1/food/restaurants?sort=distance", null, null).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("LOCATION_REQUIRED"));
        send("GET", "/api/v1/food/restaurants?maxDistanceMeters=500", null, null).andExpect(status().isBadRequest());
        send("GET", "/api/v1/food/restaurants?lat=43.2", null, null).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("LOCATION_INVALID"));
        send("GET", "/api/v1/food/restaurants?lat=91&lon=76", null, null).andExpect(status().isBadRequest());

        // Location edits: pairs only, range checked, null pair forgets the location.
        send("PUT", base() + "/location", owner, "{\"latitude\":43.2}").andExpect(status().isBadRequest());
        send("PUT", base() + "/location", owner, "{\"latitude\":95,\"longitude\":76}").andExpect(status().isBadRequest());
        send("PUT", base() + "/location", otherOwner, "{\"latitude\":43.2,\"longitude\":76.8}").andExpect(status().is4xxClientError());
        send("PUT", base() + "/location", owner, "{}").andExpect(status().isOk()).andExpect(jsonPath("$.latitude").doesNotExist());
    }

    @Test
    void syntheticLocationSeedIsDeterministicAndIdempotent() {
        FoodDemoSeeder seeder = new FoodDemoSeeder(db);
        db.update("update marketplace.food_restaurants set latitude = null, longitude = null");
        db.update("update marketplace.food_restaurants set is_synthetic = false where id = ?", farRestaurant);
        seeder.seedLocations();
        assertThat(db.queryForObject("select count(*) from marketplace.food_restaurants where is_synthetic and latitude is null", Integer.class)).isZero();
        assertThat(db.queryForObject("select latitude is null from marketplace.food_restaurants where id = ?", Boolean.class, farRestaurant))
                .as("non-synthetic rows are never given invented coordinates").isTrue();
        assertThat(db.queryForObject("select count(*) from marketplace.food_restaurants where is_synthetic and (abs(latitude - 43.2389) > 0.06 or abs(longitude - 76.8897) > 0.06)", Integer.class)).isZero();
        List<String> first = db.queryForList("select latitude || ',' || longitude from marketplace.food_restaurants where latitude is not null order by slug", String.class);
        seeder.seedLocations();
        assertThat(db.queryForList("select latitude || ',' || longitude from marketplace.food_restaurants where latitude is not null order by slug", String.class)).isEqualTo(first);
    }

    private static double haversine(double lat1, double lon1, double lat2, double lon2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.pow(Math.sin(dLat / 2), 2) + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLon / 2), 2);
        return 2 * 6371000 * Math.asin(Math.sqrt(a));
    }
}
