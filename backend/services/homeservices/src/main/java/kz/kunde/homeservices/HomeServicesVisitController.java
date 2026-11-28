package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingService;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
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
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Visits of Home Services bookings. The master (Executor) reports the way: on the way, arrived, started, finished; the
 * customer reads the same progress. The booking keeps the Booking Engine statuses ({@code CONFIRMED -> IN_PROGRESS ->
 * COMPLETED}); "on the way" and "arrived" refine CONFIRMED and live in {@code home_service_visits}, owned here.
 * A master only ever sees and changes bookings of the master record linked to their own account; a customer only their own.
 */
@RestController
@Validated
@RequestMapping("/api/v1")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class HomeServicesVisitController {
    private static final String CATEGORY = "CLEANING";

    public record Job(String id, String bookingNumber, String serviceName, String venueName, String addressText,
            OffsetDateTime startsAt, OffsetDateTime endsAt, String status, String stage, Integer etaMinutes,
            long priceMinor) {}

    public record Visit(String bookingId, String status, String stage, Integer etaMinutes) {}

    public record LinkRequest(@NotBlank @Pattern(regexp = "[A-Za-z0-9-]{6,24}") String code) {}

    /** {@code latitude}/{@code longitude} are the master's position when leaving: with them the ETA comes from KUNDE Maps. */
    public record StageRequest(@NotNull @Pattern(regexp = "EN_ROUTE|ARRIVED") String stage,
            @Min(0) @Max(600) Integer etaMinutes,
            @jakarta.validation.constraints.DecimalMin("-90") @jakarta.validation.constraints.DecimalMax("90") Double latitude,
            @jakarta.validation.constraints.DecimalMin("-180") @jakarta.validation.constraints.DecimalMax("180") Double longitude) {}

    private final JdbcTemplate db;
    private final FeatureToggles toggles;
    private final BookingService bookings;
    private final HomeServiceEta eta;

    public HomeServicesVisitController(JdbcTemplate db, FeatureToggles toggles, BookingService bookings, HomeServiceEta eta) {
        this.db = db;
        this.toggles = toggles;
        this.bookings = bookings;
        this.eta = eta;
    }

    private UUID user(Jwt principal) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        try {
            return UUID.fromString(principal.getSubject());
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed");
        }
    }

    private UUID master(UUID user) {
        return db.query("select id from marketplace.booking_masters where user_id = ? and active",
                (rs, row) -> rs.getObject(1, UUID.class), user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_A_MASTER", "This account is not linked to a master"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    // ---- Executor

    /** Links the signed-in account to the master the venue gave the invite code for; the code works once. */
    @PostMapping("/executor/home-services/link")
    @Transactional
    ResponseEntity<Void> link(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody LinkRequest request) {
        UUID user = user(principal);
        int linked = db.update("update marketplace.booking_masters set user_id = ?, invite_code = null "
                + "where invite_code = ? and user_id is null and active and not exists (select 1 from marketplace.booking_masters x where x.user_id = ?)",
                user, request.code().toUpperCase(), user);
        if (linked == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "INVITE_INVALID", "The invite code is invalid or already used");
        }
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    /** Own upcoming and running jobs (next 7 days) and ones that ended in the last 12 hours but were not finished, earliest first. */
    @GetMapping("/executor/home-services/jobs")
    @Transactional(readOnly = true)
    ResponseEntity<List<Job>> jobs(@AuthenticationPrincipal Jwt principal) {
        UUID master = master(user(principal));
        return ok(db.query("""
                select b.id, b.booking_number, b.service_name, b.venue_name, b.address_text, b.starts_at, b.ends_at, b.status,
                       v.stage, case when v.stage = 'EN_ROUTE' and v.eta_minutes is not null
                            then greatest(0, v.eta_minutes - floor(extract(epoch from (now() - v.updated_at)) / 60)::int)
                            else v.eta_minutes end, b.price_minor
                from transactions.bookings b left join marketplace.home_service_visits v on v.booking_id = b.id
                where b.master_id = ? and b.category = ? and b.status in ('CONFIRMED', 'IN_PROGRESS')
                  and (b.ends_at > now() - interval '12 hours' or b.status = 'IN_PROGRESS') and b.starts_at < now() + interval '7 days'
                order by b.starts_at, b.id
                """, (rs, row) -> new Job(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                rs.getObject(6, OffsetDateTime.class), rs.getObject(7, OffsetDateTime.class), rs.getString(8),
                rs.getString(9), rs.getObject(10, Integer.class), rs.getLong(11)), master, CATEGORY));
    }

    /** The master's own booking, locked for the transition. */
    private Object[] lockJob(UUID master, UUID id) {
        return db.query("select status from transactions.bookings where id = ? and master_id = ? and category = ? for update",
                (rs, n) -> new Object[] {rs.getString(1)}, id, master, CATEGORY).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
    }

    private String stage(UUID bookingId) {
        return db.query("select stage from marketplace.home_service_visits where booking_id = ?", (rs, n) -> rs.getString(1), bookingId)
                .stream().findFirst().orElse(null);
    }

    private static ApiException stateInvalid() {
        return new ApiException(HttpStatus.CONFLICT, "JOB_STATE_INVALID", "The job is not in a state that allows this action");
    }

    /** Reports the way: {@code EN_ROUTE} (optionally with an ETA, repeatable to refresh it) and then {@code ARRIVED}. */
    @PutMapping("/executor/home-services/jobs/{id}/stage")
    @Transactional
    ResponseEntity<Visit> stage(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
            @Valid @RequestBody StageRequest request) {
        UUID master = master(user(principal));
        String status = (String) lockJob(master, id)[0];
        String current = stage(id);
        if (!"CONFIRMED".equals(status)) {
            throw stateInvalid();
        }
        if ("EN_ROUTE".equals(request.stage())) {
            if ("ARRIVED".equals(current)) {
                throw stateInvalid();
            }
            Integer minutes = request.etaMinutes();
            if (request.latitude() != null && request.longitude() != null) {
                String address = db.queryForObject("select address_text from transactions.bookings where id = ?", String.class, id);
                var measured = eta.minutes(address, new kz.kunde.platform.geo.Point(request.latitude(), request.longitude()));
                if (measured.isPresent()) {
                    minutes = Math.min(600, measured.getAsInt());
                }
            }
            db.update("""
                    insert into marketplace.home_service_visits (booking_id, stage, eta_minutes) values (?, 'EN_ROUTE', ?)
                    on conflict (booking_id) do update set eta_minutes = excluded.eta_minutes, updated_at = now()
                    """, id, minutes);
        } else {
            if (!"EN_ROUTE".equals(current)) {
                throw stateInvalid();
            }
            db.update("update marketplace.home_service_visits set stage = 'ARRIVED', eta_minutes = 0, arrived_at = now(), updated_at = now() "
                    + "where booking_id = ?", id);
        }
        return ok(visit(id));
    }

    /** Starts the work: only after the master has reported that they arrived. */
    @PostMapping("/executor/home-services/jobs/{id}/start")
    @Transactional
    ResponseEntity<Visit> start(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        UUID user = user(principal);
        UUID master = master(user);
        if (!"CONFIRMED".equals(lockJob(master, id)[0]) || !"ARRIVED".equals(stage(id))) {
            throw stateInvalid();
        }
        setStatus(id, "IN_PROGRESS", user);
        return ok(visit(id));
    }

    @PostMapping("/executor/home-services/jobs/{id}/complete")
    @Transactional
    ResponseEntity<Visit> complete(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        UUID user = user(principal);
        UUID master = master(user);
        String status = (String) lockJob(master, id)[0];
        if (!"COMPLETED".equals(status)) {
            if (!"IN_PROGRESS".equals(status)) {
                throw stateInvalid();
            }
            setStatus(id, "COMPLETED", user);
        }
        return ok(visit(id));
    }

    private void setStatus(UUID id, String status, UUID actor) {
        db.update("update transactions.bookings set status = ?, updated_at = now(), version = version + 1 where id = ?", status, id);
        bookings.event(id, status, "PARTNER", actor, null);
    }

    private Visit visit(UUID bookingId) {
        return db.query("""
                select b.id, b.status, v.stage, case when v.stage = 'EN_ROUTE' and v.eta_minutes is not null
                            then greatest(0, v.eta_minutes - floor(extract(epoch from (now() - v.updated_at)) / 60)::int)
                            else v.eta_minutes end from transactions.bookings b
                left join marketplace.home_service_visits v on v.booking_id = b.id where b.id = ?
                """, (rs, n) -> new Visit(rs.getString(1), rs.getString(2), rs.getString(3), rs.getObject(4, Integer.class)), bookingId)
                .getFirst();
    }

    // ---- Consumer

    /** Progress of the customer's own booking; anyone else's booking is "not found". */
    @GetMapping("/home-services/bookings/{id}/visit")
    @Transactional(readOnly = true)
    ResponseEntity<Visit> customerVisit(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        UUID user = user(principal);
        boolean mine = !db.queryForList("select 1 from transactions.bookings where id = ? and user_id = ? and category = ?",
                id, user, CATEGORY).isEmpty();
        if (!mine) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found");
        }
        return ok(visit(id));
    }
}
