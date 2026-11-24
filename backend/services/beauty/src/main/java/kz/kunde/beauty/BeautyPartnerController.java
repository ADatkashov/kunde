package kz.kunde.beauty;

import java.util.List;
import java.util.UUID;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.partner.PartnerService;
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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** KUNDE Partner for Beauty: the salon overview (today's bookings and revenue) and masters with their invite codes. */
@RestController
@RequestMapping("/api/v1/partner/partners/{partnerId}/beauty")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class BeautyPartnerController {
    public record Salon(String id, String name, String addressText) {}

    /** Percent changes are null when the previous day had nothing to compare with. */
    public record Overview(List<Salon> salons, long bookingsToday, Integer bookingsDeltaPercent, long revenueTodayMinor,
            Integer revenueDeltaPercent, long pendingRequests, long mastersOnline, long mastersTotal) {}

    public record MasterRow(String id, String venueId, String name, String specialty, boolean online, boolean linked,
            String inviteCode) {}

    private static final String ACTIVE = "b.status in ('CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'COMPLETED')";
    private static final String TODAY = "(now() at time zone 'Asia/Almaty')::date";

    private final JdbcTemplate db;
    private final PartnerService partners;
    private final FeatureToggles toggles;

    public BeautyPartnerController(JdbcTemplate db, PartnerService partners, FeatureToggles toggles) {
        this.db = db;
        this.partners = partners;
        this.toggles = toggles;
    }

    private void authorize(Jwt principal, UUID partnerId) {
        if (!toggles.enabled(Feature.BEAUTY)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BEAUTY_DISABLED", "Beauty is unavailable");
        }
        partners.requireProcessing(PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed")), partnerId);
    }

    private static Integer delta(long today, long yesterday) {
        return yesterday == 0 ? null : (int) Math.round((today - yesterday) * 100.0 / yesterday);
    }

    @GetMapping("/overview")
    ResponseEntity<Overview> overview(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        authorize(principal, partnerId);
        List<Salon> salons = db.query("select v.id::text, v.name, v.address_text from marketplace.booking_venues v "
                + "where v.partner_id = ? and v.category = 'BARBER' order by v.sort_order, v.name",
                (rs, row) -> new Salon(rs.getString(1), rs.getString(2), rs.getString(3)), partnerId);
        var counts = db.queryForMap("select count(*) filter (where " + ACTIVE + " and (b.starts_at at time zone 'Asia/Almaty')::date = " + TODAY + ") as today_count, "
                + "coalesce(sum(b.price_minor) filter (where " + ACTIVE + " and (b.starts_at at time zone 'Asia/Almaty')::date = " + TODAY + "), 0) as today_revenue, "
                + "count(*) filter (where " + ACTIVE + " and (b.starts_at at time zone 'Asia/Almaty')::date = " + TODAY + " - 1) as yesterday_count, "
                + "coalesce(sum(b.price_minor) filter (where " + ACTIVE + " and (b.starts_at at time zone 'Asia/Almaty')::date = " + TODAY + " - 1), 0) as yesterday_revenue, "
                + "count(*) filter (where b.status = 'PENDING') as pending "
                + "from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id "
                + "where v.partner_id = ? and v.category = 'BARBER'", partnerId);
        var masters = db.queryForMap("select count(*) filter (where m.online) as online, count(*) as total "
                + "from marketplace.booking_masters m join marketplace.booking_venues v on v.id = m.venue_id "
                + "where v.partner_id = ? and v.category = 'BARBER' and m.active", partnerId);
        long today = ((Number) counts.get("today_count")).longValue();
        long revenue = ((Number) counts.get("today_revenue")).longValue();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new Overview(salons, today,
                delta(today, ((Number) counts.get("yesterday_count")).longValue()), revenue,
                delta(revenue, ((Number) counts.get("yesterday_revenue")).longValue()), ((Number) counts.get("pending")).longValue(),
                ((Number) masters.get("online")).longValue(), ((Number) masters.get("total")).longValue()));
    }

    @GetMapping("/masters")
    ResponseEntity<List<MasterRow>> masters(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        authorize(principal, partnerId);
        List<MasterRow> rows = db.query("""
                select m.id::text, m.venue_id::text, m.name, m.specialty, m.online, m.user_id is not null as linked,
                       case when m.user_id is null then m.invite_code end as invite_code
                from marketplace.booking_masters m join marketplace.booking_venues v on v.id = m.venue_id
                where v.partner_id = ? and v.category = 'BARBER' and m.active order by v.sort_order, m.sort_order, m.name
                """, (rs, row) -> new MasterRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getBoolean(5),
                rs.getBoolean(6), rs.getString(7)), partnerId);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(rows);
    }
}
