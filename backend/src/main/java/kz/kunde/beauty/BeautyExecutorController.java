package kz.kunde.beauty;

import kz.kunde.booking.BookingService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
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
 * KUNDE Executor for a Beauty master: own appointments, start/complete/no-show, availability, own earnings.
 * A master only ever sees and changes bookings of the master record linked to their own account.
 */
@RestController
@Validated
@RequestMapping("/api/v1/executor/beauty")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BeautyExecutorController {
    public record Appointment(String id, String bookingNumber, String serviceName, String venueName, String venueAddress,
            String clientName, OffsetDateTime startsAt, OffsetDateTime endsAt, String status, boolean canStart,
            boolean canComplete, boolean canMarkNoShow) {}

    public record Today(String masterName, String venueName, boolean online, long todayCount, List<Appointment> appointments) {}

    public record Earnings(long todayMinor, long weekMinor, long monthMinor, long completedToday, long completedMonth,
            String currency) {}

    public record LinkRequest(@NotBlank @Pattern(regexp = "[A-Za-z0-9-]{6,24}") String code) {}

    public record AvailabilityRequest(@NotNull Boolean online) {}

    private static final String ZONE_DAY = "(%s at time zone 'Asia/Almaty')::date";

    private final JdbcTemplate db;
    private final ConsumerIdentityService identity;
    private final FeatureToggles toggles;
    private final BookingService bookings;

    public BeautyExecutorController(JdbcTemplate db, ConsumerIdentityService identity, FeatureToggles toggles, BookingService bookings) {
        this.db = db;
        this.identity = identity;
        this.toggles = toggles;
        this.bookings = bookings;
    }

    private UUID user(Jwt principal) {
        if (!toggles.enabled(Feature.BEAUTY)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BEAUTY_DISABLED", "Beauty is unavailable");
        }
        return identity.get(principal).id();
    }

    private UUID master(UUID user) {
        return db.query("select id from marketplace.booking_masters where user_id = ? and active", (rs, row) -> rs.getObject(1, UUID.class), user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_A_MASTER", "This account is not linked to a master"));
    }

    /** Links the signed-in account to the master the salon gave the invite code for; the code works once. */
    @PostMapping("/link")
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

    private static String clientName(String displayName) {
        if (displayName == null || displayName.isBlank()) { return ""; }
        String[] parts = displayName.trim().split("\\s+");
        return parts.length > 1 ? parts[0] + " " + parts[1].charAt(0) + "." : parts[0];
    }

    @GetMapping("/today")
    @Transactional
    ResponseEntity<Today> today(@AuthenticationPrincipal Jwt principal) {
        UUID user = user(principal);
        UUID master = master(user);
        bookings.completeDue("master_id = ?", master);
        var info = db.queryForMap("select m.name, v.name as venue_name, m.online from marketplace.booking_masters m "
                + "join marketplace.booking_venues v on v.id = m.venue_id where m.id = ?", master);
        List<Appointment> list = db.query("""
                select b.id::text, b.booking_number, b.service_name, b.venue_name, b.venue_address, b.starts_at, b.ends_at, b.status,
                       p.display_name,
                       (b.status = 'CONFIRMED' and now() >= b.starts_at - interval '30 minutes') as can_start,
                       (b.status = 'IN_PROGRESS') as can_complete,
                       (b.status = 'CONFIRMED' and now() > b.starts_at + interval '10 minutes') as can_no_show
                from transactions.bookings b left join profile.consumer_profiles p on p.user_id = b.user_id
                where b.master_id = ? and b.status in ('CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS')
                  and (b.ends_at > now() or b.status = 'IN_PROGRESS') and b.starts_at < now() + interval '7 days'
                order by b.starts_at, b.id
                """, (rs, row) -> new Appointment(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                clientName(rs.getString(9)), rs.getObject(6, OffsetDateTime.class), rs.getObject(7, OffsetDateTime.class), rs.getString(8),
                rs.getBoolean(10), rs.getBoolean(11), rs.getBoolean(12)), master);
        long todayCount = db.queryForObject("select count(*) from transactions.bookings b where b.master_id = ? and b.status in "
                + "('CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'COMPLETED') and " + ZONE_DAY.formatted("b.starts_at") + " = " + ZONE_DAY.formatted("now()"),
                Long.class, master);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new Today((String) info.get("name"), (String) info.get("venue_name"),
                (Boolean) info.get("online"), todayCount, list));
    }

    /** Goes online/offline for NEW bookings. Confirmed bookings are not cancelled or moved. */
    @PutMapping("/availability")
    @Transactional
    ResponseEntity<Void> availability(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody AvailabilityRequest request) {
        db.update("update marketplace.booking_masters set online = ? where id = ?", request.online(), master(user(principal)));
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PostMapping("/appointments/{id}/start")
    @Transactional
    ResponseEntity<Void> start(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return transition(principal, id, "CONFIRMED", "IN_PROGRESS", "starts_at - interval '30 minutes' <= now()", "TOO_EARLY");
    }

    @PostMapping("/appointments/{id}/complete")
    @Transactional
    ResponseEntity<Void> complete(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return transition(principal, id, "IN_PROGRESS", "COMPLETED", "true", "NOT_ALLOWED");
    }

    @PostMapping("/appointments/{id}/no-show")
    @Transactional
    ResponseEntity<Void> noShow(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return transition(principal, id, "CONFIRMED", "NO_SHOW", "starts_at + interval '10 minutes' < now()", "TOO_EARLY");
    }

    private ResponseEntity<Void> transition(Jwt principal, UUID id, String from, String to, String timeRule, String timeCode) {
        UUID user = user(principal);
        UUID master = master(user);
        var row = db.query("select status, " + timeRule + " from transactions.bookings where id = ? and master_id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getBoolean(2)}, id, master).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "APPOINTMENT_NOT_FOUND", "Appointment not found"));
        if (!from.equals(row[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "APPOINTMENT_STATE_INVALID", "The appointment is not in a state that allows this action");
        }
        if (!(boolean) row[1]) {
            throw new ApiException(HttpStatus.CONFLICT, "APPOINTMENT_" + timeCode, "It is not the right time for this action");
        }
        db.update("update transactions.bookings set status = ?, updated_at = now(), version = version + 1 where id = ?", to, id);
        bookings.event(id, to, "PARTNER", user, null);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    /** Only the master's own completed work, not the salon's revenue. */
    @GetMapping("/earnings")
    ResponseEntity<Earnings> earnings(@AuthenticationPrincipal Jwt principal) {
        UUID master = master(user(principal));
        String day = ZONE_DAY.formatted("b.starts_at");
        String today = ZONE_DAY.formatted("now()");
        var sums = db.queryForMap("select coalesce(sum(b.price_minor) filter (where " + day + " = " + today + "), 0) as today_sum, "
                + "coalesce(sum(b.price_minor) filter (where " + day + " > " + today + " - 7), 0) as week_sum, "
                + "coalesce(sum(b.price_minor), 0) as month_sum, count(*) filter (where " + day + " = " + today + ") as today_count, count(*) as month_count "
                + "from transactions.bookings b where b.master_id = ? and b.status = 'COMPLETED' and " + day + " > " + today + " - 30", master);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new Earnings(((Number) sums.get("today_sum")).longValue(),
                ((Number) sums.get("week_sum")).longValue(), ((Number) sums.get("month_sum")).longValue(),
                ((Number) sums.get("today_count")).longValue(), ((Number) sums.get("month_count")).longValue(), "KZT"));
    }
}
