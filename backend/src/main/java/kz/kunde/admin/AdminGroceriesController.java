package kz.kunde.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.food.FoodPromotionService;
import kz.kunde.food.FoodPromotionService.PromotionView;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Groceries Control Center. Scoped by its own {@code GROCERIES_OPERATIONS} grant: it sees and changes only stores, orders,
 * promotions, reviews and catalog data of the Groceries vertical, never the Food restaurants. Every number comes from real
 * orders (an empty database yields zeros); no customer name, phone or address is returned; changes go to the append-only audit.
 */
@RestController
@RequestMapping("/api/v1/admin/groceries")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.food.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminGroceriesController {
    public record Day(LocalDate day, long orders, long revenueMinor) {}

    public record StatusCount(String status, long count) {}

    public record CategorySales(String category, long itemsSold, long revenueMinor) {}

    public record Summary(long stores, long openStores, long blockedStores, long orders, long deliveredOrders, long cancelledOrders,
            long activeOrders, long revenueMinor, long averageCheckMinor, long deliveryOrders, long pickupOrders, long refundedMinor,
            long changedOrders, long problemOrders, long openComplaints, long lowStockProducts, long outOfStockProducts,
            long uncategorizedProducts, long openCourierTasks, long activeCourierTasks, long deliveredCourierTasks,
            List<Day> perDay, List<StatusCount> statuses, List<CategorySales> categories) {}

    public record OrderRow(String id, String store, String status, String fulfillmentType, String paymentMethod, String paymentStatus,
            long totalMinor, long refundedMinor, boolean hasChanges, String customerRef, String cancelledBy, String cancelReason,
            OffsetDateTime placedAt) {}

    public record StoreRow(String id, String name, String partner, boolean open, String moderationStatus, String moderationNote,
            Double ratingAvg, int ratingCount, long orders, long products, boolean synthetic) {}

    public record ProductRow(String id, String name, String store, String category, String unit, Integer stockQty, boolean available,
            String problem) {}

    public record ReviewRow(String id, String store, int rating, String comment, String status, int complaints, OffsetDateTime createdAt) {}

    public record ComplaintRow(String id, String reviewId, String store, String reviewComment, String reason, String status, OffsetDateTime createdAt) {}

    public record AuditRow(long id, String actorType, String action, String target, String detail, OffsetDateTime at) {}

    public record ModerationBody(@NotNull @Pattern(regexp = "BLOCK|UNBLOCK") String decision, @NotBlank @Size(min = 3, max = 200) String reason) {}

    public record PromoStatusBody(@NotNull @Pattern(regexp = "ACTIVE|PAUSED|DISABLED") String status, @Size(max = 200) String reason) {}

    public record ReviewBody(@NotNull @Pattern(regexp = "HIDE|SHOW") String decision, @NotBlank @Size(min = 3, max = 200) String reason) {}

    public record ResolveBody(@NotBlank @Size(min = 3, max = 200) String resolution) {}

    public record RefundBody(@NotBlank @Size(min = 3, max = 200) String reason) {}

    /** A product counts as low on stock at 5 pieces or 2 kg (stock of weighed goods is counted in grams). */
    private static final String LOW = "(d.stock_qty is not null and d.stock_qty > 0 and ((d.unit = 'PIECE' and d.stock_qty <= 5) or (d.unit = 'KG' and d.stock_qty <= 2000)))";
    private static final String OUT = "(d.stock_qty is not null and d.stock_qty = 0)";

    private final JdbcTemplate db;
    private final AdminGrants grants;
    private final FoodPromotionService promotions;

    public AdminGroceriesController(JdbcTemplate db, AdminGrants grants, FoodPromotionService promotions) {
        this.db = db;
        this.grants = grants;
        this.promotions = promotions;
    }

    private UUID admin(Jwt principal) {
        UUID id = PartnerAccessPolicy.userId(principal).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(id, Permission.GROCERIES_OPERATIONS);
        return id;
    }

    private static <T> ResponseEntity<T> ok(T body) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body); }

    private void audit(UUID admin, String action, String target, String detail) {
        db.update("insert into marketplace.food_audit (actor_user_id, actor_type, action, target, detail) values (?, 'ADMIN', ?, ?, ?)",
                admin, action, target, detail == null ? "" : detail);
    }

    private void requireGroceryOrder(UUID orderId) {
        Integer n = db.queryForObject("select count(*) from transactions.food_orders where id = ? and vertical = 'GROCERY'", Integer.class, orderId);
        if (n == null || n == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"); }
    }

    @GetMapping("/summary")
    ResponseEntity<Summary> summary(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "7") int days) {
        admin(principal);
        int d = Math.max(1, Math.min(days, 60));
        long[] r = db.query("""
                select count(*), count(*) filter (where is_open and moderation_status = 'ACTIVE'), count(*) filter (where moderation_status = 'BLOCKED')
                from marketplace.food_restaurants where vertical = 'GROCERY'""", (rs, n) -> new long[] {rs.getLong(1), rs.getLong(2), rs.getLong(3)}).get(0);
        long[] t = db.query("""
                select count(*), count(*) filter (where status = 'DELIVERED'), count(*) filter (where status = 'CANCELLED'),
                       count(*) filter (where status not in ('DELIVERED', 'CANCELLED')),
                       coalesce(sum(coalesce(final_total_minor, total_minor)) filter (where status = 'DELIVERED'), 0),
                       count(*) filter (where fulfillment_type = 'DELIVERY'), count(*) filter (where fulfillment_type = 'PICKUP'),
                       coalesce(sum(refunded_minor), 0), count(*) filter (where has_changes),
                       count(*) filter (where status = 'CANCELLED' and cancelled_by = 'SYSTEM')
                from transactions.food_orders where vertical = 'GROCERY' and placed_at > now() - make_interval(days => ?)""",
                (rs, n) -> {
                    long[] a = new long[10];
                    for (int i = 0; i < 10; i++) { a[i] = rs.getLong(i + 1); }
                    return a;
                }, d).get(0);
        long complaints = db.queryForObject("""
                select count(*) from marketplace.food_review_complaints c join marketplace.food_reviews v on v.id = c.review_id
                join marketplace.food_restaurants r on r.id = v.restaurant_id where c.status = 'OPEN' and r.vertical = 'GROCERY'""", Long.class);
        long[] stock = db.query("""
                select count(*) filter (where %s), count(*) filter (where %s), count(*) filter (where d.grocery_category is null)
                from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id where r.vertical = 'GROCERY'
                """.formatted(LOW, OUT), (rs, n) -> new long[] {rs.getLong(1), rs.getLong(2), rs.getLong(3)}).get(0);
        long[] tasks = db.query("""
                select count(*) filter (where t.status = 'OPEN'), count(*) filter (where t.status in ('ASSIGNED', 'PICKED_UP')),
                       count(*) filter (where t.status = 'DELIVERED' and t.delivered_at > now() - make_interval(days => ?))
                from transactions.food_courier_tasks t join transactions.food_orders o on o.id = t.order_id where o.vertical = 'GROCERY'
                """, (rs, n) -> new long[] {rs.getLong(1), rs.getLong(2), rs.getLong(3)}, d).get(0);
        List<Day> perDay = db.query("""
                select g::date, count(o.id), coalesce(sum(coalesce(o.final_total_minor, o.total_minor)) filter (where o.status = 'DELIVERED'), 0)
                from generate_series((now() at time zone 'Asia/Almaty')::date - (? - 1), (now() at time zone 'Asia/Almaty')::date, interval '1 day') g
                left join transactions.food_orders o on o.vertical = 'GROCERY' and (o.placed_at at time zone 'Asia/Almaty')::date = g::date
                group by g order by g""", (rs, n) -> new Day(rs.getDate(1).toLocalDate(), rs.getLong(2), rs.getLong(3)), d);
        List<StatusCount> statuses = db.query("""
                select status, count(*) from transactions.food_orders where vertical = 'GROCERY' and placed_at > now() - make_interval(days => ?)
                group by status order by count(*) desc""", (rs, n) -> new StatusCount(rs.getString(1), rs.getLong(2)), d);
        List<CategorySales> categories = db.query("""
                select coalesce(dd.grocery_category, 'other'), count(*), coalesce(sum(i.final_line_total_minor), 0)
                from transactions.food_order_items i join transactions.food_orders o on o.id = i.order_id
                join marketplace.food_dishes dd on dd.id = coalesce(i.replaced_by_dish_id, i.dish_id)
                where o.vertical = 'GROCERY' and o.status = 'DELIVERED' and i.fulfillment_status in ('OK', 'SUBSTITUTED')
                  and o.placed_at > now() - make_interval(days => ?)
                group by 1 order by 3 desc""", (rs, n) -> new CategorySales(rs.getString(1), rs.getLong(2), rs.getLong(3)), d);
        long avg = t[1] == 0 ? 0 : t[4] / t[1];
        return ok(new Summary(r[0], r[1], r[2], t[0], t[1], t[2], t[3], t[4], avg, t[5], t[6], t[7], t[8], t[9], complaints, stock[0], stock[1],
                stock[2], tasks[0], tasks[1], tasks[2], perDay, statuses, categories));
    }

    @GetMapping("/orders")
    ResponseEntity<List<OrderRow>> orders(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "50") int limit) {
        admin(principal);
        return ok(orderRows(null, status, limit));
    }

    private List<OrderRow> orderRows(UUID only, String status, int limit) {
        return db.query("""
                select id, restaurant_name, status, fulfillment_type, payment_method, payment_status, coalesce(final_total_minor, total_minor), refunded_minor,
                       has_changes, left(user_id::text, 8), cancelled_by, cancel_reason, placed_at
                from transactions.food_orders where vertical = 'GROCERY' and (?::uuid is null or id = ?::uuid)
                  and (?::text is null or status = ?::text) order by placed_at desc limit ?""",
                (rs, n) -> new OrderRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                        rs.getLong(7), rs.getLong(8), rs.getBoolean(9), rs.getString(10), rs.getString(11), rs.getString(12),
                        rs.getObject(13, OffsetDateTime.class)), only, only, status, status, Math.max(1, Math.min(limit, 200)));
    }

    /** Test refund (DEV ledger only, no money moves) of a paid test-card Groceries order that is delivered or cancelled. Idempotent. */
    @Transactional
    @PostMapping("/orders/{orderId}/refund")
    ResponseEntity<OrderRow> refund(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId, @Valid @RequestBody RefundBody body) {
        UUID admin = admin(principal);
        requireGroceryOrder(orderId);
        var row = db.query("select status, payment_method, payment_status from transactions.food_orders where id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getString(3)}, orderId).get(0);
        if (!"REFUNDED".equals(row[2])) {
            if (!"TEST_CARD".equals(row[1]) || !"TEST_PAID".equals(row[2])) {
                throw new ApiException(HttpStatus.CONFLICT, "REFUND_NOT_AVAILABLE", "Only a paid test-card order can be refunded");
            }
            if (!"DELIVERED".equals(row[0]) && !"CANCELLED".equals(row[0])) {
                throw new ApiException(HttpStatus.CONFLICT, "REFUND_NOT_AVAILABLE", "The order is still in progress");
            }
            db.update("update transactions.food_orders set payment_status = 'REFUNDED', refunded_minor = coalesce(final_total_minor, total_minor), refund_reason = ?, updated_at = now(), version = version + 1 where id = ?",
                    body.reason().strip(), orderId);
            audit(admin, "ORDER_REFUNDED", orderId.toString(), body.reason().strip());
        }
        return ok(orderRows(orderId, null, 1).get(0));
    }

    @GetMapping("/stores")
    ResponseEntity<List<StoreRow>> stores(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(storeRows());
    }

    private List<StoreRow> storeRows() {
        return db.query("""
                select r.id, r.name, p.display_name, r.is_open, r.moderation_status, r.moderation_note,
                       (select round(avg(v.rating)::numeric, 1)::float8 from marketplace.food_reviews v where v.restaurant_id = r.id and v.status = 'VISIBLE'),
                       (select count(*) from marketplace.food_reviews v where v.restaurant_id = r.id and v.status = 'VISIBLE'),
                       (select count(*) from transactions.food_orders o where o.restaurant_id = r.id),
                       (select count(*) from marketplace.food_dishes d where d.restaurant_id = r.id), r.is_synthetic
                from marketplace.food_restaurants r left join marketplace.partners p on p.id = r.partner_id
                where r.vertical = 'GROCERY' order by r.name limit 300""",
                (rs, n) -> new StoreRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getBoolean(4), rs.getString(5), rs.getString(6),
                        rs.getObject(7, Double.class), rs.getInt(8), rs.getLong(9), rs.getLong(10), rs.getBoolean(11)));
    }

    @Transactional
    @PostMapping("/stores/{id}/moderation")
    ResponseEntity<List<StoreRow>> moderate(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ModerationBody body) {
        UUID admin = admin(principal);
        String to = "BLOCK".equals(body.decision()) ? "BLOCKED" : "ACTIVE";
        String from = db.query("select moderation_status from marketplace.food_restaurants where id = ? and vertical = 'GROCERY' for update", (rs, n) -> rs.getString(1), id)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "STORE_NOT_FOUND", "Store not found"));
        if (from.equals(to)) { throw new ApiException(HttpStatus.CONFLICT, "MODERATION_NO_CHANGE", "The store is already " + to); }
        db.update("update marketplace.food_restaurants set moderation_status = ?, moderation_note = ? where id = ?", to, body.reason().strip(), id);
        audit(admin, "STORE_" + body.decision(), id.toString(), body.reason().strip());
        return ok(storeRows());
    }

    /** Catalog and stock problems: out of stock, low stock, unavailable and products without a category. */
    @GetMapping("/catalog/problems")
    ResponseEntity<List<ProductRow>> problems(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(db.query("""
                select * from (
                  select d.id, d.name, r.name as store, d.grocery_category, d.unit, d.stock_qty, d.available,
                         case when %s then 'OUT_OF_STOCK' when %s then 'LOW_STOCK' when not d.available then 'UNAVAILABLE'
                              when d.grocery_category is null then 'NO_CATEGORY' end as problem
                  from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id where r.vertical = 'GROCERY') x
                where problem is not null order by case problem when 'OUT_OF_STOCK' then 0 when 'LOW_STOCK' then 1 when 'UNAVAILABLE' then 2 else 3 end, store, name limit 200
                """.formatted(OUT, LOW), (rs, n) -> new ProductRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                rs.getObject(6, Integer.class), rs.getBoolean(7), rs.getString(8))));
    }

    /** Promotions of Groceries stores only (platform-wide Food promotions are outside this scope). */
    @GetMapping("/promotions")
    ResponseEntity<List<PromotionView>> promotions(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status) {
        admin(principal);
        return ok(promotions.all(status).stream().filter(p -> p.restaurantId() != null && groceryStore(UUID.fromString(p.restaurantId()))).toList());
    }

    private boolean groceryStore(UUID id) {
        Integer n = db.queryForObject("select count(*) from marketplace.food_restaurants where id = ? and vertical = 'GROCERY'", Integer.class, id);
        return n != null && n > 0;
    }

    @PostMapping("/promotions/{id}/status")
    ResponseEntity<PromotionView> promotionStatus(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody PromoStatusBody body) {
        UUID admin = admin(principal);
        Integer scoped = db.queryForObject("select count(*) from marketplace.food_promotions p join marketplace.food_restaurants r on r.id = p.restaurant_id where p.id = ? and r.vertical = 'GROCERY'", Integer.class, id);
        if (scoped == null || scoped == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "PROMO_NOT_FOUND", "Promotion not found"); }
        return ok(promotions.adminSetStatus(admin, id, body.status(), body.reason()));
    }

    @GetMapping("/reviews")
    ResponseEntity<List<ReviewRow>> reviews(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status) {
        admin(principal);
        return ok(reviewRows(status));
    }

    private List<ReviewRow> reviewRows(String status) {
        return db.query("""
                select v.id, r.name, v.rating, v.comment, v.status,
                       (select count(*) from marketplace.food_review_complaints c where c.review_id = v.id and c.status = 'OPEN'), v.created_at
                from marketplace.food_reviews v join marketplace.food_restaurants r on r.id = v.restaurant_id
                where r.vertical = 'GROCERY' and (?::text is null or v.status = ?::text) order by v.created_at desc limit 200""",
                (rs, n) -> new ReviewRow(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getString(4), rs.getString(5), rs.getInt(6),
                        rs.getObject(7, OffsetDateTime.class)), status, status);
    }

    @Transactional
    @PostMapping("/reviews/{id}/moderation")
    ResponseEntity<List<ReviewRow>> moderateReview(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ReviewBody body) {
        UUID admin = admin(principal);
        int n = db.update("""
                update marketplace.food_reviews v set status = ?, moderation_note = ? from marketplace.food_restaurants r
                where v.id = ? and r.id = v.restaurant_id and r.vertical = 'GROCERY'""", "HIDE".equals(body.decision()) ? "HIDDEN" : "VISIBLE", body.reason().strip(), id);
        if (n == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Review not found"); }
        audit(admin, "REVIEW_" + body.decision(), id.toString(), body.reason().strip());
        return ok(reviewRows(null));
    }

    @GetMapping("/complaints")
    ResponseEntity<List<ComplaintRow>> complaints(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "OPEN") String status) {
        admin(principal);
        return ok(complaintRows(status));
    }

    private List<ComplaintRow> complaintRows(String status) {
        return db.query("""
                select c.id, c.review_id, r.name, v.comment, c.reason, c.status, c.created_at
                from marketplace.food_review_complaints c join marketplace.food_reviews v on v.id = c.review_id
                join marketplace.food_restaurants r on r.id = v.restaurant_id where r.vertical = 'GROCERY' and c.status = ? order by c.created_at desc limit 200""",
                (rs, n) -> new ComplaintRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                        rs.getObject(7, OffsetDateTime.class)), status);
    }

    @Transactional
    @PostMapping("/complaints/{id}/resolve")
    ResponseEntity<List<ComplaintRow>> resolve(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ResolveBody body) {
        UUID admin = admin(principal);
        int n = db.update("""
                update marketplace.food_review_complaints c set status = 'RESOLVED' from marketplace.food_reviews v, marketplace.food_restaurants r
                where c.id = ? and c.status = 'OPEN' and v.id = c.review_id and r.id = v.restaurant_id and r.vertical = 'GROCERY'""", id);
        if (n == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "COMPLAINT_NOT_FOUND", "Open complaint not found"); }
        audit(admin, "COMPLAINT_RESOLVED", id.toString(), body.resolution().strip());
        return ok(complaintRows("OPEN"));
    }

    /** Audit entries about Groceries stores, orders, products, promotions and reviews. */
    @GetMapping("/audit")
    ResponseEntity<List<AuditRow>> audit(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(db.query("""
                select a.id, a.actor_type, a.action, a.target, a.detail, a.occurred_at from marketplace.food_audit a
                where a.target in (select id::text from marketplace.food_restaurants where vertical = 'GROCERY')
                   or a.target in (select id::text from transactions.food_orders where vertical = 'GROCERY')
                   or a.target in (select p.id::text from marketplace.food_promotions p join marketplace.food_restaurants r on r.id = p.restaurant_id where r.vertical = 'GROCERY')
                   or a.target in (select v.id::text from marketplace.food_reviews v join marketplace.food_restaurants r on r.id = v.restaurant_id where r.vertical = 'GROCERY')
                order by a.id desc limit 200""",
                (rs, n) -> new AuditRow(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getObject(6, OffsetDateTime.class))));
    }
}
