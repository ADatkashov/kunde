package kz.kunde.booking;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Plug-in point of the booking engine for one venue category (for example {@code BARBER} is Beauty, {@code CLEANING} is
 * Home Services). The product module implements it, so the engine never reads the product's tables or feature flag.
 */
public interface BookingCategory {
    /** The value stored in {@code marketplace.booking_venues.category}. */
    String category();

    /** Throws a 404 {@code ApiException} when the product is switched off. */
    void requireAvailable();

    /** Percentage discount applied right now to the list price of the venue's services, or {@code null}. */
    default Integer discountPercent(UUID venueId) {
        return null;
    }

    /** Whether a booking at this venue is confirmed at once instead of waiting for the partner's answer. */
    default boolean confirmsInstantly(UUID venueId) {
        return false;
    }

    /** What a vertical needs to price or refuse a booking beyond the list price. */
    record PricingContext(UUID venueId, UUID serviceId, long listPriceMinor, OffsetDateTime startsAt, java.time.ZoneId venueZone,
            Double latitude, Double longitude, boolean urgent) {}

    /**
     * Amount added to the list price after any discount: call-out fee, urgent or evening surcharge. May refuse the booking
     * with an {@code ApiException} (for example when the address is outside the venue's service area). The same method
     * prices the public quote, so a quote and the booking made from it cannot disagree.
     */
    default long surchargeMinor(PricingContext context) {
        return 0;
    }
}
