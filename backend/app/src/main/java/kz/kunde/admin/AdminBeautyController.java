package kz.kunde.admin;

import kz.kunde.platform.authz.AdminGrants;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
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
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Aggregated Beauty analytics for platform administrators (BEAUTY_OPERATIONS). Personal data is limited to an initial. */
@RestController
@Validated
@RequestMapping("/api/v1/admin/beauty")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminBeautyController {
    public record DayCount(String date, long bookings) {}

    public record CategoryShare(String code, long bookings, int percent) {}

    public record Recent(String bookingNumber, String client, String salon, String service, long amountMinor, String status, OffsetDateTime startsAt) {}

    public record Analytics(int days, long salons, Integer salonsDeltaPercent, long bookings, Integer bookingsDeltaPercent,
            long revenueMinor, Integer revenueDeltaPercent, long averageCheckMinor, Integer averageCheckDeltaPercent,
            List<DayCount> bookingsByDay, List<CategoryShare> categories, List<Recent> recent) {}

    private static final String ACTIVE = "b.status in ('CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'COMPLETED')";

    private final JdbcTemplate db;
    private final AdminGrants grants;

    public AdminBeautyController(JdbcTemplate db, AdminGrants grants) {
        this.db = db;
        this.grants = grants;
    }

    private static Integer delta(long now, long before) {
        return before == 0 ? null : (int) Math.round((now - before) * 100.0 / before);
    }

    @GetMapping("/analytics")
    ResponseEntity<Analytics> analytics(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "7") @Min(1) @Max(90) int days) {
        UUID actor = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Access is not allowed"));
        grants.require(actor, AdminGrants.Permission.BEAUTY_OPERATIONS);
        String day = "(b.starts_at at time zone 'Asia/Almaty')::date";
        String today = "(now() at time zone 'Asia/Almaty')::date";
        var totals = db.queryForMap("select count(*) filter (where " + ACTIVE + " and " + day + " > " + today + " - ?) as cur_count, "
                + "coalesce(sum(b.price_minor) filter (where " + ACTIVE + " and " + day + " > " + today + " - ?), 0) as cur_sum, "
                + "count(*) filter (where " + ACTIVE + " and " + day + " <= " + today + " - ? and " + day + " > " + today + " - 2 * ?) as prev_count, "
                + "coalesce(sum(b.price_minor) filter (where " + ACTIVE + " and " + day + " <= " + today + " - ? and " + day + " > " + today + " - 2 * ?), 0) as prev_sum "
                + "from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id "
                + "join marketplace.beauty_salon_profiles p on p.venue_id = v.id", days, days, days, days, days, days);
        long bookings = ((Number) totals.get("cur_count")).longValue();
        long revenue = ((Number) totals.get("cur_sum")).longValue();
        long prevBookings = ((Number) totals.get("prev_count")).longValue();
        long prevRevenue = ((Number) totals.get("prev_sum")).longValue();
        long average = bookings == 0 ? 0 : Math.round((double) revenue / bookings);
        long prevAverage = prevBookings == 0 ? 0 : Math.round((double) prevRevenue / prevBookings);
        long salons = db.queryForObject("select count(*) from marketplace.beauty_salon_profiles p join marketplace.booking_venues v on v.id = p.venue_id where v.is_open", Long.class);
        long salonsBefore = db.queryForObject("select count(*) from marketplace.beauty_salon_profiles p join marketplace.booking_venues v on v.id = p.venue_id "
                + "where v.is_open and v.created_at < now() - make_interval(days => ?)", Long.class, days);
        List<DayCount> byDay = db.query("select d::text, count(b.id) from generate_series(" + today + " - (? - 1), " + today + ", interval '1 day') d "
                + "left join (select b.id, " + day + " as day from transactions.bookings b join marketplace.beauty_salon_profiles p on p.venue_id = b.venue_id where " + ACTIVE + ") b on b.day = d::date "
                + "group by d order by d", (rs, row) -> new DayCount(rs.getString(1).substring(0, 10), rs.getLong(2)), days);
        List<CategoryShare> shares = db.query("select coalesce(sp.category_code, 'OTHER') as code, count(*) from transactions.bookings b "
                + "join marketplace.beauty_salon_profiles p on p.venue_id = b.venue_id left join marketplace.beauty_service_profiles sp on sp.service_id = b.service_id "
                + "where " + ACTIVE + " and " + day + " > " + today + " - ? group by 1 order by 2 desc, 1 limit 8",
                (rs, row) -> new CategoryShare(rs.getString(1), rs.getLong(2), 0), days);
        long totalShares = shares.stream().mapToLong(CategoryShare::bookings).sum();
        List<CategoryShare> withPercent = shares.stream().map(s -> new CategoryShare(s.code(), s.bookings(),
                totalShares == 0 ? 0 : (int) Math.round(s.bookings() * 100.0 / totalShares))).toList();
        List<Recent> recent = db.query("select b.booking_number, pr.display_name, b.venue_name, b.service_name, b.price_minor, b.status, b.starts_at "
                + "from transactions.bookings b join marketplace.beauty_salon_profiles p on p.venue_id = b.venue_id "
                + "left join profile.consumer_profiles pr on pr.user_id = b.user_id order by b.created_at desc, b.id limit 10",
                (rs, row) -> new Recent(rs.getString(1), initial(rs.getString(2)), rs.getString(3), rs.getString(4), rs.getLong(5), rs.getString(6),
                        rs.getObject(7, OffsetDateTime.class)));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new Analytics(days, salons, delta(salons, salonsBefore), bookings,
                delta(bookings, prevBookings), revenue, delta(revenue, prevRevenue), average, delta(average, prevAverage), byDay, withPercent, recent));
    }

    private static String initial(String displayName) {
        if (displayName == null || displayName.isBlank()) { return ""; }
        String[] parts = displayName.trim().split("\\s+");
        return parts.length > 1 ? parts[0] + " " + parts[1].charAt(0) + "." : parts[0];
    }
}
