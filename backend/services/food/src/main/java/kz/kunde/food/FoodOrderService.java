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
 * Food/Grocery cart pricing (server-side quote), orders and the DEV mock fulfillment simulator. Prices are always
 * recomputed from the catalog on the server; the client only sends ids, quantities and substitution preferences.
 * Quantities are pieces (unit PIECE) or grams (unit KG, price is per kg, step 100 g). Stock is reserved when the
 * order is placed and returned on cancellation. Payment is mocked (no card data) and delivery is simulated.
 */
@Service
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodOrderService {
    public static final List<String> FLOW = List.of("PLACED", "ACCEPTED", "PREPARING", "ON_THE_WAY", "DELIVERED");
    /** Pickup orders are handed over at the restaurant: the courier leg is replaced by READY_FOR_PICKUP. */
    public static final List<String> PICKUP_FLOW = List.of("PLACED", "ACCEPTED", "PREPARING", "READY_FOR_PICKUP", "DELIVERED");
    private static final Set<String> TERMINAL = Set.of("DELIVERED", "CANCELLED");
    private static final java.util.regex.Pattern KEY = java.util.regex.Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final int MAX_ACTIVE_ORDERS = 5;
    private static final int MAX_PIECES = 20;
    private static final int MAX_GRAMS = 5000;
    private static final int GRAM_STEP = 100;
    private static final int MAX_TOTAL_PIECES = 50;

    public record CartItem(@NotNull UUID dishId, @Min(1) @Max(10000) int quantity,
            @Size(max = 20) List<@NotNull UUID> optionIds,
            @jakarta.validation.constraints.Pattern(regexp = "NONE|ANY_SIMILAR|CHOSEN") String substitution,
            @Size(max = 5) List<@NotNull UUID> substituteDishIds) {
        List<UUID> options() { return optionIds == null ? List.of() : optionIds; }
        String policy() { return substitution == null ? "NONE" : substitution; }
        List<UUID> substitutes() { return substituteDishIds == null ? List.of() : substituteDishIds; }
    }

    public record QuoteRequest(@NotNull UUID restaurantId, @NotEmpty @Size(max = 30) List<@Valid @NotNull CartItem> items,
            @jakarta.validation.constraints.Pattern(regexp = "DELIVERY|PICKUP") String fulfillmentType,
            @Size(max = 32) String promoCode) {}

    public record OrderRequest(@NotNull UUID restaurantId, @NotEmpty @Size(max = 30) List<@Valid @NotNull CartItem> items,
            UUID addressId, @NotNull String paymentMethod, @Size(max = 300) String comment, Long expectedTotalMinor,
            @jakarta.validation.constraints.Pattern(regexp = "DELIVERY|PICKUP") String fulfillmentType,
            @Size(max = 32) String promoCode) {
        boolean pickup() { return "PICKUP".equals(fulfillmentType); }
    }

    public record QuoteLine(String dishId, String name, String optionsText, List<String> optionIds, String unit,
            long unitPriceMinor, int quantity, long lineTotalMinor, String substitution, List<String> substituteDishIds) {}

    public record Quote(String restaurantId, String restaurantName, List<QuoteLine> lines, long subtotalMinor,
            long deliveryFeeMinor, long totalMinor, String currency, long minOrderMinor, String fulfillmentType,
            long discountMinor, String promoCode, String promoTitle, int prepMinutes) {}

    public record TimelineEntry(String status, OffsetDateTime at, String actor, String reason) {}

    /** itemId identifies the line for picking and for the customer's decision; proposed* is set while status is PROPOSED. */
    public record OrderLine(String itemId, String dishId, String name, String optionsText, String unit, long unitPriceMinor, int quantity,
            long lineTotalMinor, String substitution, String fulfillmentStatus, String replacedByName,
            Long finalLineTotalMinor, String proposedName, Long proposedUnitPriceMinor) {}

    public record OrderView(String id, String restaurantId, String restaurantName, String status,
            String paymentMethod, String paymentStatus, String currency, long subtotalMinor, long deliveryFeeMinor,
            long totalMinor, String addressLabel, String addressText, String comment, OffsetDateTime placedAt,
            List<OrderLine> items, List<TimelineEntry> timeline, boolean cancellable, boolean simulated,
            String vertical, Long finalTotalMinor, boolean hasChanges, String fulfillment, String cancelledBy,
            String cancelReason, String fulfillmentType, long discountMinor, String promoCode, boolean reviewed) {}

    public record RepeatItem(String dishId, String name, int quantity, List<String> optionIds, String unit,
            String substitution, List<String> substituteDishIds) {}

    public record RepeatResult(String restaurantId, String restaurantName, List<RepeatItem> items, List<String> skipped) {}

    public record Placed(OrderView order, boolean created) {}

    private final JdbcTemplate db;
    private final FoodProperties props;
    private final FoodPromotionService promotions;
    private kz.kunde.platform.FeatureToggles toggles;

    /** D-05: a partner has this long to answer a new order; afterwards the system cancels it (free for the customer). */
    @org.springframework.beans.factory.annotation.Value("${app.partner-ops.response-timeout-seconds:300}")
    int partnerResponseSeconds = 300;

    public FoodOrderService(JdbcTemplate db, FoodProperties props, FoodPromotionService promotions) {
        this.db = db;
        this.props = props;
        this.promotions = promotions;
    }

    @org.springframework.beans.factory.annotation.Autowired
    void setToggles(kz.kunde.platform.FeatureToggles toggles) { this.toggles = toggles; }

    /** New grocery quotes/orders need the GROCERIES switch; reading or cancelling existing orders never does. */
    private void requireGroceriesOn(UUID restaurantId) {
        if (toggles == null || toggles.enabled(kz.kunde.platform.FeatureToggles.Feature.GROCERIES)) { return; }
        String vertical = db.query("select vertical from marketplace.food_restaurants where id = ?",
                (rs, row) -> rs.getString(1), restaurantId).stream().findFirst().orElse(null);
        if ("GROCERY".equals(vertical)) {
            throw new ApiException(HttpStatus.CONFLICT, "GROCERIES_DISABLED", "Groceries is switched off; new orders are not accepted");
        }
    }

    static long lineTotal(String unit, long unitPrice, int quantity) {
        return "KG".equals(unit) ? (unitPrice * quantity + 500) / 1000 : unitPrice * quantity;
    }

    // ---- pricing ---------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public Quote quote(UUID restaurantId, List<CartItem> items) {
        return quote(restaurantId, items, "DELIVERY", null, null);
    }

    @Transactional(readOnly = true)
    public Quote quote(UUID restaurantId, List<CartItem> items, String fulfillmentType, String promoCode, UUID user) {
        boolean pickup = "PICKUP".equals(fulfillmentType);
        requireGroceriesOn(restaurantId);
        var restaurant = db.query("""
                select name, delivery_fee_minor, min_order_minor, marketplace.food_restaurant_open(r), pickup_enabled, prep_minutes
                from marketplace.food_restaurants r where id = ?
                """, (rs, row) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getLong(3), rs.getBoolean(4),
                        rs.getBoolean(5), rs.getInt(6)},
                restaurantId).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                "RESTAURANT_NOT_FOUND", "Restaurant is not available"));
        if (!(boolean) restaurant[3]) {
            throw new ApiException(HttpStatus.CONFLICT, "RESTAURANT_CLOSED", "Restaurant is closed");
        }
        List<QuoteLine> lines = new ArrayList<>();
        long subtotal = 0;
        int pieces = 0;
        for (CartItem item : items) {
            QuoteLine line = priceLine(restaurantId, item);
            lines.add(line);
            subtotal += line.lineTotalMinor();
            if ("PIECE".equals(line.unit())) { pieces += line.quantity(); }
        }
        if (pieces > MAX_TOTAL_PIECES) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_CART_TOO_LARGE", "Too many items in the cart");
        }
        long minOrder = (long) restaurant[2];
        if (subtotal < minOrder) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_MIN_ORDER_NOT_MET",
                    "Order total is below the restaurant minimum");
        }
        if (pickup && !(boolean) restaurant[4]) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PICKUP_UNAVAILABLE", "This restaurant does not offer pickup");
        }
        long fee = pickup ? 0 : (long) restaurant[1];
        long discount = 0;
        String appliedCode = null;
        String promoTitle = null;
        if (promoCode != null && !promoCode.isBlank()) {
            var promo = promotions.evaluate(promoCode, restaurantId, subtotal, user, false);
            discount = promo.discountMinor();
            appliedCode = promo.code();
            promoTitle = promo.title();
        }
        return new Quote(restaurantId.toString(), (String) restaurant[0], lines, subtotal, fee, subtotal + fee - discount,
                "KZT", minOrder, pickup ? "PICKUP" : "DELIVERY", discount, appliedCode, promoTitle, (int) restaurant[5]);
    }

    private QuoteLine priceLine(UUID restaurantId, CartItem item) {
        var dish = db.query("""
                select name, price_minor, available, unit, stock_qty, section_id
                from marketplace.food_dishes where id = ? and restaurant_id = ?
                """, (rs, row) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getBoolean(3), rs.getString(4),
                        rs.getObject(5, Integer.class), rs.getObject(6, UUID.class)},
                item.dishId(), restaurantId).stream().findFirst().orElseThrow(() -> new ApiException(
                HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_ITEM_UNAVAILABLE", "A dish is not available"));
        if (!(boolean) dish[2]) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_ITEM_UNAVAILABLE", "A dish is not available");
        }
        String unit = (String) dish[3];
        int quantity = item.quantity();
        if ("KG".equals(unit)) {
            if (quantity < GRAM_STEP || quantity > MAX_GRAMS || quantity % GRAM_STEP != 0) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_QUANTITY_INVALID",
                        "Weighed goods are ordered in 100 g steps from 100 g to 5 kg");
            }
        } else if (quantity > MAX_PIECES) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_QUANTITY_INVALID", "At most 20 pieces per line");
        }
        Integer stock = (Integer) dish[4];
        if (stock != null && quantity > stock) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_STOCK_INSUFFICIENT", "Not enough in stock");
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
        String policy = item.policy();
        List<String> substitutes = List.of();
        if ("CHOSEN".equals(policy)) {
            if (item.substitutes().isEmpty()) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_SUBSTITUTION_INVALID",
                        "Choose at least one acceptable replacement");
            }
            for (UUID sub : item.substitutes()) {
                Integer ok = db.queryForObject("""
                        select count(*) from marketplace.food_dishes
                        where id = ? and restaurant_id = ? and unit = ? and id <> ?
                        """, Integer.class, sub, restaurantId, unit, item.dishId());
                if (ok == null || ok == 0) {
                    throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FOOD_SUBSTITUTION_INVALID",
                            "A replacement must be another product of the same store and unit");
                }
            }
            substitutes = item.substitutes().stream().map(UUID::toString).toList();
        }
        long unitPrice = (long) dish[1] + delta;
        return new QuoteLine(item.dishId().toString(), (String) dish[0], String.join(", ", names),
                item.options().stream().map(UUID::toString).toList(), unit, unitPrice, quantity,
                lineTotal(unit, unitPrice, quantity), policy, substitutes);
    }

    // ---- orders ----------------------------------------------------------------------------------

    @Transactional
    public Placed place(UUID user, OrderRequest request, String idempotencyKey) {
        if (idempotencyKey == null || !KEY.matcher(idempotencyKey).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_INVALID",
                    "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }
        String payment = request.paymentMethod();
        if (!"TEST_CARD".equals(payment) && !"CASH_ON_DELIVERY".equals(payment) && !"DEV_NO_PAYMENT".equals(payment)) {
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
        requireGroceriesOn(request.restaurantId());
        Integer active = db.queryForObject("""
                select count(*) from transactions.food_orders where user_id = ? and status not in ('DELIVERED', 'CANCELLED')
                  and placed_at > now() - make_interval(secs => ?)
                """, Integer.class, user, props.simulation().deliveredAfterSeconds());
        if (active != null && active >= MAX_ACTIVE_ORDERS) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_ACTIVE_ORDERS", "Too many active orders");
        }
        String[] address;
        if (request.pickup()) {
            address = db.query("select 'Самовывоз', coalesce(address_text, name) from marketplace.food_restaurants where id = ?",
                    (rs, row) -> new String[] {rs.getString(1), rs.getString(2)}, request.restaurantId())
                    .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                            "RESTAURANT_NOT_FOUND", "Restaurant is not available"));
        } else {
            address = db.query("""
                    select label, formatted_address from profile.consumer_addresses
                    where id = ? and user_id = ? and deleted_at is null
                    """, (rs, row) -> new String[] {rs.getString(1), rs.getString(2)}, request.addressId(), user)
                    .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,
                            "ADDRESS_NOT_FOUND", "Choose one of your saved delivery addresses"));
        }
        var store = db.query("select r.vertical, r.partner_id, p.verification_status from marketplace.food_restaurants r left join marketplace.partners p on p.id = r.partner_id where r.id = ? for share of r",
                (rs, row) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class), rs.getString(3)}, request.restaurantId())
                .stream().findFirst();
        boolean flowers = store.isPresent() && "FLOWERS_GIFTS".equals(store.get()[0]);
        if (flowers && (!"DEV_NO_PAYMENT".equals(payment) || store.get()[1] == null || !"APPROVED".equals(store.get()[2]))) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FLOWERS_ORDER_UNAVAILABLE",
                    "Flowers orders require a partner and DEV no-payment checkout");
        }
        if (!flowers && "DEV_NO_PAYMENT".equals(payment)) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PAYMENT_METHOD_UNSUPPORTED", "Payment method unsupported");
        }
        if (request.pickup() && flowers) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PICKUP_UNAVAILABLE", "This store does not offer pickup");
        }
        Quote quote = quote(request.restaurantId(), request.items(), request.pickup() ? "PICKUP" : "DELIVERY",
                flowers ? null : request.promoCode(), user);
        if (request.expectedTotalMinor() != null && !flowers && request.expectedTotalMinor() != quote.totalMinor()) {
            throw new ApiException(HttpStatus.CONFLICT, "FOOD_PRICE_CHANGED", "The total changed; refresh the cart");
        }
        if (flowers && (request.expectedTotalMinor() == null || request.expectedTotalMinor() != quote.totalMinor())) {
            throw new ApiException(HttpStatus.CONFLICT, "FOOD_PRICE_CHANGED", "The total changed; refresh the cart");
        }
        // Reserve stock atomically per line; a concurrent order that took the last units makes this one fail cleanly.
        for (QuoteLine line : quote.lines()) {
            int reserved = db.update("""
                    update marketplace.food_dishes set stock_qty = stock_qty - ?
                    where id = ? and (stock_qty is null or stock_qty >= ?)
                    """, line.quantity(), UUID.fromString(line.dishId()), line.quantity());
            if (reserved == 0) {
                throw new ApiException(HttpStatus.CONFLICT, "FOOD_STOCK_INSUFFICIENT", "Not enough in stock");
            }
        }
        String comment = request.comment() == null || request.comment().isBlank() ? null : request.comment().strip();
        UUID orderId = db.queryForObject("""
                insert into transactions.food_orders (user_id, restaurant_id, restaurant_name, payment_method, payment_status,
                    subtotal_minor, delivery_fee_minor, total_minor, address_label, address_text, comment, idempotency_key, vertical,
                    partner_id, fulfillment_mode, fulfillment_type, discount_minor, promo_code)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, (select vertical from marketplace.food_restaurants where id = ?),
                    (select partner_id from marketplace.food_restaurants where id = ?),
                    case when (select partner_id from marketplace.food_restaurants where id = ?) is null then 'SIMULATED' else 'PARTNER' end,
                    ?, ?, ?)
                returning id
                """, UUID.class, user, request.restaurantId(), quote.restaurantName(), payment,
                "DEV_NO_PAYMENT".equals(payment) ? "NO_PAYMENT" :
                        ("TEST_CARD".equals(payment) ? "TEST_PAID" : "PAY_ON_RECEIPT"), quote.subtotalMinor(),
                quote.deliveryFeeMinor(), quote.totalMinor(), address[0], address[1], comment, idempotencyKey,
                request.restaurantId(), request.restaurantId(), request.restaurantId(), quote.fulfillmentType(),
                quote.discountMinor(), quote.promoCode());
        if (quote.promoCode() != null) {
            promotions.redeem(quote.promoCode(), orderId, user, quote.discountMinor());
        }
        int lineNo = 0;
        for (QuoteLine line : quote.lines()) {
            db.update("""
                    insert into transactions.food_order_items (order_id, dish_id, dish_name, options_text, option_ids,
                        unit_price_minor, quantity, line_total_minor, unit, substitution, substitute_dish_ids, line_no)
                    values (?, ?, ?, ?, ?::uuid[], ?, ?, ?, ?, ?, ?::uuid[], ?)
                    """, orderId, UUID.fromString(line.dishId()), line.name(), line.optionsText(),
                    "{" + String.join(",", line.optionIds()) + "}", line.unitPriceMinor(), line.quantity(),
                    line.lineTotalMinor(), line.unit(), line.substitution(),
                    "{" + String.join(",", line.substituteDishIds()) + "}", lineNo++);
        }
        db.update("insert into transactions.food_order_events (order_id, status, actor_type, actor_user_id) values (?, 'PLACED', 'CUSTOMER', ?)",
                orderId, user);
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
                update transactions.food_orders set status = 'CANCELLED', payment_status = case when payment_method = 'DEV_NO_PAYMENT' then 'NO_PAYMENT' else 'VOIDED' end, cancelled_by = 'CUSTOMER',
                    updated_at = now(), version = version + 1 where id = ?
                """, orderId);
        db.update("insert into transactions.food_order_events (order_id, status, actor_type, actor_user_id) values (?, 'CANCELLED', 'CUSTOMER', ?)",
                orderId, user);
        restoreStock(orderId);
        return views(List.of(orderId), user).get(0);
    }

    void restoreStock(UUID orderId) {
        promotions.release(orderId);
        db.update("""
                update marketplace.food_dishes d set stock_qty = d.stock_qty + i.quantity
                from transactions.food_order_items i
                where i.order_id = ? and i.dish_id = d.id and d.stock_qty is not null and i.fulfillment_status <> 'REMOVED'
                """, orderId);
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
                select i.dish_id, i.dish_name, i.quantity, i.option_ids, d.available, i.unit, i.substitution, i.substitute_dish_ids
                from transactions.food_order_items i join marketplace.food_dishes d on d.id = i.dish_id
                where i.order_id = ? order by i.line_no, i.id
                """, rs -> {
                    UUID dishId = rs.getObject("dish_id", UUID.class);
                    List<UUID> options = uuids(rs.getArray("option_ids"));
                    List<UUID> subs = uuids(rs.getArray("substitute_dish_ids"));
                    String policy = rs.getString("substitution");
                    int quantity = rs.getInt("quantity");
                    boolean ok = rs.getBoolean("available");
                    if (ok) {
                        try {
                            priceLine((UUID) order[0], new CartItem(dishId, quantity, options, policy, subs));
                        } catch (ApiException invalid) {
                            ok = false;
                        }
                    }
                    if (ok) {
                        items.add(new RepeatItem(dishId.toString(), rs.getString("dish_name"), quantity,
                                options.stream().map(UUID::toString).toList(), rs.getString("unit"), policy,
                                subs.stream().map(UUID::toString).toList()));
                    } else {
                        skipped.add(rs.getString("dish_name"));
                    }
                }, orderId);
        return new RepeatResult(order[0].toString(), (String) order[1], items, skipped);
    }

    private static List<UUID> uuids(java.sql.Array array) throws java.sql.SQLException {
        List<UUID> list = new ArrayList<>();
        for (Object o : (Object[]) array.getArray()) { list.add((UUID) o); }
        return list;
    }

    /** Cancels this partner's orders that waited longer than the response window (called before partner reads/moves). */
    void expireUnanswered(UUID partnerId) {
        for (UUID id : db.queryForList("""
                select id from transactions.food_orders
                where partner_id = ? and status = 'PLACED' and placed_at <= now() - make_interval(secs => ?)
                """, UUID.class, partnerId, partnerResponseSeconds)) {
            advance(id);
        }
    }

    // ---- DEV mock fulfillment --------------------------------------------------------------------

    /** Moves a non-terminal order forward according to elapsed time since placement (explicit DEV simulation). */
    void advance(UUID orderId) {
        var row = db.query("""
                select status, extract(epoch from (now() - placed_at))::bigint as elapsed, placed_at, fulfillment_mode, fulfillment_type
                from transactions.food_orders where id = ? for update
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getObject(3, OffsetDateTime.class), rs.getString(4), rs.getString(5)}, orderId)
                .stream().findFirst().orElse(null);
        if (row == null || TERMINAL.contains((String) row[0])) {
            return;
        }
        if ("PARTNER".equals(row[3])) {
            // Only the partner moves these orders; the one thing the system does is the unanswered-order timeout (D-05).
            if ("PLACED".equals(row[0]) && (long) row[1] >= partnerResponseSeconds) {
                db.update("""
                        update transactions.food_orders set status = 'CANCELLED', payment_status = case when payment_method = 'DEV_NO_PAYMENT' then 'NO_PAYMENT' else 'VOIDED' end, cancelled_by = 'SYSTEM',
                            cancel_reason = 'PARTNER_TIMEOUT', updated_at = now(), version = version + 1 where id = ?
                        """, orderId);
                db.update("""
                        insert into transactions.food_order_events (order_id, status, actor_type, reason, occurred_at)
                        values (?, 'CANCELLED', 'SYSTEM', 'PARTNER_TIMEOUT', ?)
                        """, orderId, ((OffsetDateTime) row[2]).plusSeconds(partnerResponseSeconds));
                restoreStock(orderId);
            }
            return;
        }
        var sim = props.simulation();
        int[] after = {0, sim.acceptedAfterSeconds(), sim.preparingAfterSeconds(), sim.onTheWayAfterSeconds(),
                sim.deliveredAfterSeconds()};
        long elapsed = (long) row[1];
        List<String> flow = "PICKUP".equals(row[4]) ? PICKUP_FLOW : FLOW;
        int current = flow.indexOf((String) row[0]);
        if (current < 0) { return; }
        int target = current;
        for (int i = current + 1; i < flow.size(); i++) {
            if (elapsed >= after[i]) { target = i; }
        }
        for (int i = current + 1; i <= target; i++) {
            db.update("insert into transactions.food_order_events (order_id, status, occurred_at) values (?, ?, ?)",
                    orderId, flow.get(i), ((OffsetDateTime) row[2]).plusSeconds(after[i]));
        }
        if (target != current) {
            db.update("update transactions.food_orders set status = ?, updated_at = now(), version = version + 1 where id = ?",
                    flow.get(target), orderId);
        }
        // The store collects the order when it starts preparing: unavailable products are replaced or removed.
        if (current < FLOW.indexOf("PREPARING") && target >= FLOW.indexOf("PREPARING")) {
            resolveLines(orderId, ((OffsetDateTime) row[2]).plusSeconds(after[FLOW.indexOf("PREPARING")]));
        }
    }

    /**
     * Applies the customer's substitution choices to products that are no longer available. Never replaces without
     * consent (policy NONE removes the line). A replacement is never charged above the original price per unit.
     */
    void resolveLines(UUID orderId, OffsetDateTime at) {
        record Line(UUID id, UUID dishId, UUID sectionId, boolean available, String unit, long unitPrice, int quantity,
                long lineTotal, String policy, List<UUID> chosen) {}
        List<Line> lines = new ArrayList<>();
        db.query("""
                select i.id, i.dish_id, d.section_id, d.available, i.unit, i.unit_price_minor, i.quantity, i.line_total_minor,
                       i.substitution, i.substitute_dish_ids
                from transactions.food_order_items i join marketplace.food_dishes d on d.id = i.dish_id
                where i.order_id = ? and i.fulfillment_status = 'PENDING' order by i.id
                """, rs -> {
                    lines.add(new Line(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                            rs.getBoolean(4), rs.getString(5), rs.getLong(6), rs.getInt(7), rs.getLong(8), rs.getString(9),
                            uuids(rs.getArray(10))));
                }, orderId);
        boolean changed = false;
        boolean anyKept = false;
        long finalSubtotal = 0;
        for (Line l : lines) {
            if (l.available()) {
                db.update("update transactions.food_order_items set fulfillment_status = 'OK', final_unit_price_minor = ?, "
                        + "final_line_total_minor = ? where id = ?", l.unitPrice(), l.lineTotal(), l.id());
                finalSubtotal += l.lineTotal();
                anyKept = true;
                continue;
            }
            changed = true;
            Object[] replacement = null;
            if (!"NONE".equals(l.policy())) {
                List<Object[]> candidates = new ArrayList<>();
                if ("CHOSEN".equals(l.policy())) {
                    for (UUID id : l.chosen()) {
                        candidates.addAll(db.query("""
                                select id, name, price_minor from marketplace.food_dishes
                                where id = ? and available and unit = ? and (stock_qty is null or stock_qty >= ?)
                                """, (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2), rs.getLong(3)},
                                id, l.unit(), l.quantity()));
                    }
                } else {
                    candidates.addAll(db.query("""
                            select id, name, price_minor from marketplace.food_dishes
                            where section_id = ? and id <> ? and available and unit = ? and (stock_qty is null or stock_qty >= ?)
                            order by price_minor, name limit 1
                            """, (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2), rs.getLong(3)},
                            l.sectionId(), l.dishId(), l.unit(), l.quantity()));
                }
                replacement = candidates.stream().findFirst().orElse(null);
            }
            if (replacement == null) {
                db.update("update transactions.food_order_items set fulfillment_status = 'REMOVED', final_unit_price_minor = 0, "
                        + "final_line_total_minor = 0 where id = ?", l.id());
            } else {
                long unit = Math.min(l.unitPrice(), (long) replacement[2]);
                long total = lineTotal(l.unit(), unit, l.quantity());
                db.update("""
                        update transactions.food_order_items set fulfillment_status = 'SUBSTITUTED', replaced_by_dish_id = ?,
                            replaced_by_name = ?, final_unit_price_minor = ?, final_line_total_minor = ? where id = ?
                        """, replacement[0], replacement[1], unit, total, l.id());
                db.update("""
                        update marketplace.food_dishes set stock_qty = stock_qty - ? where id = ? and stock_qty is not null
                        """, l.quantity(), replacement[0]);
                finalSubtotal += total;
                anyKept = true;
            }
        }
        if (lines.isEmpty()) { return; }
        if (!anyKept) {
            db.update("""
                    update transactions.food_orders set status = 'CANCELLED', payment_status = case when payment_method = 'DEV_NO_PAYMENT' then 'NO_PAYMENT' else 'VOIDED' end, has_changes = true,
                        cancelled_by = 'SYSTEM', cancel_reason = 'NO_ITEMS_AVAILABLE', final_total_minor = 0, updated_at = now(), version = version + 1 where id = ?
                    """, orderId);
            db.update("insert into transactions.food_order_events (order_id, status, occurred_at) values (?, 'CANCELLED', ?)",
                    orderId, at);
            return;
        }
        db.update("""
                update transactions.food_orders set has_changes = ?, final_total_minor = ? + delivery_fee_minor,
                    updated_at = now() where id = ?
                """, changed, finalSubtotal, orderId);
    }

    // ---- interactive picking (Groceries) -----------------------------------------------------------

    /** True while a line still waits for the store (PENDING) or for the customer (PROPOSED). */
    boolean pickingOpen(UUID orderId) {
        Integer open = db.queryForObject("select count(*) from transactions.food_order_items where order_id = ? and fulfillment_status in ('PENDING', 'PROPOSED')",
                Integer.class, orderId);
        return open != null && open > 0;
    }

    boolean interactivePicking(UUID orderId) {
        return "GROCERY".equals(db.queryForObject("select vertical from transactions.food_orders where id = ?", String.class, orderId));
    }

    /**
     * The store's decision for one line of its own order while it is being prepared: PICKED, MISSING or REPLACE.
     * A replacement the customer pre-approved (policy ANY_SIMILAR, or CHOSEN and listed) is applied at once, never above
     * the ordered unit price; any other replacement becomes a proposal the customer must accept (price shown to them).
     */
    @Transactional
    public void pickItem(UUID partnerId, UUID orderId, UUID itemId, String action, UUID replacementDishId) {
        var order = db.query("select status, vertical from transactions.food_orders where id = ? and partner_id = ? for update",
                (rs, n) -> new String[] {rs.getString(1), rs.getString(2)}, orderId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        if (!"PREPARING".equals(order[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_NOT_PREPARING", "Lines can be picked while the order is being prepared");
        }
        var line = db.query("""
                select i.fulfillment_status, i.unit, i.unit_price_minor, i.quantity, i.line_total_minor, i.substitution,
                       i.substitute_dish_ids, d.section_id, i.dish_id
                from transactions.food_order_items i join marketplace.food_dishes d on d.id = i.dish_id
                where i.id = ? and i.order_id = ? for update of i
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getLong(3), rs.getInt(4), rs.getLong(5),
                        rs.getString(6), uuids(rs.getArray(7)), rs.getObject(8, UUID.class), rs.getObject(9, UUID.class)}, itemId, orderId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ITEM_NOT_FOUND", "Order line not found"));
        String status = (String) line[0];
        if (!"PENDING".equals(status)) {
            throw new ApiException(HttpStatus.CONFLICT, "ITEM_ALREADY_DECIDED", "This line is already decided");
        }
        String unit = (String) line[1];
        long unitPrice = (long) line[2];
        int quantity = (int) line[3];
        switch (action) {
            case "PICKED" -> db.update("update transactions.food_order_items set fulfillment_status = 'OK', final_unit_price_minor = ?, final_line_total_minor = ? where id = ?",
                    unitPrice, line[4], itemId);
            case "MISSING" -> db.update("update transactions.food_order_items set fulfillment_status = 'REMOVED', final_unit_price_minor = 0, final_line_total_minor = 0 where id = ?", itemId);
            case "REPLACE" -> {
                if (replacementDishId == null) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "REPLACEMENT_REQUIRED", "Choose a replacement product");
                }
                var repl = db.query("""
                        select name, price_minor from marketplace.food_dishes d
                        where d.id = ? and d.restaurant_id = (select restaurant_id from transactions.food_orders where id = ?)
                          and d.available and d.unit = ? and (d.stock_qty is null or d.stock_qty >= ?) and d.id <> ?
                        """, (rs, n) -> new Object[] {rs.getString(1), rs.getLong(2)}, replacementDishId, orderId, unit, quantity, line[8])
                        .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "REPLACEMENT_UNAVAILABLE",
                                "The replacement is not available in the required quantity"));
                String policy = (String) line[5];
                @SuppressWarnings("unchecked")
                List<UUID> chosen = (List<UUID>) line[6];
                boolean preApproved = "ANY_SIMILAR".equals(policy) || ("CHOSEN".equals(policy) && chosen.contains(replacementDishId));
                if (preApproved) {
                    long price = Math.min(unitPrice, (long) repl[1]);
                    db.update("""
                            update transactions.food_order_items set fulfillment_status = 'SUBSTITUTED', replaced_by_dish_id = ?, replaced_by_name = ?,
                                final_unit_price_minor = ?, final_line_total_minor = ? where id = ?
                            """, replacementDishId, repl[0], price, lineTotal(unit, price, quantity), itemId);
                    db.update("update marketplace.food_dishes set stock_qty = stock_qty - ? where id = ? and stock_qty is not null", quantity, replacementDishId);
                } else {
                    db.update("""
                            update transactions.food_order_items set fulfillment_status = 'PROPOSED', proposed_dish_id = ?, proposed_name = ?,
                                proposed_unit_price_minor = ? where id = ?
                            """, replacementDishId, repl[0], repl[1], itemId);
                }
            }
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "ACTION_INVALID", "action must be PICKED, MISSING or REPLACE");
        }
        finalizeIfComplete(orderId);
    }

    /** The customer's answer to a proposed replacement: accept (charged at the proposed price) or decline (the line is removed). */
    @Transactional
    public OrderView decideReplacement(UUID user, UUID orderId, UUID itemId, boolean approve) {
        requireOwned(user, orderId);
        db.query("select 1 from transactions.food_orders where id = ? for update", (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, orderId);
        var line = db.query("""
                select fulfillment_status, unit, quantity, proposed_dish_id, proposed_name, proposed_unit_price_minor
                from transactions.food_order_items where id = ? and order_id = ? for update
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getInt(3), rs.getObject(4, UUID.class),
                        rs.getString(5), rs.getLong(6)}, itemId, orderId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ITEM_NOT_FOUND", "Order line not found"));
        if (!"PROPOSED".equals(line[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "NO_PROPOSAL", "There is no replacement waiting for your answer");
        }
        if (approve) {
            String unit = (String) line[1];
            int quantity = (int) line[2];
            long price = (long) line[5];
            Integer ok = db.update("""
                    update marketplace.food_dishes set stock_qty = stock_qty - ? where id = ? and available and (stock_qty is null or stock_qty >= ?)
                    """, quantity, line[3], quantity);
            if (ok == 0) {
                throw new ApiException(HttpStatus.CONFLICT, "REPLACEMENT_UNAVAILABLE", "The replacement is no longer available");
            }
            db.update("""
                    update transactions.food_order_items set fulfillment_status = 'SUBSTITUTED', replaced_by_dish_id = proposed_dish_id,
                        replaced_by_name = proposed_name, final_unit_price_minor = ?, final_line_total_minor = ?,
                        proposed_dish_id = null, proposed_name = null, proposed_unit_price_minor = null where id = ?
                    """, price, lineTotal(unit, price, quantity), itemId);
        } else {
            db.update("""
                    update transactions.food_order_items set fulfillment_status = 'REMOVED', final_unit_price_minor = 0, final_line_total_minor = 0,
                        proposed_dish_id = null, proposed_name = null, proposed_unit_price_minor = null where id = ?
                    """, itemId);
        }
        finalizeIfComplete(orderId);
        return views(List.of(orderId), user).get(0);
    }

    /** When no line waits any more: totals follow the final lines; an order with nothing left is cancelled (stock and promo released). */
    private void finalizeIfComplete(UUID orderId) {
        if (pickingOpen(orderId)) { return; }
        var sums = db.queryForObject("""
                select coalesce(sum(final_line_total_minor) filter (where fulfillment_status in ('OK', 'SUBSTITUTED')), 0),
                       count(*) filter (where fulfillment_status in ('OK', 'SUBSTITUTED')),
                       bool_or(fulfillment_status <> 'OK' or final_line_total_minor <> line_total_minor)
                from transactions.food_order_items where order_id = ?
                """, (rs, n) -> new Object[] {rs.getLong(1), rs.getInt(2), rs.getBoolean(3)}, orderId);
        if ((int) sums[1] == 0) {
            restoreStock(orderId);
            db.update("""
                    update transactions.food_orders set status = 'CANCELLED', payment_status = case when payment_method = 'DEV_NO_PAYMENT' then 'NO_PAYMENT' else 'VOIDED' end,
                        has_changes = true, cancelled_by = 'SYSTEM', cancel_reason = 'NO_ITEMS_AVAILABLE', final_total_minor = 0, updated_at = now(), version = version + 1 where id = ?
                    """, orderId);
            db.update("insert into transactions.food_order_events (order_id, status, actor_type, reason) values (?, 'CANCELLED', 'SYSTEM', 'NO_ITEMS_AVAILABLE')", orderId);
            return;
        }
        db.update("update transactions.food_orders set has_changes = ?, final_total_minor = ? + delivery_fee_minor, updated_at = now() where id = ?",
                sums[2], sums[0], orderId);
    }

    // ---- views -----------------------------------------------------------------------------------

    private void requireOwned(UUID user, UUID orderId) {
        Integer found = db.queryForObject("select count(*) from transactions.food_orders where id = ? and user_id = ?",
                Integer.class, orderId, user);
        if (found == null || found == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found");
        }
    }

    List<OrderView> views(List<UUID> ids, UUID user) {
        if (ids.isEmpty()) { return List.of(); }
        UUID[] array = ids.toArray(UUID[]::new);
        Map<UUID, List<OrderLine>> items = new HashMap<>();
        db.query("""
                select order_id, id, dish_id, dish_name, options_text, unit, unit_price_minor, quantity, line_total_minor,
                       substitution, fulfillment_status, replaced_by_name, final_line_total_minor, proposed_name, proposed_unit_price_minor
                from transactions.food_order_items where order_id = any (?) order by line_no, id
                """, rs -> {
                    items.computeIfAbsent(rs.getObject("order_id", UUID.class), k -> new ArrayList<>()).add(new OrderLine(
                            rs.getString("id"), rs.getString("dish_id"), rs.getString("dish_name"), rs.getString("options_text"),
                            rs.getString("unit"), rs.getLong("unit_price_minor"), rs.getInt("quantity"),
                            rs.getLong("line_total_minor"), rs.getString("substitution"),
                            rs.getString("fulfillment_status"), rs.getString("replaced_by_name"),
                            rs.getObject("final_line_total_minor", Long.class), rs.getString("proposed_name"),
                            rs.getObject("proposed_unit_price_minor", Long.class)));
                }, (Object) array);
        Map<UUID, List<TimelineEntry>> timeline = new HashMap<>();
        db.query("select order_id, status, occurred_at, actor_type, reason from transactions.food_order_events where order_id = any (?) order by id",
                rs -> {
                    timeline.computeIfAbsent(rs.getObject("order_id", UUID.class), k -> new ArrayList<>())
                            .add(new TimelineEntry(rs.getString("status"), rs.getObject("occurred_at", OffsetDateTime.class),
                                    rs.getString("actor_type"), rs.getString("reason")));
                }, (Object) array);
        Map<UUID, OrderView> byId = new LinkedHashMap<>();
        db.query("""
                select id, restaurant_id, restaurant_name, status, payment_method, payment_status, currency,
                       subtotal_minor, delivery_fee_minor, total_minor, address_label, address_text, comment, placed_at, vertical,
                       final_total_minor, has_changes, fulfillment_mode, cancelled_by, cancel_reason,
                       fulfillment_type, discount_minor, promo_code,
                       exists (select 1 from marketplace.food_reviews v where v.order_id = food_orders.id) as reviewed
                from transactions.food_orders where (?::uuid is null or user_id = ?::uuid) and id = any (?)
                """, rs -> {
                    UUID id = rs.getObject("id", UUID.class);
                    byId.put(id, new OrderView(id.toString(), rs.getString("restaurant_id"), rs.getString("restaurant_name"),
                            rs.getString("status"), rs.getString("payment_method"), rs.getString("payment_status"),
                            rs.getString("currency"), rs.getLong("subtotal_minor"), rs.getLong("delivery_fee_minor"),
                            rs.getLong("total_minor"), rs.getString("address_label"), rs.getString("address_text"),
                            rs.getString("comment"), rs.getObject("placed_at", OffsetDateTime.class),
                            items.getOrDefault(id, List.of()), timeline.getOrDefault(id, List.of()),
                            "PLACED".equals(rs.getString("status")), "SIMULATED".equals(rs.getString("fulfillment_mode")),
                            rs.getString("vertical"), rs.getObject("final_total_minor", Long.class), rs.getBoolean("has_changes"),
                            rs.getString("fulfillment_mode"), rs.getString("cancelled_by"), rs.getString("cancel_reason"),
                            rs.getString("fulfillment_type"), rs.getLong("discount_minor"), rs.getString("promo_code"),
                            rs.getBoolean("reviewed")));
                }, user, user, array);
        return ids.stream().map(byId::get).filter(java.util.Objects::nonNull).toList();
    }
}
