package kz.kunde.homeservices;

import kz.kunde.booking.BookingCategory;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

/** Home Services rules for the booking engine's {@code CLEANING} venues: the feature switch. */
@Component
public class HomeServicesBookingCategory implements BookingCategory {
    private final FeatureToggles toggles;

    public HomeServicesBookingCategory(FeatureToggles toggles) {
        this.toggles = toggles;
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
}
