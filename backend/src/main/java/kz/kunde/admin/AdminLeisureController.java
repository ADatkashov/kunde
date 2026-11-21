package kz.kunde.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.leisure.LeisureOrderService;
import kz.kunde.leisure.LeisurePayments;
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
import org.springframework.web.bind.annotation.*;

/**
 * Leisure Control Center (ADR-018 scope + per-request LEISURE_OPERATIONS grant): analytics, moderation of venues and events, categories,
 * bookings and tickets, refunds, complaints, reviews and the audit journal. Every change is written to the append-only Leisure audit.
 * The runtime on/off switch is the shared feature switch (LEISURE) of {@link AdminFeatureController}.
 */
@RestController
@RequestMapping("/api/v1/admin/leisure")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminLeisureController {
    public record Summary(long events, long venues, long partners, long orders, long tickets, long bookedMinor, long refundedMinor, long admittedGuests,
            long pendingVenues, long pendingEvents, long openComplaints, List<Day> perDay) {}

    public record Day(LocalDate day, long orders, long bookedMinor) {}

    public record VenueRow(String id, String name, String partner, String district, String status, String moderationNote, int events, OffsetDateTime createdAt, boolean synthetic) {}

    public record EventRow(String id, String title, String venue, String category, String bookingType, String status, String moderationNote, boolean synthetic) {}

    public record OrderRow(String id, String status, String event, String venue, OffsetDateTime startsAt, int guests, long totalMinor, String paymentMethod, String paymentStatus,
            String paymentId, OffsetDateTime createdAt) {}

    public record TicketRow(String id, String orderId, String status, String event, OffsetDateTime startsAt, String seat, OffsetDateTime usedAt) {}

    public record CategoryRow(String code, String nameRu, String bookingType, boolean enabled) {}

    public record ComplaintRow(String id, String venue, String orderId, String body, String status, String resolution, OffsetDateTime createdAt) {}

    public record AuditRow(long id, String actorType, String action, String target, String detail, OffsetDateTime at) {}

    public record Decision(@NotNull @Pattern(regexp = "APPROVE|REJECT|BLOCK|UNBLOCK") String decision, @Size(max = 200) String reason) {}

    public record EnabledBody(@NotNull Boolean enabled) {}

    public record ReasonBody(@NotBlank @Size(max = 200) String reason) {}

    public record RefundBody(@NotNull @Positive Long amountMinor, @NotBlank @Size(max = 200) String reason) {}

    public record ResolveBody(@NotBlank @Size(max = 300) String resolution) {}

    private final JdbcTemplate db;
    private final AdminGrants grants;
    private final LeisurePayments payments;
    private final LeisureOrderService orders;

    public AdminLeisureController(JdbcTemplate db, AdminGrants grants, LeisurePayments payments, LeisureOrderService orders) {
        this.db = db;
        this.grants = grants;
        this.payments = payments;
        this.orders = orders;
    }

    private UUID admin(Jwt principal) {
        UUID id = PartnerAccessPolicy.userId(principal).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(id, Permission.LEISURE_OPERATIONS);
        return id;
    }

    private static <T> ResponseEntity<T> ok(T body) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body); }

    private void audit(UUID admin, String action, String target, String detail) {
        db.update("insert into marketplace.leisure_audit (actor_user_id, actor_type, action, target, detail) values (?, 'ADMIN', ?, ?, ?)", admin, action, target, detail);
    }

    private static final String PRODUCT_OK = " (?::text is null or c.product = ?::text) "; // padded: text blocks strip trailing blanks before the concatenation
    private static final String ORDERS_OF = " transactions.leisure_orders o join marketplace.leisure_events e on e.id = o.event_id join marketplace.leisure_categories c on c.code = e.category_code ";

    /** {@code product} is EVENTS or LEISURE (the two products share this engine); absent = both. Anything else is a client error. */
    private static String product(String product) {
        if (product == null || product.isBlank()) { return null; }
        if (!"EVENTS".equals(product) && !"LEISURE".equals(product)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PRODUCT_INVALID", "product must be EVENTS or LEISURE");
        }
        return product;
    }

    @GetMapping("/summary")
    ResponseEntity<Summary> summary(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "7") int days, @RequestParam(required = false) String product) {
        admin(principal);
        String pr = product(product);
        int d = Math.max(1, Math.min(days, 60));
        long[] t = db.query("""
                select (select count(*) from marketplace.leisure_events e join marketplace.leisure_categories c on c.code = e.category_code where e.status = 'PUBLISHED' and """ + PRODUCT_OK + """
                       ),
                       (select count(distinct v.id) from marketplace.leisure_venues v join marketplace.leisure_events e on e.venue_id = v.id join marketplace.leisure_categories c on c.code = e.category_code
                          where v.status = 'APPROVED' and """ + PRODUCT_OK + """
                       ),
                       (select count(distinct v.partner_id) from marketplace.leisure_venues v join marketplace.leisure_events e on e.venue_id = v.id join marketplace.leisure_categories c on c.code = e.category_code
                          where v.status = 'APPROVED' and """ + PRODUCT_OK + """
                       ),
                       (select count(*) from """ + ORDERS_OF + """
                          where o.status = 'CONFIRMED' and """ + PRODUCT_OK + """
                       ),
                       (select count(*) from transactions.leisure_tickets t join marketplace.leisure_sessions s on s.id = t.session_id join marketplace.leisure_events e on e.id = s.event_id
                          join marketplace.leisure_categories c on c.code = e.category_code where t.status in ('VALID', 'USED') and """ + PRODUCT_OK + """
                       ),
                       (select coalesce(sum(o.total_minor), 0) from """ + ORDERS_OF + """
                          where o.status = 'CONFIRMED' and """ + PRODUCT_OK + """
                       ),
                       (select coalesce(sum(p.refunded_minor), 0) from transactions.leisure_payments p join transactions.leisure_orders o on o.id = p.order_id
                          join marketplace.leisure_events e on e.id = o.event_id join marketplace.leisure_categories c on c.code = e.category_code where """ + PRODUCT_OK + """
                       ),
                       (select coalesce(sum(t.admits), 0) from transactions.leisure_tickets t join marketplace.leisure_sessions s on s.id = t.session_id join marketplace.leisure_events e on e.id = s.event_id
                          join marketplace.leisure_categories c on c.code = e.category_code where t.status = 'USED' and """ + PRODUCT_OK + """
                       ),
                       (select count(*) from marketplace.leisure_venues where status = 'PENDING'),
                       (select count(*) from marketplace.leisure_events e join marketplace.leisure_categories c on c.code = e.category_code where e.status = 'PENDING' and """ + PRODUCT_OK + """
                       ),
                       (select count(*) from transactions.leisure_complaints where status = 'OPEN')""", (rs, n) -> {
            long[] a = new long[11];
            for (int i = 0; i < 11; i++) { a[i] = rs.getLong(i + 1); }
            return a;
        }, repeat(pr, 9)).get(0);
        List<Day> perDay = db.query("""
                select g::date, count(x.id), coalesce(sum(x.total_minor), 0) from generate_series((now() at time zone 'Asia/Almaty')::date - (? - 1), (now() at time zone 'Asia/Almaty')::date, interval '1 day') g
                left join (select o.id, o.total_minor, o.created_at from """ + ORDERS_OF + """
                           where o.status = 'CONFIRMED' and """ + PRODUCT_OK + """
                          ) x on (x.created_at at time zone 'Asia/Almaty')::date = g::date group by g order by g""",
                (rs, n) -> new Day(rs.getDate(1).toLocalDate(), rs.getLong(2), rs.getLong(3)), d, pr, pr);
        return ok(new Summary(t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], perDay));
    }

    /** The product parameter, twice per condition (the SQL repeats it as {@code ?::text is null or ... = ?::text}). */
    private static Object[] repeat(String pr, int conditions) {
        Object[] out = new Object[conditions * 2];
        for (int i = 0; i < out.length; i++) { out[i] = pr; }
        return out;
    }

    @GetMapping("/venues")
    ResponseEntity<List<VenueRow>> venues(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status) {
        admin(principal);
        return ok(db.query("""
                select v.id, v.name, p.display_name, v.district, v.status, v.moderation_note, (select count(*) from marketplace.leisure_events e where e.venue_id = v.id), v.created_at, v.is_synthetic
                from marketplace.leisure_venues v join marketplace.partners p on p.id = v.partner_id where (?::text is null or v.status = ?::text) order by v.created_at desc limit 200""",
                (rs, n) -> new VenueRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getInt(7),
                        kz.kunde.leisure.LeisureTime.local(rs, 8), rs.getBoolean(9)), status, status));
    }

    @Transactional
    @PostMapping("/venues/{id}/decision")
    ResponseEntity<VenueRow> venueDecision(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody Decision body) {
        UUID admin = admin(principal);
        String from = db.query("select status from marketplace.leisure_venues where id = ? for update", (rs, n) -> rs.getString(1), id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found"));
        String to = transition(from, body, "PENDING", "APPROVED", "REJECTED", "BLOCKED", "APPROVED");
        db.update("update marketplace.leisure_venues set status = ?, moderation_note = ?, version = version + 1, updated_at = now() where id = ?", to, body.reason(), id);
        audit(admin, "VENUE_" + body.decision(), id.toString(), body.reason());
        return ok(venues(principal, null).getBody().stream().filter(v -> v.id().equals(id.toString())).findFirst().orElseThrow());
    }

    @GetMapping("/events")
    ResponseEntity<List<EventRow>> events(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status, @RequestParam(required = false) String product) {
        admin(principal);
        String pr = product(product);
        return ok(db.query("""
                select e.id, e.title, v.name, e.category_code, e.booking_type, e.status, e.moderation_note, e.is_synthetic from marketplace.leisure_events e
                join marketplace.leisure_venues v on v.id = e.venue_id join marketplace.leisure_categories c on c.code = e.category_code
                where (?::text is null or e.status = ?::text) and """ + PRODUCT_OK + """
                 order by e.created_at desc limit 200""",
                (rs, n) -> new EventRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7), rs.getBoolean(8)), status, status, pr, pr));
    }

    @Transactional
    @PostMapping("/events/{id}/decision")
    ResponseEntity<EventRow> eventDecision(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody Decision body) {
        UUID admin = admin(principal);
        String from = db.query("select status from marketplace.leisure_events where id = ? for update", (rs, n) -> rs.getString(1), id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "EVENT_NOT_FOUND", "Event not found"));
        String to = transition(from, body, "PENDING", "PUBLISHED", "REJECTED", "BLOCKED", "ARCHIVED");
        db.update("update marketplace.leisure_events set status = ?, moderation_note = ?, version = version + 1, updated_at = now() where id = ?", to, body.reason(), id);
        audit(admin, "EVENT_" + body.decision(), id.toString(), body.reason());
        return ok(events(principal, null, null).getBody().stream().filter(v -> v.id().equals(id.toString())).findFirst().orElseThrow());
    }

    /** APPROVE/REJECT apply to a pending item, BLOCK to anything not blocked, UNBLOCK only to a blocked one (back to the neutral state). */
    private static String transition(String from, Decision d, String pending, String approved, String rejected, String blocked, String unblockedTo) {
        if ((d.decision().equals("REJECT") || d.decision().equals("BLOCK")) && (d.reason() == null || d.reason().isBlank())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason is required to reject or block");
        }
        return switch (d.decision()) {
            case "APPROVE" -> { require(pending.equals(from), "Only a pending item can be approved"); yield approved; }
            case "REJECT" -> { require(pending.equals(from), "Only a pending item can be rejected"); yield rejected; }
            case "BLOCK" -> { require(!blocked.equals(from), "Already blocked"); yield blocked; }
            default -> { require(blocked.equals(from), "Only a blocked item can be unblocked"); yield unblockedTo; }
        };
    }

    private static void require(boolean ok, String message) {
        if (!ok) { throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", message); }
    }

    @GetMapping("/categories")
    ResponseEntity<List<CategoryRow>> categories(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String product) {
        admin(principal);
        String pr = product(product);
        return ok(db.query("select code, name_ru, default_booking_type, enabled from marketplace.leisure_categories c where " + PRODUCT_OK + " order by sort_order",
                (rs, n) -> new CategoryRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getBoolean(4)), pr, pr));
    }

    @Transactional
    @PatchMapping("/categories/{code}")
    ResponseEntity<CategoryRow> category(@AuthenticationPrincipal Jwt principal, @PathVariable String code, @Valid @RequestBody EnabledBody body) {
        UUID admin = admin(principal);
        if (db.update("update marketplace.leisure_categories set enabled = ? where code = ?", body.enabled(), code) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "CATEGORY_NOT_FOUND", "Category not found");
        }
        audit(admin, "CATEGORY_" + (body.enabled() ? "ENABLED" : "DISABLED"), code, null);
        return ok(db.query("select code, name_ru, default_booking_type, enabled from marketplace.leisure_categories where code = ?",
                (rs, n) -> new CategoryRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getBoolean(4)), code).get(0));
    }

    @GetMapping("/orders")
    ResponseEntity<List<OrderRow>> orderList(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status, @RequestParam(defaultValue = "50") int limit,
            @RequestParam(required = false) String product) {
        admin(principal);
        String pr = product(product);
        return ok(db.query("""
                select o.id, o.status, e.title, v.name, s.starts_at, o.guests, o.total_minor, o.payment_method, p.status, p.id, o.created_at from transactions.leisure_orders o
                join marketplace.leisure_events e on e.id = o.event_id join marketplace.leisure_categories c on c.code = e.category_code join marketplace.leisure_venues v on v.id = o.venue_id join marketplace.leisure_sessions s on s.id = o.session_id
                left join transactions.leisure_payments p on p.order_id = o.id where (?::text is null or o.status = ?::text) and """ + PRODUCT_OK + """
                 order by o.created_at desc limit ?""",
                (rs, n) -> new OrderRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), kz.kunde.leisure.LeisureTime.local(rs, 5), rs.getInt(6), rs.getLong(7),
                        rs.getString(8), rs.getString(9), rs.getString(10), kz.kunde.leisure.LeisureTime.local(rs, 11)), status, status, pr, pr, Math.max(1, Math.min(limit, 200))));
    }

    @PostMapping("/orders/{id}/cancel")
    ResponseEntity<Void> cancelOrder(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ReasonBody body) {
        orders.adminCancel(admin(principal), id, body.reason());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @GetMapping("/tickets")
    ResponseEntity<List<TicketRow>> tickets(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status, @RequestParam(required = false) UUID orderId) {
        admin(principal);
        return ok(db.query("""
                select t.id, t.order_id, t.status, e.title, s.starts_at, st.row_label || st.seat_number, t.used_at from transactions.leisure_tickets t
                join marketplace.leisure_sessions s on s.id = t.session_id join marketplace.leisure_events e on e.id = s.event_id left join marketplace.leisure_seats st on st.id = t.seat_id
                where (?::text is null or t.status = ?::text) and (?::uuid is null or t.order_id = ?::uuid) order by t.created_at desc limit 100""",
                (rs, n) -> new TicketRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), kz.kunde.leisure.LeisureTime.local(rs, 5), rs.getString(6),
                        kz.kunde.leisure.LeisureTime.local(rs, 7)), status, status, orderId, orderId));
    }

    @GetMapping("/payments")
    ResponseEntity<List<LeisurePayments.Entry>> paymentList(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "false") boolean refundableOnly) {
        admin(principal);
        return ok(payments.latest(refundableOnly));
    }

    @PostMapping("/payments/{id}/refund")
    ResponseEntity<LeisurePayments.PaymentView> refund(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody RefundBody body) {
        return ok(payments.refund(admin(principal), id, body.amountMinor(), body.reason()));
    }

    @GetMapping("/complaints")
    ResponseEntity<List<ComplaintRow>> complaints(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "false") boolean includeResolved) {
        admin(principal);
        return ok(db.query("""
                select c.id, v.name, c.order_id, c.body, c.status, c.resolution, c.created_at from transactions.leisure_complaints c join marketplace.leisure_venues v on v.id = c.venue_id
                where (? or c.status = 'OPEN') order by c.created_at desc limit 100""", (rs, n) -> new ComplaintRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getString(5), rs.getString(6), kz.kunde.leisure.LeisureTime.local(rs, 7)), includeResolved));
    }

    @Transactional
    @PostMapping("/complaints/{id}/resolve")
    ResponseEntity<Void> resolve(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ResolveBody body) {
        UUID admin = admin(principal);
        if (db.update("update transactions.leisure_complaints set status = 'RESOLVED', resolution = ?, resolved_by = ?, resolved_at = now() where id = ? and status = 'OPEN'", body.resolution(), admin, id) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "COMPLAINT_NOT_FOUND", "Open complaint not found");
        }
        audit(admin, "COMPLAINT_RESOLVED", id.toString(), body.resolution());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @Transactional
    @PostMapping("/reviews/{id}/hide")
    ResponseEntity<Void> hideReview(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ReasonBody body) {
        UUID admin = admin(principal);
        if (db.update("update transactions.leisure_reviews set status = 'HIDDEN' where id = ? and status = 'PUBLISHED'", id) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Published review not found");
        }
        audit(admin, "REVIEW_HIDDEN", id.toString(), body.reason());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @GetMapping("/audit")
    ResponseEntity<List<AuditRow>> auditLog(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "50") int limit, @RequestParam(defaultValue = "0") int offset) {
        admin(principal);
        return ok(db.query("select id, actor_type, action, target, detail, occurred_at from marketplace.leisure_audit order by id desc limit ? offset ?",
                (rs, n) -> new AuditRow(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), kz.kunde.leisure.LeisureTime.local(rs, 6)),
                Math.max(1, Math.min(limit, 200)), Math.max(0, offset)));
    }
}
