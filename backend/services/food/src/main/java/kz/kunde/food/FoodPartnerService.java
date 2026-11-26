package kz.kunde.food;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.food.FoodOrderService.OrderView;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Partner operations for Food/Grocery: incoming orders of the partner's own restaurants and their catalog availability.
 * Every call first resolves the caller's membership of the path partner (404 for strangers) and then only touches rows
 * whose restaurant belongs to that partner, so another partner's order or dish is indistinguishable from a missing one.
 * Status changes are validated here (server-side state machine), serialized by a row lock, idempotent (repeating the
 * already reached status changes nothing) and recorded in the append-only order event log with the acting user.
 */
@Service
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodPartnerService {
    /** Allowed partner transitions. CANCELLED (rejection) additionally needs a reason. */
    private static final Map<String, List<String>> NEXT_DELIVERY = Map.of(
            "PLACED", List.of("ACCEPTED", "CANCELLED"),
            "ACCEPTED", List.of("PREPARING", "CANCELLED"),
            "PREPARING", List.of("READY_FOR_PICKUP", "ON_THE_WAY", "CANCELLED"),
            "READY_FOR_PICKUP", List.of("ON_THE_WAY", "CANCELLED"),
            "ON_THE_WAY", List.of("DELIVERED"));
    /** Pickup: the customer collects the order, so there is no courier leg; DELIVERED means "handed over". */
    private static final Map<String, List<String>> NEXT_PICKUP = Map.of(
            "PLACED", List.of("ACCEPTED", "CANCELLED"),
            "ACCEPTED", List.of("PREPARING", "CANCELLED"),
            "PREPARING", List.of("READY_FOR_PICKUP", "CANCELLED"),
            "READY_FOR_PICKUP", List.of("DELIVERED", "CANCELLED"));

    /** Groceries delivery: the store only prepares and hands over; a courier collects (ON_THE_WAY) and delivers (DELIVERED). */
    private static final Map<String, List<String>> NEXT_GROCERY_DELIVERY = Map.of(
            "PLACED", List.of("ACCEPTED", "CANCELLED"),
            "ACCEPTED", List.of("PREPARING", "CANCELLED"),
            "PREPARING", List.of("READY_FOR_PICKUP", "CANCELLED"),
            "READY_FOR_PICKUP", List.of("CANCELLED"));

    private static List<String> next(String status, String type, String vertical) {
        if ("GROCERY".equals(vertical) && !"PICKUP".equals(type)) {
            return NEXT_GROCERY_DELIVERY.getOrDefault(status, List.of());
        }
        return ("PICKUP".equals(type) ? NEXT_PICKUP : NEXT_DELIVERY).getOrDefault(status, List.of());
    }

    public record PartnerOrder(OrderView order, String customerRef, List<String> allowedNext, OffsetDateTime respondBy,
            OffsetDateTime reminderAt) {}

    public record RestaurantView(String id, String name, String vertical, boolean open, boolean synthetic,
            boolean pickupEnabled, int prepMinutes, int etaMinMinutes, int etaMaxMinutes, long deliveryFeeMinor,
            long minOrderMinor, String addressText, String description) {}

    public record RestaurantUpdate(Boolean open, Boolean pickupEnabled, Integer prepMinutes, Integer etaMinMinutes,
            Integer etaMaxMinutes, Long deliveryFeeMinor, Long minOrderMinor, String addressText, String description) {}

    public record Summary(long ordersToday, long activeOrders, long deliveredToday, long cancelledToday, long revenueTodayMinor,
            long revenue7dMinor, long orders7d, Double ratingAvg, int ratingCount, List<Day> perDay) {}

    public record Day(java.time.LocalDate day, long orders, long revenueMinor) {}

    public record Photo(String id, String url) {}

    /** Product card of the partner app. The Groceries fields are null for restaurant dishes that never set them. */
    public record DishView(String id, String name, String section, long priceMinor, boolean available, Integer stockQty,
            String unit, String sectionId, String description, String groceryCategory, String brand, String originCountry,
            String composition, String storageConditions, Integer kcal, Double protein, Double fat, Double carbs,
            Long compareAtPriceMinor, List<Photo> photos) {}

    /** Groceries product attributes; a null field is left alone, the clear flags remove a stored value. */
    public record ProductAttributes(String groceryCategory, String brand, String originCountry, String composition,
            String storageConditions, Integer kcal, Double protein, Double fat, Double carbs, Long compareAtPriceMinor,
            boolean clearCompareAt, boolean clearCategory) {}

    private final JdbcTemplate db;
    private final FoodOrderService orders;
    private final PartnerService partners;
    private final FoodCourierService couriers;

    public FoodPartnerService(JdbcTemplate db, FoodOrderService orders, PartnerService partners, FoodCourierService couriers) {
        this.couriers = couriers;
        this.db = db;
        this.orders = orders;
        this.partners = partners;
    }

    // ---- orders --------------------------------------------------------------------------------

    /** {@code scope}: "active" (default, needs action or in progress) or "history" (delivered/cancelled). */
    @Transactional
    public List<PartnerOrder> list(UUID actor, UUID partnerId, String scope, int limit, int offset) {
        partners.requireProcessing(actor, partnerId);
        orders.expireUnanswered(partnerId);
        boolean history = "history".equals(scope);
        List<UUID> ids = db.queryForList("""
                select id from transactions.food_orders where partner_id = ? and (status in ('PLACED','ACCEPTED','PREPARING','READY_FOR_PICKUP','ON_THE_WAY')) <> ?
                order by case when status = 'PLACED' then 0 else 1 end, placed_at desc, id limit ? offset ?
                """, UUID.class, partnerId, history, limit, offset);
        return wrap(ids);
    }

    @Transactional
    public PartnerOrder get(UUID actor, UUID partnerId, UUID orderId) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedOrder(partnerId, orderId);
        orders.expireUnanswered(partnerId);
        return wrap(List.of(orderId)).get(0);
    }

    /**
     * Moves the order to {@code to}. Repeating a request whose target equals the current status is a no-op returning the
     * current state (safe for retries); any other illegal move is 409 and leaves the order untouched.
     */
    @Transactional
    public PartnerOrder transition(UUID actor, UUID partnerId, UUID orderId, String to, String reason) {
        partners.requireProcessing(actor, partnerId);
        orders.expireUnanswered(partnerId);
        String[] state = db.query("select status, fulfillment_type, vertical from transactions.food_orders where id = ? and partner_id = ? for update",
                (rs, n) -> new String[] {rs.getString(1), rs.getString(2), rs.getString(3)}, orderId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        String status = state[0];
        String clean = reason == null || reason.isBlank() ? null : reason.strip();
        if (to.equals(status)) {
            return wrap(List.of(orderId)).get(0);
        }
        if (!next(status, state[1], state[2]).contains(to)) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_TRANSITION_INVALID",
                    "The order cannot move from " + status + " to " + to);
        }
        if (("READY_FOR_PICKUP".equals(to) || "ON_THE_WAY".equals(to)) && orders.interactivePicking(orderId) && orders.pickingOpen(orderId)) {
            throw new ApiException(HttpStatus.CONFLICT, "PICKING_INCOMPLETE",
                    "Every line must be picked, replaced or marked missing, and replacements need the customer's answer");
        }
        if ("CANCELLED".equals(to) && (clean == null || clean.length() < 3 || clean.length() > 300)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of 3-300 characters is required");
        }
        if ("CANCELLED".equals(to)) {
            db.update("""
                    update transactions.food_orders set status = 'CANCELLED', payment_status = case when payment_method = 'DEV_NO_PAYMENT' then 'NO_PAYMENT' else 'VOIDED' end, cancelled_by = 'PARTNER',
                        cancel_reason = ?, updated_at = now(), version = version + 1 where id = ?
                    """, clean, orderId);
            orders.restoreStock(orderId);
        } else {
            db.update("update transactions.food_orders set status = ?, updated_at = now(), version = version + 1 where id = ?",
                    to, orderId);
        }
        db.update("""
                insert into transactions.food_order_events (order_id, status, actor_type, actor_user_id, reason)
                values (?, ?, 'PARTNER', ?, ?)
                """, orderId, to, actor, "CANCELLED".equals(to) ? clean : null);
        boolean groceryDelivery = "GROCERY".equals(state[2]) && !"PICKUP".equals(state[1]);
        if (groceryDelivery && "READY_FOR_PICKUP".equals(to)) { couriers.openTask(orderId); }
        if (groceryDelivery && "CANCELLED".equals(to)) { couriers.cancel(orderId); }
        if ("PREPARING".equals(to) && !orders.interactivePicking(orderId)) {
            // The store collects the order: unavailable products are replaced or removed per the customer's choice.
            orders.resolveLines(orderId, OffsetDateTime.now());
        }
        return wrap(List.of(orderId)).get(0);
    }

    /** Picking of one line (PICKED, MISSING, REPLACE) by the store that owns the order. */
    @Transactional
    public PartnerOrder pick(UUID actor, UUID partnerId, UUID orderId, UUID itemId, String action, UUID replacementDishId) {
        partners.requireProcessing(actor, partnerId);
        orders.pickItem(partnerId, orderId, itemId, action, replacementDishId);
        return wrap(List.of(orderId)).get(0);
    }

    void requireAccess(UUID actor, UUID partnerId) { partners.requireProcessing(actor, partnerId); }

    void requireManager(UUID actor, UUID partnerId) { partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER); }

    void requireOwnedRestaurantFor(UUID actor, UUID partnerId, UUID restaurantId) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedRestaurant(partnerId, restaurantId);
    }

    // ---- catalog / availability ----------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<RestaurantView> restaurants(UUID actor, UUID partnerId) {
        partners.requireProcessing(actor, partnerId);
        return db.query("""
                select id, name, vertical, is_open, is_synthetic, pickup_enabled, prep_minutes, eta_min_minutes,
                       eta_max_minutes, delivery_fee_minor, min_order_minor, address_text, description
                from marketplace.food_restaurants
                where partner_id = ? order by sort_order, name
                """, (rs, n) -> new RestaurantView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getBoolean(4),
                rs.getBoolean(5), rs.getBoolean(6), rs.getInt(7), rs.getInt(8), rs.getInt(9), rs.getLong(10), rs.getLong(11),
                rs.getString(12), rs.getString(13)), partnerId);
    }

    /** Owner/Manager edits the restaurant profile and ordering conditions; every changed field is audited. */
    @Transactional
    public RestaurantView updateRestaurant(UUID actor, UUID partnerId, UUID restaurantId, RestaurantUpdate u) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        var cur = db.query("""
                select is_open, pickup_enabled, prep_minutes, eta_min_minutes, eta_max_minutes, delivery_fee_minor, min_order_minor,
                       address_text, description, moderation_status from marketplace.food_restaurants where id = ? and partner_id = ? for update""",
                (rs, n) -> new Object[] {rs.getBoolean(1), rs.getBoolean(2), rs.getInt(3), rs.getInt(4), rs.getInt(5), rs.getLong(6),
                        rs.getLong(7), rs.getString(8), rs.getString(9), rs.getString(10)}, restaurantId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant not found"));
        if (Boolean.TRUE.equals(u.open()) && "BLOCKED".equals(cur[9])) {
            throw new ApiException(HttpStatus.CONFLICT, "RESTAURANT_BLOCKED", "The restaurant was blocked by an administrator");
        }
        boolean open = u.open() != null ? u.open() : (boolean) cur[0];
        boolean pickup = u.pickupEnabled() != null ? u.pickupEnabled() : (boolean) cur[1];
        int prep = u.prepMinutes() != null ? u.prepMinutes() : (int) cur[2];
        int etaMin = u.etaMinMinutes() != null ? u.etaMinMinutes() : (int) cur[3];
        int etaMax = u.etaMaxMinutes() != null ? u.etaMaxMinutes() : (int) cur[4];
        long fee = u.deliveryFeeMinor() != null ? u.deliveryFeeMinor() : (long) cur[5];
        long min = u.minOrderMinor() != null ? u.minOrderMinor() : (long) cur[6];
        String address = u.addressText() != null ? u.addressText().strip() : (String) cur[7];
        String description = u.description() != null ? u.description().strip() : (String) cur[8];
        if (prep < 1 || prep > 240 || etaMin < 1 || etaMax < etaMin || etaMax > 240 || fee < 0 || fee > 10_000_000
                || min < 0 || min > 100_000_000 || (address != null && address.length() > 300)
                || (description != null && description.length() > 500)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "RESTAURANT_SETTINGS_INVALID", "Invalid restaurant settings");
        }
        if (address != null && address.isEmpty()) { address = null; }
        db.update("""
                update marketplace.food_restaurants set is_open = ?, pickup_enabled = ?, prep_minutes = ?, eta_min_minutes = ?,
                    eta_max_minutes = ?, delivery_fee_minor = ?, min_order_minor = ?, address_text = ?, description = ?
                where id = ?""", open, pickup, prep, etaMin, etaMax, fee, min, address, description == null ? "" : description, restaurantId);
        String[] names = {"open", "pickup_enabled", "prep_minutes", "eta_min", "eta_max", "delivery_fee", "min_order", "address", "description"};
        Object[] after = {open, pickup, prep, etaMin, etaMax, fee, min, address, description};
        for (int i = 0; i < names.length; i++) {
            if (!java.util.Objects.equals(cur[i], after[i] == null ? "" : after[i]) && !(cur[i] == null && after[i] == null)) {
                audit(partnerId, actor, "RESTAURANT", restaurantId, names[i], String.valueOf(cur[i]), String.valueOf(after[i]));
            }
        }
        return restaurants(actor, partnerId).stream().filter(r -> r.id().equals(restaurantId.toString())).findFirst().orElseThrow();
    }

    /** Dashboard numbers from real orders (Asia/Almaty days). Revenue counts delivered orders at their final total. */
    @Transactional(readOnly = true)
    public Summary summary(UUID actor, UUID partnerId) {
        partners.requireProcessing(actor, partnerId);
        long[] t = db.query("""
                select count(*) filter (where (placed_at at time zone 'Asia/Almaty')::date = (now() at time zone 'Asia/Almaty')::date),
                       count(*) filter (where status in ('PLACED','ACCEPTED','PREPARING','READY_FOR_PICKUP','ON_THE_WAY')),
                       count(*) filter (where status = 'DELIVERED' and (placed_at at time zone 'Asia/Almaty')::date = (now() at time zone 'Asia/Almaty')::date),
                       count(*) filter (where status = 'CANCELLED' and (placed_at at time zone 'Asia/Almaty')::date = (now() at time zone 'Asia/Almaty')::date),
                       coalesce(sum(coalesce(final_total_minor, total_minor)) filter (where status = 'DELIVERED' and (placed_at at time zone 'Asia/Almaty')::date = (now() at time zone 'Asia/Almaty')::date), 0),
                       coalesce(sum(coalesce(final_total_minor, total_minor)) filter (where status = 'DELIVERED' and placed_at > now() - interval '7 days'), 0),
                       count(*) filter (where placed_at > now() - interval '7 days')
                from transactions.food_orders where partner_id = ?""", (rs, n) -> {
            long[] a = new long[7];
            for (int i = 0; i < 7; i++) { a[i] = rs.getLong(i + 1); }
            return a;
        }, partnerId).get(0);
        var rating = db.query("""
                select round(avg(v.rating)::numeric, 1)::float8, count(*) from marketplace.food_reviews v
                join marketplace.food_restaurants r on r.id = v.restaurant_id
                where r.partner_id = ? and v.status = 'VISIBLE'""",
                (rs, n) -> new Object[] {rs.getObject(1, Double.class), rs.getInt(2)}, partnerId).get(0);
        List<Day> perDay = db.query("""
                select g::date, count(o.id), coalesce(sum(coalesce(o.final_total_minor, o.total_minor)) filter (where o.status = 'DELIVERED'), 0)
                from generate_series((now() at time zone 'Asia/Almaty')::date - 6, (now() at time zone 'Asia/Almaty')::date, interval '1 day') g
                left join transactions.food_orders o on o.partner_id = ? and (o.placed_at at time zone 'Asia/Almaty')::date = g::date
                group by g order by g""", (rs, n) -> new Day(rs.getDate(1).toLocalDate(), rs.getLong(2), rs.getLong(3)), partnerId);
        return new Summary(t[0], t[1], t[2], t[3], t[4], t[5], t[6], (Double) rating[0], (int) rating[1], perDay);
    }

    @Transactional
    public RestaurantView setOpen(UUID actor, UUID partnerId, UUID restaurantId, boolean open) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        Boolean previous = db.query("select is_open from marketplace.food_restaurants where id = ? and partner_id = ? for update",
                (rs, n) -> rs.getBoolean(1), restaurantId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant not found"));
        if (previous != open) {
            db.update("update marketplace.food_restaurants set is_open = ? where id = ?", open, restaurantId);
            audit(partnerId, actor, "RESTAURANT", restaurantId, "open", String.valueOf(previous), String.valueOf(open));
        }
        return restaurants(actor, partnerId).stream().filter(r -> r.id().equals(restaurantId.toString())).findFirst().orElseThrow();
    }

    @Transactional(readOnly = true)
    public List<DishView> dishes(UUID actor, UUID partnerId, UUID restaurantId) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedRestaurant(partnerId, restaurantId);
        java.util.Map<String, List<Photo>> photos = new java.util.HashMap<>();
        db.query("""
                select p.dish_id, p.id, p.url from marketplace.food_dish_photos p
                join marketplace.food_dishes d on d.id = p.dish_id where d.restaurant_id = ? order by p.sort_order, p.created_at, p.id
                """, rs -> {
                    photos.computeIfAbsent(rs.getString(1), k -> new java.util.ArrayList<>()).add(new Photo(rs.getString(2), rs.getString(3)));
                }, restaurantId);
        return db.query("""
                select d.id, d.name, s.name, d.price_minor, d.available, d.stock_qty, d.unit, s.id, d.description,
                       d.grocery_category, d.brand, d.origin_country, d.composition, d.storage_conditions, d.kcal_100,
                       d.protein_100, d.fat_100, d.carbs_100, d.compare_at_price_minor
                from marketplace.food_dishes d join marketplace.food_menu_sections s on s.id = d.section_id
                where d.restaurant_id = ? order by s.sort_order, d.sort_order, d.name
                """, (rs, n) -> new DishView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getLong(4),
                rs.getBoolean(5), rs.getObject(6, Integer.class), rs.getString(7), rs.getString(8), rs.getString(9),
                rs.getString(10), rs.getString(11), rs.getString(12), rs.getString(13), rs.getString(14),
                rs.getObject(15, Integer.class), dbl(rs.getBigDecimal(16)), dbl(rs.getBigDecimal(17)), dbl(rs.getBigDecimal(18)),
                rs.getObject(19, Long.class), photos.getOrDefault(rs.getString(1), List.of())), restaurantId);
    }

    private static Double dbl(java.math.BigDecimal v) { return v == null ? null : v.doubleValue(); }

    /** Availability and the stock counter only; names and prices stay with the existing offering flow. */
    @Transactional
    public DishView updateDish(UUID actor, UUID partnerId, UUID restaurantId, UUID dishId, Boolean available,
            Integer stockQty, boolean clearStock, String name, String description, Long priceMinor) {
        boolean content = name != null || description != null || priceMinor != null;
        // Menu content (name, description, price) is a manager decision; availability and stock stay open to operators.
        if (content) {
            partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        } else {
            partners.requireProcessing(actor, partnerId);
        }
        requireOwnedRestaurant(partnerId, restaurantId);
        String cleanName = name == null ? null : validName(name);
        String cleanDescription = description == null ? null : validDescription(description);
        if (priceMinor != null) { validPrice(priceMinor); }
        if (stockQty != null && (clearStock || stockQty < 0 || stockQty > 100000)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "STOCK_INVALID", "Stock must be 0-100000, or cleared");
        }
        var row = db.query("""
                select available, stock_qty, name, description, price_minor from marketplace.food_dishes where id = ? and restaurant_id = ? for update
                """, (rs, n) -> new Object[] {rs.getBoolean(1), rs.getObject(2, Integer.class), rs.getString(3), rs.getString(4), rs.getLong(5)},
                dishId, restaurantId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DISH_NOT_FOUND", "Dish not found"));
        if (available != null && available != (boolean) row[0]) {
            db.update("update marketplace.food_dishes set available = ? where id = ?", available, dishId);
            audit(partnerId, actor, "DISH", dishId, "available", String.valueOf(row[0]), String.valueOf(available));
        }
        if (cleanName != null && !cleanName.equals(row[2])) {
            db.update("update marketplace.food_dishes set name = ? where id = ?", cleanName, dishId);
            audit(partnerId, actor, "DISH", dishId, "name", (String) row[2], cleanName);
        }
        if (cleanDescription != null && !cleanDescription.equals(row[3])) {
            db.update("update marketplace.food_dishes set description = ? where id = ?", cleanDescription, dishId);
            audit(partnerId, actor, "DISH", dishId, "description", abbreviate((String) row[3]), abbreviate(cleanDescription));
        }
        if (priceMinor != null && priceMinor != (long) row[4]) {
            db.update("update marketplace.food_dishes set price_minor = ? where id = ?", priceMinor, dishId);
            audit(partnerId, actor, "DISH", dishId, "price", String.valueOf(row[4]), String.valueOf(priceMinor));
        }
        if (stockQty != null || clearStock) {
            Integer target = clearStock ? null : stockQty;
            if (!java.util.Objects.equals(target, row[1])) {
                db.update("update marketplace.food_dishes set stock_qty = ? where id = ?", target, dishId);
                audit(partnerId, actor, "DISH", dishId, "stock", String.valueOf(row[1]), String.valueOf(target));
            }
        }
        return dishes(actor, partnerId, restaurantId).stream().filter(d -> d.id().equals(dishId.toString())).findFirst().orElseThrow();
    }

    /** Adds a dish to an existing section of the partner's own restaurant; it starts available and untracked. */
    @Transactional
    public DishView createDish(UUID actor, UUID partnerId, UUID restaurantId, UUID sectionId, String name, String description,
            long priceMinor) {
        return createDish(actor, partnerId, restaurantId, sectionId, name, description, priceMinor, "PIECE");
    }

    /** {@code unit} KG creates a weighed product: the price is per kg and stock is counted in grams. */
    @Transactional
    public DishView createDish(UUID actor, UUID partnerId, UUID restaurantId, UUID sectionId, String name, String description,
            long priceMinor, String unit) {
        if (!"PIECE".equals(unit) && !"KG".equals(unit)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "UNIT_INVALID", "unit must be PIECE or KG");
        }
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        requireOwnedRestaurant(partnerId, restaurantId);
        String cleanName = validName(name);
        String cleanDescription = description == null ? "" : validDescription(description);
        validPrice(priceMinor);
        Integer section = db.queryForObject("select count(*) from marketplace.food_menu_sections where id = ? and restaurant_id = ?",
                Integer.class, sectionId, restaurantId);
        if (section == null || section == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "SECTION_NOT_FOUND", "Menu section not found");
        }
        Integer dupes = db.queryForObject("select count(*) from marketplace.food_dishes where restaurant_id = ? and lower(name) = lower(?)",
                Integer.class, restaurantId, cleanName);
        if (dupes != null && dupes > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "DISH_NAME_TAKEN", "A dish with this name already exists");
        }
        Integer count = db.queryForObject("select count(*) from marketplace.food_dishes where restaurant_id = ?", Integer.class, restaurantId);
        if (count != null && count >= MAX_DISHES) {
            throw new ApiException(HttpStatus.CONFLICT, "MENU_FULL", "The menu has too many dishes");
        }
        UUID id = db.queryForObject("""
                insert into marketplace.food_dishes (restaurant_id, section_id, name, description, price_minor, unit, sort_order)
                values (?, ?, ?, ?, ?, ?, coalesce((select max(sort_order) + 1 from marketplace.food_dishes where section_id = ?), 0))
                returning id
                """, UUID.class, restaurantId, sectionId, cleanName, cleanDescription, priceMinor, unit, sectionId);
        audit(partnerId, actor, "DISH", id, "created", null, cleanName);
        return dishes(actor, partnerId, restaurantId).stream().filter(d -> d.id().equals(id.toString())).findFirst().orElseThrow();
    }

    private DishView dish(UUID actor, UUID partnerId, UUID restaurantId, UUID dishId) {
        return dishes(actor, partnerId, restaurantId).stream().filter(d -> d.id().equals(dishId.toString())).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DISH_NOT_FOUND", "Dish not found"));
    }

    private static String clean(String value, int max, String field) {
        if (value == null) { return null; }
        String v = value.strip();
        if (v.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ATTRIBUTE_INVALID", field + " is too long");
        }
        return v.isEmpty() ? "" : v;
    }

    private static void inRange(Number value, double max, String field) {
        if (value != null && (value.doubleValue() < 0 || value.doubleValue() > max)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ATTRIBUTE_INVALID", field + " is out of range");
        }
    }

    /**
     * Sets the Groceries attributes of a product of the partner's own store (owner/manager only): category, brand, origin,
     * composition, storage, nutrition per 100 g and the price before a discount (must stay above the price). Every change is audited.
     */
    @Transactional
    public DishView updateProductAttributes(UUID actor, UUID partnerId, UUID restaurantId, UUID dishId, ProductAttributes a) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        requireOwnedRestaurant(partnerId, restaurantId);
        var row = db.query("select price_minor, compare_at_price_minor, grocery_category, brand from marketplace.food_dishes where id = ? and restaurant_id = ? for update",
                (rs, n) -> new Object[] {rs.getLong(1), rs.getObject(2, Long.class), rs.getString(3), rs.getString(4)}, dishId, restaurantId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DISH_NOT_FOUND", "Dish not found"));
        long price = (long) row[0];
        if (a.groceryCategory() != null && !a.groceryCategory().isBlank()) {
            Integer known = db.queryForObject("select count(*) from marketplace.grocery_categories where slug = ? and enabled", Integer.class, a.groceryCategory());
            if (known == null || known == 0) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "CATEGORY_INVALID", "Unknown product category");
            }
            db.update("update marketplace.food_dishes set grocery_category = ? where id = ?", a.groceryCategory(), dishId);
            audit(partnerId, actor, "DISH", dishId, "category", (String) row[2], a.groceryCategory());
        } else if (a.clearCategory()) {
            db.update("update marketplace.food_dishes set grocery_category = null where id = ?", dishId);
            audit(partnerId, actor, "DISH", dishId, "category", (String) row[2], null);
        }
        String brand = clean(a.brand(), 80, "brand");
        if (brand != null) {
            db.update("update marketplace.food_dishes set brand = ? where id = ?", brand.isEmpty() ? null : brand, dishId);
            audit(partnerId, actor, "DISH", dishId, "brand", (String) row[3], brand);
        }
        String origin = clean(a.originCountry(), 60, "originCountry");
        if (origin != null) { db.update("update marketplace.food_dishes set origin_country = ? where id = ?", origin.isEmpty() ? null : origin, dishId); }
        String composition = clean(a.composition(), 500, "composition");
        if (composition != null) { db.update("update marketplace.food_dishes set composition = ? where id = ?", composition.isEmpty() ? null : composition, dishId); }
        String storage = clean(a.storageConditions(), 300, "storageConditions");
        if (storage != null) { db.update("update marketplace.food_dishes set storage_conditions = ? where id = ?", storage.isEmpty() ? null : storage, dishId); }
        inRange(a.kcal(), 1000, "kcal");
        inRange(a.protein(), 100, "protein");
        inRange(a.fat(), 100, "fat");
        inRange(a.carbs(), 100, "carbs");
        if (a.kcal() != null) { db.update("update marketplace.food_dishes set kcal_100 = ? where id = ?", a.kcal(), dishId); }
        if (a.protein() != null) { db.update("update marketplace.food_dishes set protein_100 = ? where id = ?", a.protein(), dishId); }
        if (a.fat() != null) { db.update("update marketplace.food_dishes set fat_100 = ? where id = ?", a.fat(), dishId); }
        if (a.carbs() != null) { db.update("update marketplace.food_dishes set carbs_100 = ? where id = ?", a.carbs(), dishId); }
        if (a.compareAtPriceMinor() != null) {
            if (a.compareAtPriceMinor() <= price || a.compareAtPriceMinor() > MAX_PRICE_MINOR) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "COMPARE_PRICE_INVALID", "The price before discount must be above the current price");
            }
            db.update("update marketplace.food_dishes set compare_at_price_minor = ? where id = ?", a.compareAtPriceMinor(), dishId);
            audit(partnerId, actor, "DISH", dishId, "compareAt", String.valueOf(row[1]), String.valueOf(a.compareAtPriceMinor()));
        } else if (a.clearCompareAt() && row[1] != null) {
            db.update("update marketplace.food_dishes set compare_at_price_minor = null where id = ?", dishId);
            audit(partnerId, actor, "DISH", dishId, "compareAt", String.valueOf(row[1]), null);
        }
        return dish(actor, partnerId, restaurantId, dishId);
    }

    private static final int MAX_PHOTOS = 6;

    /** Adds a photo by HTTPS URL (at most 6 per product); the first photo becomes the cover. */
    @Transactional
    public DishView addPhoto(UUID actor, UUID partnerId, UUID restaurantId, UUID dishId, String url) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        requireOwnedRestaurant(partnerId, restaurantId);
        String clean = url == null ? "" : url.strip();
        if (!clean.matches("^https://[^\\s]{4,480}$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PHOTO_URL_INVALID", "A photo must be an HTTPS link");
        }
        db.query("select id from marketplace.food_dishes where id = ? and restaurant_id = ? for update",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, dishId, restaurantId);
        Integer exists = db.queryForObject("select count(*) from marketplace.food_dishes where id = ? and restaurant_id = ?", Integer.class, dishId, restaurantId);
        if (exists == null || exists == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "DISH_NOT_FOUND", "Dish not found"); }
        Integer count = db.queryForObject("select count(*) from marketplace.food_dish_photos where dish_id = ?", Integer.class, dishId);
        if (count != null && count >= MAX_PHOTOS) {
            throw new ApiException(HttpStatus.CONFLICT, "PHOTO_LIMIT", "At most 6 photos per product");
        }
        db.update("insert into marketplace.food_dish_photos (dish_id, url, sort_order) values (?, ?, ?)", dishId, clean, count == null ? 0 : count);
        syncCover(dishId);
        audit(partnerId, actor, "DISH", dishId, "photo+", null, abbreviate(clean));
        return dish(actor, partnerId, restaurantId, dishId);
    }

    @Transactional
    public DishView removePhoto(UUID actor, UUID partnerId, UUID restaurantId, UUID dishId, UUID photoId) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        requireOwnedRestaurant(partnerId, restaurantId);
        int removed = db.update("""
                delete from marketplace.food_dish_photos p using marketplace.food_dishes d
                where p.id = ? and p.dish_id = d.id and d.id = ? and d.restaurant_id = ?
                """, photoId, dishId, restaurantId);
        if (removed == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "Photo not found"); }
        syncCover(dishId);
        audit(partnerId, actor, "DISH", dishId, "photo-", photoId.toString(), null);
        return dish(actor, partnerId, restaurantId, dishId);
    }

    private void syncCover(UUID dishId) {
        db.update("""
                update marketplace.food_dishes set image_url = (select url from marketplace.food_dish_photos
                    where dish_id = ? order by sort_order, created_at, id limit 1) where id = ?
                """, dishId, dishId);
    }

    private static final int MAX_DISHES = 300;
    /** KZT minor units; 0 up to 1 000 000 KZT. */
    private static final long MAX_PRICE_MINOR = 100_000_000L;

    private static String validName(String name) {
        String clean = name.strip();
        if (clean.length() < 2 || clean.length() > 160) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "NAME_INVALID", "Name must be 2-160 characters");
        }
        return clean;
    }

    private static String validDescription(String description) {
        String clean = description.strip();
        if (clean.length() > 500) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "DESCRIPTION_INVALID", "Description must be at most 500 characters");
        }
        return clean;
    }

    private static void validPrice(long priceMinor) {
        if (priceMinor < 0 || priceMinor > MAX_PRICE_MINOR) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PRICE_INVALID", "Price must be between 0 and 1 000 000 KZT");
        }
    }

    private static String abbreviate(String s) { return s == null ? null : s.length() <= 300 ? s : s.substring(0, 297) + "..."; }

    // ---- internals -----------------------------------------------------------------------------

    void auditCatalog(UUID partnerId, UUID actor, String entityType, UUID entityId, String field, String oldValue, String newValue) {
        audit(partnerId, actor, entityType, entityId, field, oldValue, newValue);
    }

    private void audit(UUID partnerId, UUID actor, String entityType, UUID entityId, String field, String oldValue, String newValue) {
        db.update("""
                insert into marketplace.partner_catalog_events (partner_id, actor_user_id, entity_type, entity_id, field, old_value, new_value)
                values (?, ?, ?, ?, ?, ?, ?)
                """, partnerId, actor, entityType, entityId, field, oldValue, newValue);
    }

    private void requireOwnedOrder(UUID partnerId, UUID orderId) {
        Integer found = db.queryForObject("select count(*) from transactions.food_orders where id = ? and partner_id = ?",
                Integer.class, orderId, partnerId);
        if (found == null || found == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found");
        }
    }

    private void requireOwnedRestaurant(UUID partnerId, UUID restaurantId) {
        Integer found = db.queryForObject("select count(*) from marketplace.food_restaurants where id = ? and partner_id = ?",
                Integer.class, restaurantId, partnerId);
        if (found == null || found == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant not found");
        }
    }

    private List<PartnerOrder> wrap(List<UUID> ids) {
        Map<UUID, String> customers = new java.util.HashMap<>();
        if (!ids.isEmpty()) {
            db.query("select id, user_id from transactions.food_orders where id = any (?)", rs -> {
                customers.put(rs.getObject(1, UUID.class), rs.getString(2).substring(0, 8));
            }, (Object) ids.toArray(UUID[]::new));
        }
        int window = orders.partnerResponseSeconds;
        return orders.views(ids, null).stream().map(o -> {
            boolean waiting = "PLACED".equals(o.status());
            return new PartnerOrder(o, customers.get(UUID.fromString(o.id())), next(o.status(), o.fulfillmentType(), o.vertical()),
                    waiting ? o.placedAt().plusSeconds(window) : null,
                    waiting ? o.placedAt().plusSeconds(window * 2L / 5) : null);
        }).toList();
    }
}
