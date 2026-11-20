package kz.kunde.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
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
 * Auto administration (ADR-018 scope + per-request AUTO_OPERATIONS grant): enable/disable a kind of service, block a
 * venue, monitor bookings without customer personal data. Every change is written to the append-only admin audit.
 */
@RestController
@RequestMapping("/api/v1/admin/auto")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminAutoController {
    public record CategoryView(String code, String nameRu, boolean enabled, boolean mobile) {}

    public record BookingRow(String id, String venueName, String serviceName, String status, OffsetDateTime startsAt, long priceMinor, String priceKind) {}

    public record EnabledBody(@NotNull Boolean enabled) {}

    public record VenueView(String id, String name, boolean open) {}

    private final JdbcTemplate db;
    private final AdminGrants grants;
    private final kz.kunde.auto.AutoJobService jobs;
    private final kz.kunde.auto.AutoFeedbackService feedback;
    private final kz.kunde.auto.AutoPayments payments;

    public AdminAutoController(JdbcTemplate db, AdminGrants grants, kz.kunde.auto.AutoJobService jobs, kz.kunde.auto.AutoFeedbackService feedback,
            kz.kunde.auto.AutoPayments payments) {
        this.payments = payments;
        this.db = db;
        this.grants = grants;
        this.jobs = jobs;
        this.feedback = feedback;
    }

    private UUID admin(Jwt principal) {
        UUID id = PartnerAccessPolicy.userId(principal).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(id, Permission.AUTO_OPERATIONS);
        return id;
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    @GetMapping("/categories")
    ResponseEntity<List<CategoryView>> categories(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(db.query("select code, name_ru, enabled, mobile from marketplace.auto_service_categories order by sort_order",
                (rs, n) -> new CategoryView(rs.getString(1), rs.getString(2), rs.getBoolean(3), rs.getBoolean(4))));
    }

    @Transactional
    @PatchMapping("/categories/{code}")
    ResponseEntity<CategoryView> category(@AuthenticationPrincipal Jwt principal, @PathVariable String code, @Valid @RequestBody EnabledBody body) {
        UUID admin = admin(principal);
        if (db.update("update marketplace.auto_service_categories set enabled = ? where code = ?", body.enabled(), code) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "CATEGORY_NOT_FOUND", "Category not found");
        }
        audit(admin, "CATEGORY_" + (body.enabled() ? "ENABLED" : "DISABLED"), code);
        return ok(db.query("select code, name_ru, enabled, mobile from marketplace.auto_service_categories where code = ?",
                (rs, n) -> new CategoryView(rs.getString(1), rs.getString(2), rs.getBoolean(3), rs.getBoolean(4)), code).get(0));
    }

    /** Blocking hides a venue from the catalog and slots; existing bookings stay and can be cancelled or completed. */
    @Transactional
    @PatchMapping("/venues/{venueId}")
    ResponseEntity<VenueView> venue(@AuthenticationPrincipal Jwt principal, @PathVariable UUID venueId, @Valid @RequestBody OpenBody body) {
        UUID admin = admin(principal);
        if (db.update("update marketplace.booking_venues set is_open = ? where id = ? and category = 'AUTO'", body.open(), venueId) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found");
        }
        audit(admin, body.open() ? "VENUE_UNBLOCKED" : "VENUE_BLOCKED", venueId.toString());
        return ok(db.query("select id, name, is_open from marketplace.booking_venues where id = ?",
                (rs, n) -> new VenueView(rs.getString(1), rs.getString(2), rs.getBoolean(3)), venueId).get(0));
    }

    public record OpenBody(@NotNull Boolean open) {}

    public record SpecialistDecision(@NotNull Boolean approve, List<String> categories, @jakarta.validation.constraints.NotBlank
            @jakarta.validation.constraints.Size(max = 200) String reason) {}

    @GetMapping("/specialists")
    ResponseEntity<List<kz.kunde.auto.AutoJobService.Reviewed>> specialists(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "false") boolean includeReviewed) {
        admin(principal);
        return ok(jobs.specialistsForReview(includeReviewed));
    }

    @PostMapping("/specialists/{id}/decision")
    ResponseEntity<kz.kunde.auto.AutoJobService.Reviewed> decide(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
            @Valid @RequestBody SpecialistDecision body) {
        UUID admin = admin(principal);
        return ok(jobs.review(admin, id, body.approve(), body.categories(), body.reason()));
    }

    public record ResolveBody(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 300) String resolution) {}

    @GetMapping("/complaints")
    ResponseEntity<List<kz.kunde.auto.AutoFeedbackService.Complaint>> complaints(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "false") boolean includeResolved) {
        admin(principal);
        return ok(feedback.queue(includeResolved));
    }

    @PostMapping("/complaints/{id}/resolve")
    ResponseEntity<kz.kunde.auto.AutoFeedbackService.Complaint> resolve(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ResolveBody body) {
        UUID admin = admin(principal);
        return ok(feedback.resolve(admin, id, body.resolution()));
    }

    @GetMapping("/venues")
    ResponseEntity<List<VenueView>> venueList(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ok(db.query("select id, name, is_open from marketplace.booking_venues where category = 'AUTO' order by name",
                (rs, n) -> new VenueView(rs.getString(1), rs.getString(2), rs.getBoolean(3))));
    }

    public record RefundBody(@NotNull @jakarta.validation.constraints.Positive Long amountMinor, @jakarta.validation.constraints.NotBlank
            @jakarta.validation.constraints.Size(max = 200) String reason) {}

    @GetMapping("/payments")
    ResponseEntity<List<kz.kunde.auto.AutoPayments.Entry>> paymentList(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "false") boolean refundableOnly) {
        admin(principal);
        return ok(payments.latest(refundableOnly));
    }

    @PostMapping("/payments/{id}/refund")
    ResponseEntity<kz.kunde.auto.AutoPayments.PaymentView> refund(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody RefundBody body) {
        UUID admin = admin(principal);
        return ok(payments.refund(admin, id, body.amountMinor(), body.reason()));
    }

    public record JobRow(String id, String category, String status, String specialist, long priceMinor, OffsetDateTime createdAt) {}

    @GetMapping("/jobs")
    ResponseEntity<List<JobRow>> jobRows(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status) {
        admin(principal);
        return ok(db.query("""
                select j.id, j.category, j.status, s.display_name, j.price_minor, j.created_at from transactions.auto_jobs j
                left join transactions.auto_specialists s on s.user_id = j.specialist_id where (?::text is null or j.status = ?::text)
                order by j.created_at desc limit 100
                """, (rs, n) -> new JobRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getLong(5),
                rs.getObject(6, OffsetDateTime.class)), status, status));
    }

    @GetMapping("/bookings")
    ResponseEntity<List<BookingRow>> bookings(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "50") int limit) {
        admin(principal);
        int cap = Math.max(1, Math.min(limit, 200));
        return ok(db.query("""
                select id, venue_name, service_name, status, starts_at, price_minor, price_kind from transactions.bookings
                where category = 'AUTO' and (?::text is null or status = ?::text) order by starts_at desc limit ?
                """, (rs, n) -> new BookingRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getObject(5, OffsetDateTime.class), rs.getLong(6), rs.getString(7)), status, status, cap));
    }

    private void audit(UUID admin, String action, String target) {
        db.update("insert into marketplace.auto_admin_events (admin_user_id, action, target) values (?, ?, ?)", admin, action, target);
    }
}
