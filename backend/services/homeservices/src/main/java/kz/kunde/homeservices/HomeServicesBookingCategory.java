package kz.kunde.homeservices;

import kz.kunde.booking.BookingCategory;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

/** Home Services rules for the booking engine's {@code CLEANING} venues: the feature switch, service zones and surcharges. */
@Component
public class HomeServicesBookingCategory implements BookingCategory {
    private final FeatureToggles toggles;
    private final HomeServicePricing pricing;

    public HomeServicesBookingCategory(FeatureToggles toggles, HomeServicePricing pricing) {
        this.toggles = toggles;
        this.pricing = pricing;
    }

    @Override
    public String category() {
        return "CLEANING";
    }

    @Override
    public void requireAvailable() {
        if (!toggles.enabled(FeatureToggles.Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
    }

    @Override
    public long surchargeMinor(PricingContext context) {
        return pricing.charges(context.venueId(), context.serviceId(), context.listPriceMinor(), context.startsAt(),
                context.venueZone(), context.latitude(), context.longitude(), context.urgent()).totalMinor();
    }
}
