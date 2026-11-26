package kz.kunde.food;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import kz.kunde.food.FoodCatalogController.Hours;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Restaurant location and weekly opening hours, edited by the owning partner (Owner/Manager). Times are Asia/Almaty
 * local. A restaurant without any slot has no schedule restriction (the manual open switch still applies); with slots it
 * is open only inside them. Replacing the schedule is atomic and audited.
 */
@Service
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
class FoodScheduleService {
    static final int MAX_SLOTS = 28;

    private final JdbcTemplate db;
    private final FoodPartnerService partner;

    FoodScheduleService(JdbcTemplate db, FoodPartnerService partner) {
        this.db = db;
        this.partner = partner;
    }

    record Schedule(Double latitude, Double longitude, List<Hours> hours, boolean openNow) {}

    static List<Hours> hours(JdbcTemplate db, UUID restaurantId) {
        return db.query("""
                select day_of_week, to_char(opens_at, 'HH24:MI'), case when closes_at = time '24:00' then '24:00' else to_char(closes_at, 'HH24:MI') end
                from marketplace.food_restaurant_hours where restaurant_id = ? order by day_of_week, opens_at""",
                (rs, n) -> new Hours(rs.getInt(1), rs.getString(2), rs.getString(3)), restaurantId);
    }

    @Transactional(readOnly = true)
    Schedule get(UUID actor, UUID partnerId, UUID restaurantId) {
        partner.requireOwnedRestaurantFor(actor, partnerId, restaurantId);
        return read(restaurantId);
    }

    @Transactional
    Schedule replaceHours(UUID actor, UUID partnerId, UUID restaurantId, List<Hours> slots) {
        partner.requireManager(actor, partnerId);
        lock(partnerId, restaurantId);
        if (slots == null || slots.size() > MAX_SLOTS) {
            throw invalid("hours must contain 0.." + MAX_SLOTS + " slots");
        }
        Set<String> seen = new HashSet<>();
        for (Hours slot : slots) {
            if (slot == null || slot.dayOfWeek() < 1 || slot.dayOfWeek() > 7) { throw invalid("dayOfWeek must be 1..7"); }
            int opens = minutes(slot.opensAt(), false);
            int closes = minutes(slot.closesAt(), true);
            if (opens == closes || !seen.add(slot.dayOfWeek() + "/" + opens)) { throw invalid("empty or duplicate slot"); }
        }
        String before = describe(hours(db, restaurantId));
        db.update("delete from marketplace.food_restaurant_hours where restaurant_id = ?", restaurantId);
        for (Hours slot : slots) {
            db.update("insert into marketplace.food_restaurant_hours (restaurant_id, day_of_week, opens_at, closes_at) values (?, ?, ?::time, ?::time)",
                    restaurantId, slot.dayOfWeek(), slot.opensAt(), slot.closesAt());
        }
        partner.auditCatalog(partnerId, actor, "RESTAURANT", restaurantId, "hours", before, describe(hours(db, restaurantId)));
        return read(restaurantId);
    }

    /** Both coordinates, or both null to forget the location (the restaurant then has no distance). */
    @Transactional
    Schedule setLocation(UUID actor, UUID partnerId, UUID restaurantId, Double latitude, Double longitude) {
        partner.requireManager(actor, partnerId);
        lock(partnerId, restaurantId);
        if ((latitude == null) != (longitude == null) || (latitude != null && (!(latitude >= -90 && latitude <= 90)
                || !(longitude >= -180 && longitude <= 180)))) {
            throw invalid("latitude and longitude must be given together within range");
        }
        String before = db.queryForObject("select coalesce(latitude::text || ',' || longitude::text, '') from marketplace.food_restaurants where id = ?",
                String.class, restaurantId);
        db.update("update marketplace.food_restaurants set latitude = ?, longitude = ? where id = ?", latitude, longitude, restaurantId);
        partner.auditCatalog(partnerId, actor, "RESTAURANT", restaurantId, "location", before,
                latitude == null ? "" : latitude + "," + longitude);
        return read(restaurantId);
    }

    private Schedule read(UUID restaurantId) {
        var row = db.queryForMap("""
                select latitude::float8 as lat, longitude::float8 as lon, marketplace.food_restaurant_open(r) as open_now
                from marketplace.food_restaurants r where id = ?""", restaurantId);
        return new Schedule((Double) row.get("lat"), (Double) row.get("lon"), hours(db, restaurantId), (Boolean) row.get("open_now"));
    }

    private void lock(UUID partnerId, UUID restaurantId) {
        List<UUID> owned = db.queryForList("select id from marketplace.food_restaurants where id = ? and partner_id = ? for update",
                UUID.class, restaurantId, partnerId);
        if (owned.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant not found");
        }
    }

    /** Minutes since midnight; 24:00 (1440) is allowed only as a closing time so a full day stays distinguishable from an empty slot. */
    private static int minutes(String value, boolean closing) {
        if (value == null || !value.matches("\\d{2}:\\d{2}")) { throw invalid("time must be HH:mm"); }
        int h = Integer.parseInt(value.substring(0, 2));
        int m = Integer.parseInt(value.substring(3));
        if (m > 59 || h > 24 || (h == 24 && (m != 0 || !closing))) { throw invalid("time must be HH:mm within the day"); }
        return h * 60 + m;
    }

    private static String describe(List<Hours> hours) {
        return hours.stream().map(h -> h.dayOfWeek() + " " + h.opensAt() + "-" + h.closesAt()).reduce((a, b) -> a + "; " + b).orElse("");
    }

    private static ApiException invalid(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "RESTAURANT_SCHEDULE_INVALID", message);
    }
}
