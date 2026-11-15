package kz.kunde.food;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Food cart pricing (server-side quote), orders and the DEV mock fulfillment simulator. Prices are always
 * recomputed from the catalog on the server; the client only sends dish and option ids. Payment is mocked
 * (no card data is ever accepted) and delivery progress is simulated from elapsed time since placement.
 */
@Service
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodOrderService {
    public static final List<String> FLOW = List.of("PLACED", "ACCEPTED", "PREPARING", "ON_THE_WAY", "DELIVERED");
    private static final Set<String> TERMINAL = Set.of("DELIVERED", "CANCELLED");
    private static final Pattern KEY = Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final int MAX_ACTIVE_ORDERS = 5;
    private static final int MAX_TOTAL_QUANTITY = 50;

    public record CartItem(@NotNull UUID dishId, @Min(1) @Max(20) int quantity,
            @Size(max = 20) List<@NotNull UUID> optionIds) {
        List<UUID> options() { return optionIds == null ? List.of() : optionIds; }
    }

    public record QuoteRequest(@NotNull UUID restaurantId, @NotEmpty @Size(max = 30) List<@Valid @NotNull CartItem> items) {}

    public record OrderRequest(@NotNull UUID restaurantId, @NotEmpty @Size(max = 30) List<@Valid @NotNull CartItem> items,
            @NotNull UUID addressId, @NotNull String paymentMethod, @Size(max = 300) String comment) {}

    public record QuoteLine(String dishId, String name, String optionsText, List<String> optionIds,
            long unitPriceMinor, int quantity, long lineTotalMinor) {}

    public record Quote(String restaurantId, String restaurantName, List<QuoteLine> lines, long subtotalMinor,
            long deliveryFeeMinor, long totalMinor, String currency, long minOrderMinor) {}

    public record TimelineEntry(String status, OffsetDateTime at) {}

    public record OrderLine(String dishId, String name, String optionsText, long unitPriceMinor, int quantity,
            long lineTotalMinor) {}

    public record OrderView(String id, String restaurantId, String restaurantName, String status,
            String paymentMethod, String paymentStatus, String currency, long subtotalMinor, long deliveryFeeMinor,
            long totalMinor, String addressLabel, String addressText, String comment, OffsetDateTime placedAt,
            List<OrderLine> items, List<TimelineEntry> timeline, boolean cancellable, boolean simulated,
            String vertical) {}

    public record RepeatItem(String dishId, String name, int quantity, List<String> optionIds) {}

    public record RepeatResult(String restaurantId, String restaurantName, List<RepeatItem> items, List<String> skipped) {}

    public record Placed(OrderView order, boolean created) {}

    private final JdbcTemplate db;
    private final FoodProperties props;

    public FoodOrderService(JdbcTemplate db, FoodProperties props) {
        this.db = db;
        this.props = props;
    }

    // ---- pricing ---------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public Quote quote(UUID restaurantId, List<CartItem> items) {
        var restaurant = db.query("""
                select name, delivery_fee_minor, min_order_minor, is_open from marketplace.food_restaurants where id = ?
                """, (rs, row) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getLong(3), rs.getBoolean(4)},
                restaurantId).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                "RESTAURANT_NOT_FOUND", "Restaurant is not available"));
        if (!(boolean) restaurant[3]) {
            throw new ApiException(HttpStatus.CONFLICT, "RESTAURANT_CLOSED", "Restaurant is closed");
        }
        if (items.stream().mapToInt(CartItem::quantity).sum() > MAX_TOTAL_QUANTITY) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_CART_TOO_LARGE", "Too many items in the cart");
        }
        List<QuoteLine> lines = new ArrayList<>();
        long subtotal = 0;
        for (CartItem item : items) {
            QuoteLine line = priceLine(restaurantId, item);
            lines.add(line);
            subtotal += line.lineTotalMinor();
        }
        long minOrder = (long) restaurant[2];
        if (subtotal < minOrder) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_MIN_ORDER_NOT_MET",
                    "Order total is below the restaurant minimum");
        }
        long fee = (long) restaurant[1];
        return new Quote(restaurantId.toString(), (String) restaurant[0], lines, subtotal, fee, subtotal + fee, "KZT", minOrder);
    }

    private QuoteLine priceLine(UUID restaurantId, CartItem item) {
        var dish = db.query("""
                select name, price_minor, available from marketplace.food_dishes where id = ? and restaurant_id = ?
                """, (rs, row) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getBoolean(3)},
                item.dishId(), restaurantId).stream().findFirst().orElseThrow(() -> new ApiException(
                HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_ITEM_UNAVAILABLE", "A dish is not available"));
        if (!(boolean) dish[2]) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_ITEM_UNAVAILABLE", "A dish is not available");
        }
        Map<UUID, Integer> chosenPerGroup = new HashMap<>();
        List<String> names = new ArrayList<>();
        long delta = 0;
        Set<UUID> seen = new HashSet<>();
        for (UUID optionId : item.options()) {
            if (!seen.add(optionId)) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_OPTIONS_INVALID", "Duplicate option");
            }
            var option = db.query("""
                    select o.name, o.price_delta_minor, o.group_id from marketplace.food_options o
                    join marketplace.food_option_groups g on g.id = o.group_id
                    where o.id = ? and g.dish_id = ?
                    """, (rs, row) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getObject(3, UUID.class)},
                    optionId, item.dishId()).stream().findFirst().orElseThrow(() -> new ApiException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_OPTIONS_INVALID", "Unknown option for this dish"));
            names.add((String) option[0]);
            delta += (long) option[1];
            chosenPerGroup.merge((UUID) option[2], 1, Integer::sum);
        }
        db.query("select id, min_select, max_select from marketplace.food_option_groups where dish_id = ?", rs -> {
            int chosen = chosenPerGroup.getOrDefault(rs.getObject(1, UUID.class), 0);
            if (chosen < rs.getInt(2) || chosen > rs.getInt(3)) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_OPTIONS_INVALID",
                        "Option selection does not satisfy the dish rules");
            }
        }, item.dishId());
        long unit = (long) dish[1] + delta;
        return new QuoteLine(item.dishId().toString(), (String) dish[0], String.join(", ", names),
                item.options().stream().map(UUID::toString).toList(), unit, item.quantity(), unit * item.quantity());
    }

    // ---- orders ----------------------------------------------------------------------------------

    @Transactional
    public Placed place(UUID user, OrderRequest request, String idempotencyKey) {
        if (idempotencyKey == null || !KEY.matcher(idempotencyKey).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_INVALID",
                    "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }
        String payment = request.paymentMethod();
        if (!"TEST_CARD".equals(payment) && !"CASH_ON_DELIVERY".equals(payment)) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PAYMENT_METHOD_UNSUPPORTED",
                    "Only the DEV test card and cash on delivery are available");
        }
        // Serialize this user's orders so the idempotency lookup and active-order cap are race free.
        db.query("select pg_advisory_xact_lock(hashtext('food-order'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        var existing = db.query("select id, restaurant_id from transactions.food_orders where user_id = ? and idempotency_key = ?",
                (rs, row) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class)}, user, idempotencyKey)
                .stream().findFirst();
        if (existing.isPresent()) {
            if (!existing.get()[1].equals(request.restaurantId())) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED",
                        "Idempotency-Key was already used for a different order");
            }
            advance((UUID) existing.get()[0]);
            return new Placed(views(List.of((UUID) existing.get()[0]), user).get(0), false);
        }
        Integer active = db.queryForObject("""
                select count(*) from transactions.food_orders where user_id = ? and status not in ('DELIVERED', 'CANCELLED')
                  and placed_at > now() - make_interval(secs => ?)
                """, Integer.class, user, props.simulation().deliveredAfterSeconds());
        if (active != null && active >= MAX_ACTIVE_ORDERS) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_ACTIVE_ORDERS", "Too many active orders");
        }
        var address = db.query("""
                select label, formatted_address from profile.consumer_addresses
                where id = ? and user_id = ? and deleted_at is null
                """, (rs, row) -> new String[] {rs.getString(1), rs.getString(2)}, request.addressId(), user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "ADDRESS_NOT_FOUND", "Choose one of your saved delivery addresses"));
        Quote quote = quote(request.restaurantId(), request.items());
        String comment = request.comment() == null || request.comment().isBlank() ? null : request.comment().strip();
        UUID orderId = db.queryForObject("""
                insert into transactions.food_orders (user_id, restaurant_id, restaurant_name, payment_method, payment_status,
                    subtotal_minor, delivery_fee_minor, total_minor, address_label, address_text, comment, idempotency_key, vertical)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, (select vertical from marketplace.food_restaurants where id = ?)) returning id
                """, UUID.class, user, request.restaurantId(), quote.restaurantName(), payment,
                "TEST_CARD".equals(payment) ? "TEST_PAID" : "PAY_ON_RECEIPT", quote.subtotalMinor(),
                quote.deliveryFeeMinor(), quote.totalMinor(), address[0], address[1], comment, idempotencyKey, request.restaurantId());
        for (QuoteLine line : quote.lines()) {
            db.update("""
                    insert into transactions.food_order_items (order_id, dish_id, dish_name, options_text, option_ids,
                        unit_price_minor, quantity, line_total_minor) values (?, ?, ?, ?, ?::uuid[], ?, ?, ?)
                    """, orderId, UUID.fromString(line.dishId()), line.name(), line.optionsText(),
                    "{" + String.join(",", line.optionIds()) + "}", line.unitPriceMinor(), line.quantity(), line.lineTotalMinor());
        }
        db.update("insert into transactions.food_order_events (order_id, status) values (?, 'PLACED')", orderId);
        return new Placed(views(List.of(orderId), user).get(0), true);
    }

    @Transactional
    public List<OrderView> list(UUID user, int limit, int offset) {
        List<UUID> ids = db.queryForList("""
                select id from transactions.food_orders where user_id = ? order by placed_at desc, id limit ? offset ?
                """, UUID.class, user, limit, offset);
        ids.forEach(this::advance);
        return views(ids, user);
    }

    @Transactional
    public OrderView get(UUID user, UUID orderId) {
        requireOwned(user, orderId);
        advance(orderId);
        return views(List.of(orderId), user).get(0);
    }

    /** Free cancellation only before the restaurant accepts (D-06); later cancellation goes through support. */
    @Transactional
    public OrderView cancel(UUID user, UUID orderId) {
        requireOwned(user, orderId);
        advance(orderId);
        String status = db.queryForObject("select status from transactions.food_orders where id = ? for update", String.class, orderId);
        if (!"PLACED".equals(status)) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_NOT_CANCELLABLE",
                    "The restaurant has already accepted this order");
        }
        db.update("""
                update transactions.food_orders set status = 'CANCELLED', payment_status = 'VOIDED',
                    updated_at = now(), version = version + 1 where id = ?
                """, orderId);
        db.update("insert into transactions.food_order_events (order_id, status) values (?, 'CANCELLED')", orderId);
        return views(List.of(orderId), user).get(0);
    }

    /** Items of a past order that can still be ordered; the client puts them in the cart and requests a fresh quote. */
    @Transactional(readOnly = true)
    public RepeatResult repeat(UUID user, UUID orderId) {
        requireOwned(user, orderId);
        var order = db.queryForObject("select restaurant_id, restaurant_name from transactions.food_orders where id = ?",
                (rs, row) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2)}, orderId);
        List<RepeatItem> items = new ArrayList<>();
        List<String> skipped = new ArrayList<>();
        db.query("""
                select i.dish_id, i.dish_name, i.quantity, i.option_ids, d.available
                from transactions.food_order_items i join marketplace.food_dishes d on d.id = i.dish_id
                where i.order_id = ? order by i.id
                """, rs -> {
                    UUID dishId = rs.getObject("dish_id", UUID.class);
                    List<UUID> options = new ArrayList<>();
                    for (Object o : (Object[]) rs.getArray("option_ids").getArray()) { options.add((UUID) o); }
                    boolean ok = rs.getBoolean("available");
                    if (ok) {
                        try {
                            priceLine((UUID) order[0], new CartItem(dishId, 1, options));
                        } catch (ApiException invalid) {
                            ok = false;
                        }
                    }
                    if (ok) {
                        items.add(new RepeatItem(dishId.toString(), rs.getString("dish_name"), rs.getInt("quantity"),
                                options.stream().map(UUID::toString).toList()));
                    } else {
                        skipped.add(rs.getString("dish_name"));
                    }
                }, orderId);
        return new RepeatResult(order[0].toString(), (String) order[1], items, skipped);
    }

    // ---- DEV mock fulfillment --------------------------------------------------------------------

    /** Moves a non-terminal order forward according to elapsed time since placement (explicit DEV simulation). */
    void advance(UUID orderId) {
        var row = db.query("""
                select status, extract(epoch from (now() - placed_at))::bigint as elapsed, placed_at
                from transactions.food_orders where id = ? for update
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getObject(3, OffsetDateTime.class)}, orderId)
                .stream().findFirst().orElse(null);
        if (row == null || TERMINAL.contains((String) row[0])) {
            return;
        }
        var sim = props.simulation();
        int[] after = {0, sim.acceptedAfterSeconds(), sim.preparingAfterSeconds(), sim.onTheWayAfterSeconds(),
                sim.deliveredAfterSeconds()};
        long elapsed = (long) row[1];
        int current = FLOW.indexOf((String) row[0]);
        int target = current;
        for (int i = current + 1; i < FLOW.size(); i++) {
            if (elapsed >= after[i]) { target = i; }
        }
        for (int i = current + 1; i <= target; i++) {
            db.update("insert into transactions.food_order_events (order_id, status, occurred_at) values (?, ?, ?)",
                    orderId, FLOW.get(i), ((OffsetDateTime) row[2]).plusSeconds(after[i]));
        }
        if (target != current) {
            db.update("update transactions.food_orders set status = ?, updated_at = now(), version = version + 1 where id = ?",
                    FLOW.get(target), orderId);
        }
    }

    // ---- views -----------------------------------------------------------------------------------

    private void requireOwned(UUID user, UUID orderId) {
        Integer found = db.queryForObject("select count(*) from transactions.food_orders where id = ? and user_id = ?",
                Integer.class, orderId, user);
        if (found == null || found == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found");
        }
    }

    private List<OrderView> views(List<UUID> ids, UUID user) {
        if (ids.isEmpty()) { return List.of(); }
        UUID[] array = ids.toArray(UUID[]::new);
        Map<UUID, List<OrderLine>> items = new HashMap<>();
        db.query("""
                select order_id, dish_id, dish_name, options_text, unit_price_minor, quantity, line_total_minor
                from transactions.food_order_items where order_id = any (?) order by id
                """, rs -> {
                    items.computeIfAbsent(rs.getObject("order_id", UUID.class), k -> new ArrayList<>()).add(new OrderLine(
                            rs.getString("dish_id"), rs.getString("dish_name"), rs.getString("options_text"),
                            rs.getLong("unit_price_minor"), rs.getInt("quantity"), rs.getLong("line_total_minor")));
                }, (Object) array);
        Map<UUID, List<TimelineEntry>> timeline = new HashMap<>();
        db.query("select order_id, status, occurred_at from transactions.food_order_events where order_id = any (?) order by id",
                rs -> {
                    timeline.computeIfAbsent(rs.getObject("order_id", UUID.class), k -> new ArrayList<>())
                            .add(new TimelineEntry(rs.getString("status"), rs.getObject("occurred_at", OffsetDateTime.class)));
                }, (Object) array);
        Map<UUID, OrderView> byId = new LinkedHashMap<>();
        db.query("""
                select id, restaurant_id, restaurant_name, status, payment_method, payment_status, currency,
                       subtotal_minor, delivery_fee_minor, total_minor, address_label, address_text, comment, placed_at, vertical
                from transactions.food_orders where user_id = ? and id = any (?)
                """, rs -> {
                    UUID id = rs.getObject("id", UUID.class);
                    byId.put(id, new OrderView(id.toString(), rs.getString("restaurant_id"), rs.getString("restaurant_name"),
                            rs.getString("status"), rs.getString("payment_method"), rs.getString("payment_status"),
                            rs.getString("currency"), rs.getLong("subtotal_minor"), rs.getLong("delivery_fee_minor"),
                            rs.getLong("total_minor"), rs.getString("address_label"), rs.getString("address_text"),
                            rs.getString("comment"), rs.getObject("placed_at", OffsetDateTime.class),
                            items.getOrDefault(id, List.of()), timeline.getOrDefault(id, List.of()),
                            "PLACED".equals(rs.getString("status")), true, rs.getString("vertical")));
                }, user, array);
        return ids.stream().map(byId::get).filter(java.util.Objects::nonNull).toList();
    }
}
