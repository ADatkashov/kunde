package kz.kunde.booking;

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
}
