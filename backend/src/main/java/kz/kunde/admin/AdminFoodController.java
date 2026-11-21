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
 * Food Control Center (ADR-018 entry scope + per-request FOOD_OPERATIONS grant). Every number comes from real orders; an
 * empty database yields zeros, never sample values. No customer name, phone or address is returned (orders carry only a
 * short customer reference). Every change is written to the append-only {@code marketplace.food_audit}.
 */
@RestController
@RequestMapping("/api/v1/admin/food")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.food.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminFoodController {
    public record Summary(long restaurants, long openRestaurants, long blockedRestaurants, long orders, long deliveredOrders,
            long cancelledOrders, long activeOrders, long revenueMinor, long averageCheckMinor, long deliveryOrders, long pickupOrders,
            long refundedMinor, long openComplaints, long hiddenReviews, long problemOrders, List<Day> perDay, List<StatusCount> statuses) {}

    public record Day(LocalDate day, long orders, long revenueMinor) {}

    public record StatusCount(String status, long count) {}

    public record OrderRow(String id, String restaurant, String vertical, String status, String fulfillmentType, String paymentMethod,
            String paymentStatus, long totalMinor, long refundedMinor, String customerRef, String cancelledBy, String cancelReason,
            OffsetDateTime placedAt) {}

    public record RestaurantRow(String id, String name, String vertical, String partner, boolean open, String moderationStatus,
            String moderationNote, Double ratingAvg, int ratingCount, long orders, boolean synthetic) {}

    public record ReviewRow(String id, String restaurant, int rating, String comment, String status, int complaints, OffsetDateTime createdAt) {}

    public record ComplaintRow(String id, String reviewId, String restaurant, String reviewComment, String reason, String status, OffsetDateTime createdAt) {}

    public record AuditRow(long id, String actorType, String action, String target, String detail, OffsetDateTime at) {}

    public record ModerationBody(@NotNull @Pattern(regexp = "BLOCK|UNBLOCK") String decision, @NotBlank @Size(min = 3, max = 200) String reason) {}

    public record PromoStatusBody(@NotNull @Pattern(regexp = "ACTIVE|PAUSED|DISABLED") String status, @Size(max = 200) String reason) {}

    public record ReviewBody(@NotNull @Pattern(regexp = "HIDE|SHOW") String decision, @NotBlank @Size(min = 3, max = 200) String reason) {}

    public record ResolveBody(@NotBlank @Size(min = 3, max = 200) String resolution) {}

    public record RefundBody(@NotBlank @Size(min = 3, max = 200) String reason) {}

    private final JdbcTemplate db;
    private final AdminGrants grants;
    private final FoodPromotionService promotions;

    public AdminFoodController(JdbcTemplate db, AdminGrants grants, FoodPromotionService promotions) {
        this.db = db;
        this.grants = grants;
        this.promotions = promotions;
    }

    private UUID admin(Jwt principal) {
        UUID id = PartnerAccessPolicy.userId(principal).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(id, Permission.FOOD_OPERATIONS);
        return id;
    }

    private static <T> ResponseEntity<T> ok(T body) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body); }

    private void audit(UUID admin, String action, String target, String detail) {
        db.update("insert into marketplace.food_audit (actor_user_id, actor_type, action, target, detail) values (?, 'ADMIN', ?, ?, ?)",
                admin, action, target, detail == null ? "" : detail);
    }

    @GetMapping("/summary")
    ResponseEntity<Summary> summary(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "7") int days) {
        admin(principal);
        int d = Math.max(1, Math.min(days, 60));
        long[] r = db.query("""
                select count(*), count(*) filter (where is_open and moderation_status = 'ACTIVE'), count(*) filter (where moderation_status = 'BLOCKED')
                from marketplace.food_restaurants where vertical = 'FOOD'""", (rs, n) -> new long[] {rs.getLong(1), rs.getLong(2), rs.getLong(3)}).get(0);
        long[] t = db.query("""
                select count(*), count(*) filter (where status = 'DELIVERED'), count(*) filter (where status = 'CANCELLED'),
                       count(*) filter (where status not in ('DELIVERED', 'CANCELLED')),
                       coalesce(sum(coalesce(final_total_minor, total_minor)) filter (where status = 'DELIVERED'), 0),
                       count(*) filter (where fulfillment_type = 'DELIVERY'), count(*) filter (where fulfillment_type = 'PICKUP'),
                       coalesce(sum(refunded_minor), 0),
                       count(*) filter (where status = 'CANCELLED' and cancelled_by = 'SYSTEM')
                from transactions.food_orders where vertical = 'FOOD' and placed_at > now() - make_interval(days => ?)""",
                (rs, n) -> {
                    long[] a = new long[9];
                    for (int i = 0; i < 9; i++) { a[i] = rs.getLong(i + 1); }
                    return a;
                }, d).get(0);
        long complaints = db.queryForObject("select count(*) from marketplace.food_review_complaints where status = 'OPEN'", Long.class);
        long hidden = db.queryForObject("select count(*) from marketplace.food_reviews where status = 'HIDDEN'", Long.class);
        List<Day> perDay = db.query("""
                select g::date, count(o.id), coalesce(sum(coalesce(o.final_total_minor, o.total_minor)) filter (where o.status = 'DELIVERED'), 0)
                from generate_series((now() at time zone 'Asia/Almaty')::date - (? - 1), (now() at time zone 'Asia/Almaty')::date, interval '1 day') g
                left join transactions.food_orders o on o.vertical = 'FOOD' and (o.placed_at at time zone 'Asia/Almaty')::date = g::date
                group by g order by g""", (rs, n) -> new Day(rs.getDate(1).toLocalDate(), rs.getLong(2), rs.getLong(3)), d);
        List<StatusCount> statuses = db.query("""
                select status, count(*) from transactions.food_orders where vertical = 'FOOD' and placed_at > now() - make_interval(days => ?)
                group by status order by count(*) desc""", (rs, n) -> new StatusCount(rs.getString(1), rs.getLong(2)), d);
        long avg = t[1] == 0 ? 0 : t[4] / t[1];
        return ok(new Summary(r[0], r[1], r[2], t[0], t[1], t[2], t[3], t[4], avg, t[5], t[6], t[7], complaints, hidden, t[8], perDay, statuses));
    }

    @GetMapping("/orders")
    ResponseEntity<List<OrderRow>> orders(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "50") int limit) {
        admin(principal);
        return ok(db.query("""
                select id, restaurant_name, vertical, status, fulfillment_type, payment_method, payment_status, total_minor, refunded_minor,
                       left(user_id::text, 8), cancelled_by, cancel_reason, placed_at
                from transactions.food_orders where (?::text is null or status = ?::text) order by placed_at desc limit ?""",
                (rs, n) -> new OrderRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                        rs.getString(7), rs.getLong(8), rs.getLong(9), rs.getString(10), rs.getString(11), rs.getString(12),
                        rs.getObject(13, OffsetDateTime.class)), status, status, Math.max(1, Math.min(limit, 200))));
    }

    /** Test refund (DEV ledger only, no money moves): a paid test-card order that was cancelled or delivered. Idempotent. */
    @Transactional
    @PostMapping("/orders/{orderId}/refund")
    ResponseEntity<OrderRow> refund(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId, @Valid @RequestBody RefundBody body) {
        UUID admin = admin(principal);
        var row = db.query("select status, payment_method, payment_status, total_minor from transactions.food_orders where id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getString(3), rs.getLong(4)}, orderId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        if (!"REFUNDED".equals(row[2])) {
            if (!"TEST_CARD".equals(row[1]) || !"TEST_PAID".equals(row[2])) {
                throw new ApiException(HttpStatus.CONFLICT, "REFUND_NOT_AVAILABLE", "Only a paid test-card order can be refunded");
            }
            if (!"DELIVERED".equals(row[0]) && !"CANCELLED".equals(row[0])) {
                throw new ApiException(HttpStatus.CONFLICT, "REFUND_NOT_AVAILABLE", "The order is still in progress");
            }
            db.update("update transactions.food_orders set payment_status = 'REFUNDED', refunded_minor = total_minor, refund_reason = ?, updated_at = now(), version = version + 1 where id = ?",
                    body.reason().strip(), orderId);
            audit(admin, "ORDER_REFUNDED", orderId.toString(), body.reason().strip());
        }
        return ok(orders(principal, null, 200).getBody().stream().filter(o -> o.id().equals(orderId.toString())).findFirst()
                .orElse(db.query("""
                        select id, restaurant_name, vertical, status, fulfillment_type, payment_method, payment_status, total_minor, refunded_minor,
                               left(user_id::text, 8), cancelled_by, cancel_reason, placed_at from transactions.food_orders where id = ?""",
                        (rs, n) -> new OrderRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                                rs.getString(7), rs.getLong(8), rs.getLong(9), rs.getString(10), rs.getString(11), rs.getString(12),
                                rs.getObject(13, OffsetDateTime.class)), orderId).get(0)));
    }

    @GetMapping("/restaurants")
    ResponseEntity<List<RestaurantRow>> restaurants(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(db.query("""
                select r.id, r.name, r.vertical, p.display_name, r.is_open, r.moderation_status, r.moderation_note,
                       (select round(avg(v.rating)::numeric, 1)::float8 from marketplace.food_reviews v where v.restaurant_id = r.id and v.status = 'VISIBLE'),
                       (select count(*) from marketplace.food_reviews v where v.restaurant_id = r.id and v.status = 'VISIBLE'),
                       (select count(*) from transactions.food_orders o where o.restaurant_id = r.id), r.is_synthetic
                from marketplace.food_restaurants r left join marketplace.partners p on p.id = r.partner_id
                order by r.vertical, r.name limit 300""",
                (rs, n) -> new RestaurantRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getBoolean(5), rs.getString(6),
                        rs.getString(7), rs.getObject(8, Double.class), rs.getInt(9), rs.getLong(10), rs.getBoolean(11))));
    }

    @Transactional
    @PostMapping("/restaurants/{id}/moderation")
    ResponseEntity<List<RestaurantRow>> moderate(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ModerationBody body) {
        UUID admin = admin(principal);
        String to = "BLOCK".equals(body.decision()) ? "BLOCKED" : "ACTIVE";
        String from = db.query("select moderation_status from marketplace.food_restaurants where id = ? for update", (rs, n) -> rs.getString(1), id)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant not found"));
        if (from.equals(to)) {
            throw new ApiException(HttpStatus.CONFLICT, "MODERATION_NO_CHANGE", "The restaurant is already " + to);
        }
        db.update("update marketplace.food_restaurants set moderation_status = ?, moderation_note = ? where id = ?", to, body.reason().strip(), id);
        audit(admin, "RESTAURANT_" + body.decision(), id.toString(), body.reason().strip());
        return ok(restaurants(principal).getBody());
    }

    @GetMapping("/promotions")
    ResponseEntity<List<PromotionView>> promotions(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status) {
        admin(principal);
        return ok(promotions.all(status));
    }

    @PostMapping("/promotions/{id}/status")
    ResponseEntity<PromotionView> promotionStatus(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody PromoStatusBody body) {
        return ok(promotions.adminSetStatus(admin(principal), id, body.status(), body.reason()));
    }

    @GetMapping("/reviews")
    ResponseEntity<List<ReviewRow>> reviews(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status) {
        admin(principal);
        return ok(db.query("""
                select v.id, r.name, v.rating, v.comment, v.status,
                       (select count(*) from marketplace.food_review_complaints c where c.review_id = v.id and c.status = 'OPEN'), v.created_at
                from marketplace.food_reviews v join marketplace.food_restaurants r on r.id = v.restaurant_id
                where (?::text is null or v.status = ?::text) order by v.created_at desc limit 200""",
                (rs, n) -> new ReviewRow(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getString(4), rs.getString(5), rs.getInt(6),
                        rs.getObject(7, OffsetDateTime.class)), status, status));
    }

    @Transactional
    @PostMapping("/reviews/{id}/moderation")
    ResponseEntity<List<ReviewRow>> moderateReview(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ReviewBody body) {
        UUID admin = admin(principal);
        int n = db.update("update marketplace.food_reviews set status = ?, moderation_note = ? where id = ?",
                "HIDE".equals(body.decision()) ? "HIDDEN" : "VISIBLE", body.reason().strip(), id);
        if (n == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Review not found"); }
        audit(admin, "REVIEW_" + body.decision(), id.toString(), body.reason().strip());
        return ok(reviews(principal, null).getBody());
    }

    @GetMapping("/complaints")
    ResponseEntity<List<ComplaintRow>> complaints(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "OPEN") String status) {
        admin(principal);
        return ok(db.query("""
                select c.id, c.review_id, r.name, v.comment, c.reason, c.status, c.created_at
                from marketplace.food_review_complaints c join marketplace.food_reviews v on v.id = c.review_id
                join marketplace.food_restaurants r on r.id = v.restaurant_id where c.status = ? order by c.created_at desc limit 200""",
                (rs, n) -> new ComplaintRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                        rs.getObject(7, OffsetDateTime.class)), status));
    }

    @Transactional
    @PostMapping("/complaints/{id}/resolve")
    ResponseEntity<List<ComplaintRow>> resolve(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ResolveBody body) {
        UUID admin = admin(principal);
        int n = db.update("update marketplace.food_review_complaints set status = 'RESOLVED' where id = ? and status = 'OPEN'", id);
        if (n == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "COMPLAINT_NOT_FOUND", "Open complaint not found"); }
        audit(admin, "COMPLAINT_RESOLVED", id.toString(), body.resolution().strip());
        return ok(complaints(principal, "OPEN").getBody());
    }

    @GetMapping("/audit")
    ResponseEntity<List<AuditRow>> audit(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(db.query("select id, actor_type, action, target, detail, occurred_at from marketplace.food_audit order by id desc limit 200",
                (rs, n) -> new AuditRow(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getObject(6, OffsetDateTime.class))));
    }
}
