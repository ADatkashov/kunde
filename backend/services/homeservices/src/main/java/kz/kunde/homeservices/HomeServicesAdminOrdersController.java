package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingService;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.authz.AdminGrants;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Operations over Home Services orders for platform staff (H8): a register with filters, an order card with its full history,
 * cancellation and re-assignment of the master. Needs the {@code HOME_SERVICES_OPERATIONS} grant. The lists carry no customer
 * contact data; the card shows the service address because staff need it to resolve a problem. Every action needs a reason,
 * checks the order version (stale screens change nothing), is written to the booking history as {@code ADMIN} and to the
 * append-only {@code home_service_admin_events}. Work that has already started ({@code IN_PROGRESS}) is a dispute, not an
 * operation, and is refused here.
 */
@RestController
@Validated
@RequestMapping("/api/v1/admin/home-services/orders")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled", "app.booking.enabled"}, havingValue = "true")
public class HomeServicesAdminOrdersController {
    private static final String CATEGORY = "CLEANING";
    /** Active masters of a venue that perform a service: the only ones an order of that service can be handed to. */
    private static final String PERFORMERS = """
            select m.id, m.name, m.online from marketplace.booking_masters m
            join marketplace.booking_master_services ms on ms.master_id = m.id and ms.service_id = ?
            where m.venue_id = ? and m.active""";
    private static final String STATUSES = "PENDING|CONFIRMED|IN_PROGRESS|COMPLETED|CANCELLED|NO_SHOW";

    public record Row(String id, String bookingNumber, String serviceName, String venueName, String masterName, String status,
            String stage, OffsetDateTime startsAt, long priceMinor, OffsetDateTime createdAt, String cancelledBy) {}

    public record Page(List<Row> items, long total, int limit, int offset) {}

    public record HistoryEntry(String status, String actorType, String reason, OffsetDateTime occurredAt) {}

    public record AdminAction(String action, String reason, OffsetDateTime occurredAt) {}

    public record Visit(String stage, Integer etaMinutes, OffsetDateTime enRouteAt, OffsetDateTime arrivedAt) {}

    public record Detail(Row order, String addressText, Integer areaSqm, String comment, String cancelReason, long version,
            boolean actionable, Visit visit, List<HistoryEntry> history, List<AdminAction> adminActions) {}

    public record MasterOption(String id, String name, boolean online) {}

    public record CancelRequest(@NotNull @Min(0) Long expectedVersion, @NotBlank @Size(max = 200) String reason) {}

    public record ReassignRequest(@NotNull UUID masterId, @NotNull @Min(0) Long expectedVersion, @NotBlank @Size(max = 200) String reason) {}

    private final JdbcTemplate db;
    private final AdminGrants grants;
    private final BookingService bookings;

    public HomeServicesAdminOrdersController(JdbcTemplate db, AdminGrants grants, BookingService bookings) {
        this.db = db;
        this.grants = grants;
        this.bookings = bookings;
    }

    @GetMapping
    @Transactional(readOnly = true)
    ResponseEntity<Page> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) @Pattern(regexp = STATUSES) String status,
            @RequestParam(required = false) @Size(max = 24) @Pattern(regexp = "[A-Za-z0-9-]*") String q,
            @RequestParam(required = false) UUID venueId,
            @RequestParam(required = false) java.time.LocalDate from,
            @RequestParam(required = false) java.time.LocalDate to,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        authorize(principal);
        String number = q == null || q.isBlank() ? null : q.trim().toUpperCase();
        String where = """
                where b.category = ? and (?::text is null or b.status = ?::text) and (?::text is null or b.booking_number like ?::text || '%')
                  and (?::uuid is null or b.venue_id = ?::uuid)
                  and (?::date is null or b.starts_at >= (?::date)::timestamp at time zone 'Asia/Almaty')
                  and (?::date is null or b.starts_at < ((?::date) + 1)::timestamp at time zone 'Asia/Almaty')
                """;
        Object[] filter = {CATEGORY, status, status, number, number, venueId, venueId, from, from, to, to};
        long total = db.queryForObject("select count(*) from transactions.bookings b " + where, Long.class, filter);
        List<Object> args = new ArrayList<>(java.util.Arrays.asList(filter));
        args.add(limit);
        args.add(offset);
        List<Row> items = db.query("""
                select b.id, b.booking_number, b.service_name, b.venue_name, b.master_name, b.status, v.stage, b.starts_at,
                       b.price_minor, b.created_at, b.cancelled_by
                from transactions.bookings b left join marketplace.home_service_visits v on v.booking_id = b.id
                """ + where + " order by b.starts_at desc, b.id limit ? offset ?", (rs, n) -> row(rs), args.toArray());
        return ok(new Page(items, total, limit, offset));
    }

    @GetMapping("/{id}")
    @Transactional(readOnly = true)
    ResponseEntity<Detail> detail(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        authorize(principal);
        return ok(detailOf(id));
    }

    /** Active masters of the order's venue the order could be handed to. */
    @GetMapping("/{id}/masters")
    @Transactional(readOnly = true)
    ResponseEntity<List<MasterOption>> masters(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        authorize(principal);
        UUID[] order = db.query("select venue_id, service_id from transactions.bookings where id = ? and category = ?",
                (rs, n) -> new UUID[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class)}, id, CATEGORY).stream().findFirst()
                .orElseThrow(HomeServicesAdminOrdersController::notFound);
        return ok(db.query(PERFORMERS + " order by m.name, m.id",
                (rs, n) -> new MasterOption(rs.getString(1), rs.getString(2), rs.getBoolean(3)), order[1], order[0]));
    }

    @PostMapping("/{id}/cancel")
    @Transactional
    ResponseEntity<Detail> cancel(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody CancelRequest request) {
        UUID admin = authorize(principal);
        Locked order = lock(id, request.expectedVersion());
        db.update("""
                update transactions.bookings set status = 'CANCELLED', cancelled_at = now(), cancelled_by = 'ADMIN', cancel_reason = ?,
                    updated_at = now(), version = version + 1 where id = ?
                """, request.reason().trim(), id);
        bookings.event(id, "CANCELLED", "ADMIN", admin, request.reason().trim());
        audit(id, admin, "CANCEL", request.reason().trim(), order.master(), null);
        return ok(detailOf(id));
    }

    @PostMapping("/{id}/reassign")
    @Transactional
    ResponseEntity<Detail> reassign(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id, @Valid @RequestBody ReassignRequest request) {
        UUID admin = authorize(principal);
        Locked order = lock(id, request.expectedVersion());
        if (request.masterId().equals(order.master())) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_UNCHANGED", "The order already belongs to this master");
        }
        String name = db.query(PERFORMERS + " and m.id = ?", (rs, n) -> rs.getString(2), order.service(), order.venue(), request.masterId())
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "MASTER_INVALID",
                        "Choose an active master of the same venue who performs this service"));
        boolean taken = Boolean.TRUE.equals(db.queryForObject("""
                select exists (select 1 from transactions.bookings o join transactions.bookings b on b.master_id = ? and b.id <> o.id
                    and b.status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS')
                    and tstzrange(b.starts_at, b.ends_at) && tstzrange(o.starts_at, o.ends_at) where o.id = ?)
                """, Boolean.class, request.masterId(), id));
        if (taken) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_BUSY", "The master is busy at this time");
        }
        try {
            // Backstop for a race: the Booking Engine's exclusion constraint refuses a second confirmed visit at the same time.
            db.update("update transactions.bookings set master_id = ?, master_name = ?, updated_at = now(), version = version + 1 where id = ?",
                    request.masterId(), name, id);
        } catch (DataIntegrityViolationException busy) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_BUSY", "The master is busy at this time");
        }
        // The previous master's "on the way" report does not carry over to the new one.
        db.update("delete from marketplace.home_service_visits where booking_id = ?", id);
        bookings.event(id, order.status(), "ADMIN", admin, "REASSIGNED: " + request.reason().trim());
        audit(id, admin, "REASSIGN", request.reason().trim(), order.master(), request.masterId());
        return ok(detailOf(id));
    }

    // ---- internals

    private record Locked(String status, UUID venue, UUID master, UUID service) {}

    /** The order, locked; only an upcoming order that has not started can be operated on, and only at the version the screen saw. */
    private Locked lock(UUID id, long expectedVersion) {
        var row = db.query("select status, venue_id, master_id, service_id, version from transactions.bookings where id = ? and category = ? for update",
                (rs, n) -> new Object[] {new Locked(rs.getString(1), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                        rs.getObject(4, UUID.class)), rs.getLong(5)},
                id, CATEGORY).stream().findFirst().orElseThrow(HomeServicesAdminOrdersController::notFound);
        if ((long) row[1] != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The order has changed; reload it");
        }
        Locked order = (Locked) row[0];
        if (!"PENDING".equals(order.status()) && !"CONFIRMED".equals(order.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_NOT_OPERABLE",
                    "Only a pending or confirmed order can be cancelled or reassigned");
        }
        return order;
    }

    private void audit(UUID booking, UUID admin, String action, String reason, UUID from, UUID to) {
        db.update("""
                insert into marketplace.home_service_admin_events (booking_id, admin_user_id, action, reason, from_master_id, to_master_id)
                values (?, ?, ?, ?, ?, ?)
                """, booking, admin, action, reason, from, to);
    }

    private Detail detailOf(UUID id) {
        Row order = db.query("""
                select b.id, b.booking_number, b.service_name, b.venue_name, b.master_name, b.status, v.stage, b.starts_at,
                       b.price_minor, b.created_at, b.cancelled_by
                from transactions.bookings b left join marketplace.home_service_visits v on v.booking_id = b.id
                where b.id = ? and b.category = ?
                """, (rs, n) -> row(rs), id, CATEGORY).stream().findFirst().orElseThrow(HomeServicesAdminOrdersController::notFound);
        var extra = db.queryForMap("select address_text, area_sqm, comment, cancel_reason, version from transactions.bookings where id = ?", id);
        Visit visit = db.query("select stage, eta_minutes, en_route_at, arrived_at from marketplace.home_service_visits where booking_id = ?",
                (rs, n) -> new Visit(rs.getString(1), rs.getObject(2, Integer.class), rs.getObject(3, OffsetDateTime.class),
                        rs.getObject(4, OffsetDateTime.class)), id).stream().findFirst().orElse(null);
        List<HistoryEntry> history = db.query("select status, actor_type, reason, occurred_at from transactions.booking_events where booking_id = ? order by id",
                (rs, n) -> new HistoryEntry(rs.getString(1), rs.getString(2), rs.getString(3), rs.getObject(4, OffsetDateTime.class)), id);
        List<AdminAction> actions = db.query("select action, reason, occurred_at from marketplace.home_service_admin_events where booking_id = ? order by id",
                (rs, n) -> new AdminAction(rs.getString(1), rs.getString(2), rs.getObject(3, OffsetDateTime.class)), id);
        boolean actionable = "PENDING".equals(order.status()) || "CONFIRMED".equals(order.status());
        return new Detail(order, (String) extra.get("address_text"), (Integer) extra.get("area_sqm"), (String) extra.get("comment"),
                (String) extra.get("cancel_reason"), ((Number) extra.get("version")).longValue(), actionable, visit, history, actions);
    }

    private static Row row(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Row(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                rs.getString(7), rs.getObject(8, OffsetDateTime.class), rs.getLong(9), rs.getObject(10, OffsetDateTime.class), rs.getString(11));
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found");
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    private UUID authorize(Jwt principal) {
        UUID actor;
        try {
            actor = UUID.fromString(principal.getSubject());
        } catch (RuntimeException invalidSubject) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Access is not allowed");
        }
        grants.require(actor, AdminGrants.Permission.HOME_SERVICES_OPERATIONS);
        return actor;
    }
}
