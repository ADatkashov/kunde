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
    private static final Map<String, List<String>> NEXT = Map.of(
            "PLACED", List.of("ACCEPTED", "CANCELLED"),
            "ACCEPTED", List.of("PREPARING", "CANCELLED"),
            "PREPARING", List.of("ON_THE_WAY", "CANCELLED"),
            "ON_THE_WAY", List.of("DELIVERED"));

    public record PartnerOrder(OrderView order, String customerRef, List<String> allowedNext, OffsetDateTime respondBy,
            OffsetDateTime reminderAt) {}

    public record RestaurantView(String id, String name, String vertical, boolean open, boolean synthetic) {}

    public record DishView(String id, String name, String section, long priceMinor, boolean available, Integer stockQty,
            String unit) {}

    private final JdbcTemplate db;
    private final FoodOrderService orders;
    private final PartnerService partners;

    public FoodPartnerService(JdbcTemplate db, FoodOrderService orders, PartnerService partners) {
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
                select id from transactions.food_orders where partner_id = ? and (status in ('PLACED','ACCEPTED','PREPARING','ON_THE_WAY')) <> ?
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
        String status = db.query("select status from transactions.food_orders where id = ? and partner_id = ? for update",
                (rs, n) -> rs.getString(1), orderId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        String clean = reason == null || reason.isBlank() ? null : reason.strip();
        if (to.equals(status)) {
            return wrap(List.of(orderId)).get(0);
        }
        if (!NEXT.getOrDefault(status, List.of()).contains(to)) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_TRANSITION_INVALID",
                    "The order cannot move from " + status + " to " + to);
        }
        if ("CANCELLED".equals(to) && (clean == null || clean.length() < 3 || clean.length() > 300)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of 3-300 characters is required");
        }
        if ("CANCELLED".equals(to)) {
            db.update("""
                    update transactions.food_orders set status = 'CANCELLED', payment_status = 'VOIDED', cancelled_by = 'PARTNER',
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
        if ("PREPARING".equals(to)) {
            // The store collects the order: unavailable products are replaced or removed per the customer's choice.
            orders.resolveLines(orderId, OffsetDateTime.now());
        }
        return wrap(List.of(orderId)).get(0);
    }

    // ---- catalog / availability ----------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<RestaurantView> restaurants(UUID actor, UUID partnerId) {
        partners.requireProcessing(actor, partnerId);
        return db.query("""
                select id, name, vertical, is_open, is_synthetic from marketplace.food_restaurants
                where partner_id = ? order by sort_order, name
                """, (rs, n) -> new RestaurantView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getBoolean(4),
                rs.getBoolean(5)), partnerId);
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
        return db.query("""
                select d.id, d.name, s.name, d.price_minor, d.available, d.stock_qty, d.unit
                from marketplace.food_dishes d join marketplace.food_menu_sections s on s.id = d.section_id
                where d.restaurant_id = ? order by s.sort_order, d.sort_order, d.name
                """, (rs, n) -> new DishView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getLong(4),
                rs.getBoolean(5), rs.getObject(6, Integer.class), rs.getString(7)), restaurantId);
    }

    /** Availability and the stock counter only; names and prices stay with the existing offering flow. */
    @Transactional
    public DishView updateDish(UUID actor, UUID partnerId, UUID restaurantId, UUID dishId, Boolean available,
            Integer stockQty, boolean clearStock) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedRestaurant(partnerId, restaurantId);
        if (stockQty != null && (clearStock || stockQty < 0 || stockQty > 100000)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "STOCK_INVALID", "Stock must be 0-100000, or cleared");
        }
        var row = db.query("""
                select available, stock_qty from marketplace.food_dishes where id = ? and restaurant_id = ? for update
                """, (rs, n) -> new Object[] {rs.getBoolean(1), rs.getObject(2, Integer.class)}, dishId, restaurantId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DISH_NOT_FOUND", "Dish not found"));
        if (available != null && available != (boolean) row[0]) {
            db.update("update marketplace.food_dishes set available = ? where id = ?", available, dishId);
            audit(partnerId, actor, "DISH", dishId, "available", String.valueOf(row[0]), String.valueOf(available));
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

    // ---- internals -----------------------------------------------------------------------------

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
            return new PartnerOrder(o, customers.get(UUID.fromString(o.id())), NEXT.getOrDefault(o.status(), List.of()),
                    waiting ? o.placedAt().plusSeconds(window) : null,
                    waiting ? o.placedAt().plusSeconds(window * 2L / 5) : null);
        }).toList();
    }
}
