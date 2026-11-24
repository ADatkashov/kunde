package kz.kunde.beauty;

import java.util.UUID;
import kz.kunde.booking.BookingCategory;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Beauty rules for the booking engine's {@code BARBER} venues: feature switch, promotions, instant confirmation. */
@Component
public class BeautyBookingCategory implements BookingCategory {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public BeautyBookingCategory(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    @Override
    public String category() {
        return "BARBER";
    }

    @Override
    public void requireAvailable() {
        if (!toggles.enabled(FeatureToggles.Feature.BEAUTY)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BEAUTY_DISABLED", "Beauty is unavailable");
        }
    }

    /** A promotion (the venue's or platform-wide) active right now. */
    @Override
    public Integer discountPercent(UUID venueId) {
        return db.queryForObject("""
                select max(percent) from marketplace.beauty_promotions
                where active and now() >= starts_at and now() < ends_at and (venue_id = ? or venue_id is null)
                """, Integer.class, venueId);
    }

    /** Beauty salons confirm instantly; other partner venues answer requests. */
    @Override
    public boolean confirmsInstantly(UUID venueId) {
        return Boolean.TRUE.equals(db.queryForObject(
                "select exists (select 1 from marketplace.beauty_salon_profiles where venue_id = ?)", Boolean.class, venueId));
    }
}
