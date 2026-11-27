package kz.kunde.flowers;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Flowers &amp; Gifts cart quote, checkout and the customer's order history (ADR-026 step 3). The server prices every line,
 * the customer's expected total is checked, stock is reserved atomically, checkout is idempotent per user and key.
 * Payments stay disabled (DEV_NO_PAYMENT). Shop-side status changes and couriers arrive in later steps.
 */
@Service
public class FlowersOrderService {
    static final ZoneId ZONE = ZoneId.of("Asia/Almaty");
    static final int MAX_ACTIVE_ORDERS = 5;
    static final int MAX_LINES = 20;
    /** Delivery windows of the «к определённому времени» mode: two hours, 10:00-20:00 local time, at least two hours ahead. */
    static final int FIRST_HOUR = 10;
    static final int LAST_HOUR = 20;
    static final int WINDOW_HOURS = 2;
    static final Duration LEAD = Duration.ofHours(2);
    static final int MAX_DAYS_AHEAD = 14;

    private final JdbcTemplate db;
    private final PartnerDirectory partners;

    public FlowersOrderService(JdbcTemplate db, PartnerDirectory partners) {
        this.db = db;
        this.partners = partners;
    }

    public record ItemRequest(UUID productId, int quantity) {}

    public record Slot(Instant startsAt, Instant endsAt) {}

    public record Line(String productId, String name, String emoji, long unitPriceMinor, int quantity, long lineTotalMinor) {}

    public record Quote(String shopId, String shopName, List<Line> lines, long subtotalMinor, long deliveryFeeMinor, long totalMinor,
            long minOrderMinor, String deliveryMode, Instant scheduledFrom, Instant scheduledTo) {}

    public record OrderView(String id, String shopId, String shopName, String status, String paymentMethod, String paymentStatus,
            long subtotalMinor, long deliveryFeeMinor, long totalMinor, String deliveryMode, Instant scheduledFrom, Instant scheduledTo,
            String addressLabel, String addressText, String recipientName, String cardText, String comment, Instant placedAt,
            List<Line> items, List<Event> events) {}

    public record Event(String status, Instant occurredAt) {}

    public record Placed(OrderView order, boolean created) {}

    private record ShopRow(UUID id, String name, long deliveryFee, long minOrder, boolean open, boolean visible) {}

    // ---- delivery windows -------------------------------------------------------------------------------------------

    /** Free windows of one local date: future ones only, with the lead time, within {@link #MAX_DAYS_AHEAD} days. */
    public List<Slot> slots(LocalDate date, Instant now) {
        List<Slot> slots = new ArrayList<>();
        LocalDate today = now.atZone(ZONE).toLocalDate();
        if (date.isBefore(today) || date.isAfter(today.plusDays(MAX_DAYS_AHEAD))) {
            return slots;
        }
        for (int hour = FIRST_HOUR; hour + WINDOW_HOURS <= LAST_HOUR; hour += WINDOW_HOURS) {
            ZonedDateTime from = ZonedDateTime.of(date, LocalTime.of(hour, 0), ZONE);
            if (!from.toInstant().isBefore(now.plus(LEAD))) {
                slots.add(new Slot(from.toInstant(), from.plusHours(WINDOW_HOURS).toInstant()));
            }
        }
        return slots;
    }

    private Slot requireSlot(Instant startsAt, Instant now) {
        return slots(startsAt.atZone(ZONE).toLocalDate(), now).stream().filter(s -> s.startsAt().equals(startsAt)).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FLOWERS_SLOT_UNAVAILABLE",
                        "Choose one of the offered delivery windows"));
    }

    // ---- quote ------------------------------------------------------------------------------------------------------

    private ShopRow shop(UUID shopId, boolean lock) {
        var approved = partners.approvedPartnerIds();
        return db.query("select id, name, delivery_fee_minor, min_order_minor, is_open, is_synthetic, partner_id from marketplace.flowers_shops where id = ?"
                + (lock ? " for share" : ""), (rs, row) -> new ShopRow(rs.getObject("id", UUID.class), rs.getString("name"),
                rs.getLong("delivery_fee_minor"), rs.getLong("min_order_minor"), rs.getBoolean("is_open"),
                rs.getBoolean("is_synthetic") || approved.contains(rs.getObject("partner_id", UUID.class))), shopId)
                .stream().findFirst().filter(ShopRow::visible)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FLOWERS_SHOP_NOT_FOUND", "Shop not found"));
    }

    @Transactional(readOnly = true)
    public Quote quote(UUID shopId, List<ItemRequest> items, String deliveryMode, Instant scheduledFrom) {
        return price(shop(shopId, false), items, deliveryMode, scheduledFrom, Instant.now());
    }

    private Quote price(ShopRow shop, List<ItemRequest> items, String deliveryMode, Instant scheduledFrom, Instant now) {
        if (items == null || items.isEmpty() || items.size() > MAX_LINES) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "FLOWERS_CART_INVALID", "Cart must have 1 to " + MAX_LINES + " lines");
        }
        Slot slot = null;
        if ("SCHEDULED".equals(deliveryMode)) {
            if (scheduledFrom == null) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "FLOWERS_SLOT_REQUIRED", "Choose a delivery window");
            }
            slot = requireSlot(scheduledFrom, now);
        } else if ("ASAP".equals(deliveryMode)) {
            if (!shop.open()) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FLOWERS_SHOP_CLOSED", "The shop is closed; choose a delivery window");
            }
        } else {
            throw new ApiException(HttpStatus.BAD_REQUEST, "FLOWERS_DELIVERY_MODE_INVALID", "deliveryMode must be ASAP or SCHEDULED");
        }
        var seen = new java.util.HashSet<UUID>();
        List<Line> lines = new ArrayList<>();
        long subtotal = 0;
        for (ItemRequest item : items) {
            if (item.productId() == null || item.quantity() < 1 || item.quantity() > 20 || !seen.add(item.productId())) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "FLOWERS_CART_INVALID", "Each product once, quantity 1 to 20");
            }
            var row = db.query("select name, emoji, price_minor, available, stock_qty from marketplace.flowers_products where id = ? and shop_id = ?",
                    (rs, i) -> new Object[] {rs.getString(1), rs.getString(2), rs.getLong(3), rs.getBoolean(4), rs.getObject(5, Integer.class)},
                    item.productId(), shop.id()).stream().findFirst()
                    .orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FLOWERS_PRODUCT_UNAVAILABLE", "A product is not sold by this shop"));
            Integer stock = (Integer) row[4];
            if (!(Boolean) row[3] || (stock != null && stock < item.quantity())) {
                throw new ApiException(HttpStatus.CONFLICT, "FLOWERS_STOCK_INSUFFICIENT", "Not enough in stock: " + row[0]);
            }
            long unit = (Long) row[2];
            long lineTotal = unit * item.quantity();
            subtotal += lineTotal;
            lines.add(new Line(item.productId().toString(), (String) row[0], (String) row[1], unit, item.quantity(), lineTotal));
        }
        if (subtotal < shop.minOrder()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FLOWERS_MIN_ORDER", "The order is below the shop minimum");
        }
        return new Quote(shop.id().toString(), shop.name(), lines, subtotal, shop.deliveryFee(), subtotal + shop.deliveryFee(),
                shop.minOrder(), deliveryMode, slot == null ? null : slot.startsAt(), slot == null ? null : slot.endsAt());
    }

    // ---- checkout ---------------------------------------------------------------------------------------------------

    public record OrderRequest(UUID shopId, List<ItemRequest> items, String deliveryMode, Instant scheduledFrom, String addressLabel,
            String addressText, String recipientName, String cardText, String comment, Long expectedTotalMinor) {}

    private static String clean(String value, int max) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String v = value.strip();
        if (v.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "FLOWERS_FIELD_TOO_LONG", "A text field is too long");
        }
        return v;
    }

    @Transactional
    public Placed place(UUID user, OrderRequest request, String idempotencyKey) {
        if (idempotencyKey == null || idempotencyKey.isBlank() || idempotencyKey.length() > 64) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key header is required (1 to 64 characters)");
        }
        db.query("select pg_advisory_xact_lock(hashtext('flowers-order'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        var existing = db.query("select id, shop_id from transactions.flowers_orders where user_id = ? and idempotency_key = ?",
                (rs, row) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class)}, user, idempotencyKey).stream().findFirst();
        if (existing.isPresent()) {
            if (!existing.get()[1].equals(request.shopId())) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "Idempotency-Key was already used for a different order");
            }
            return new Placed(view((UUID) existing.get()[0], user), false);
        }
        Integer active = db.queryForObject("select count(*) from transactions.flowers_orders where user_id = ? and status not in ('DELIVERED', 'CANCELLED')",
                Integer.class, user);
        if (active != null && active >= MAX_ACTIVE_ORDERS) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_ACTIVE_ORDERS", "Too many active orders");
        }
        String address = clean(request.addressText(), 500);
        if (address == null || address.length() < 5) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "ADDRESS_REQUIRED", "Enter a delivery address (5+ characters)");
        }
        Quote quote = price(shop(request.shopId(), true), request.items(), request.deliveryMode(), request.scheduledFrom(), Instant.now());
        if (request.expectedTotalMinor() == null || request.expectedTotalMinor() != quote.totalMinor()) {
            throw new ApiException(HttpStatus.CONFLICT, "FLOWERS_PRICE_CHANGED", "The total changed; refresh the cart");
        }
        for (Line line : quote.lines()) {
            int reserved = db.update("update marketplace.flowers_products set stock_qty = stock_qty - ? where id = ? and available and (stock_qty is null or stock_qty >= ?)",
                    line.quantity(), UUID.fromString(line.productId()), line.quantity());
            if (reserved == 0) {
                throw new ApiException(HttpStatus.CONFLICT, "FLOWERS_STOCK_INSUFFICIENT", "Not enough in stock");
            }
        }
        String label = clean(request.addressLabel(), 80);
        UUID orderId = db.queryForObject("""
                insert into transactions.flowers_orders (user_id, shop_id, shop_name, subtotal_minor, delivery_fee_minor, total_minor, delivery_mode,
                    scheduled_from, scheduled_to, address_label, address_text, recipient_name, card_text, comment, idempotency_key)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                """, UUID.class, user, request.shopId(), quote.shopName(), quote.subtotalMinor(), quote.deliveryFeeMinor(), quote.totalMinor(),
                quote.deliveryMode(), quote.scheduledFrom() == null ? null : java.sql.Timestamp.from(quote.scheduledFrom()),
                quote.scheduledTo() == null ? null : java.sql.Timestamp.from(quote.scheduledTo()), label == null ? "" : label, address,
                clean(request.recipientName(), 80), clean(request.cardText(), 300), clean(request.comment(), 300), idempotencyKey);
        for (Line line : quote.lines()) {
            db.update("insert into transactions.flowers_order_items (order_id, product_id, product_name, emoji, unit_price_minor, quantity, line_total_minor) values (?, ?, ?, ?, ?, ?, ?)",
                    orderId, UUID.fromString(line.productId()), line.name(), line.emoji(), line.unitPriceMinor(), line.quantity(), line.lineTotalMinor());
        }
        db.update("insert into transactions.flowers_order_events (order_id, status, actor_type, actor_user_id) values (?, 'PLACED', 'CUSTOMER', ?)", orderId, user);
        return new Placed(view(orderId, user), true);
    }

    // ---- reads and cancellation ---------------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<OrderView> list(UUID user, int limit, int offset) {
        return db.queryForList("select id from transactions.flowers_orders where user_id = ? order by placed_at desc, id limit ? offset ?",
                UUID.class, user, limit, offset).stream().map(id -> view(id, user)).toList();
    }

    @Transactional(readOnly = true)
    public OrderView get(UUID user, UUID orderId) {
        return view(orderId, user);
    }

    /** Free cancellation only before the shop accepts the order; the reserved stock goes back to the shelf. */
    @Transactional
    public OrderView cancel(UUID user, UUID orderId) {
        view(orderId, user);
        String status = db.queryForObject("select status from transactions.flowers_orders where id = ? for update", String.class, orderId);
        if (!"PLACED".equals(status)) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_NOT_CANCELLABLE", "The shop has already accepted this order");
        }
        db.update("update transactions.flowers_orders set status = 'CANCELLED', updated_at = now(), version = version + 1 where id = ?", orderId);
        db.update("insert into transactions.flowers_order_events (order_id, status, actor_type, actor_user_id) values (?, 'CANCELLED', 'CUSTOMER', ?)", orderId, user);
        db.update("""
                update marketplace.flowers_products p set stock_qty = p.stock_qty + i.quantity
                from transactions.flowers_order_items i where i.order_id = ? and i.product_id = p.id and p.stock_qty is not null
                """, orderId);
        return view(orderId, user);
    }

    private OrderView view(UUID orderId, UUID user) {
        return db.query("""
                select id, shop_id, shop_name, status, payment_method, payment_status, subtotal_minor, delivery_fee_minor, total_minor, delivery_mode,
                       scheduled_from, scheduled_to, address_label, address_text, recipient_name, card_text, comment, placed_at
                from transactions.flowers_orders where id = ? and user_id = ?
                """, (rs, row) -> new OrderView(rs.getString("id"), rs.getString("shop_id"), rs.getString("shop_name"), rs.getString("status"),
                rs.getString("payment_method"), rs.getString("payment_status"), rs.getLong("subtotal_minor"), rs.getLong("delivery_fee_minor"),
                rs.getLong("total_minor"), rs.getString("delivery_mode"),
                rs.getTimestamp("scheduled_from") == null ? null : rs.getTimestamp("scheduled_from").toInstant(),
                rs.getTimestamp("scheduled_to") == null ? null : rs.getTimestamp("scheduled_to").toInstant(),
                rs.getString("address_label"), rs.getString("address_text"), rs.getString("recipient_name"), rs.getString("card_text"),
                rs.getString("comment"), rs.getTimestamp("placed_at").toInstant(),
                db.query("select product_id, product_name, emoji, unit_price_minor, quantity, line_total_minor from transactions.flowers_order_items where order_id = ? order by id",
                        (r, i) -> new Line(r.getString(1), r.getString(2), r.getString(3), r.getLong(4), r.getInt(5), r.getLong(6)), orderId),
                db.query("select status, occurred_at from transactions.flowers_order_events where order_id = ? order by id",
                        (r, i) -> new Event(r.getString(1), r.getTimestamp(2).toInstant()), orderId)), orderId, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
    }
}
