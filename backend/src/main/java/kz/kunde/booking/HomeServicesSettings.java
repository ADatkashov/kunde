package kz.kunde.booking;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/** Explicit environment opt-in for the Home Services Booking pilot. */
@Component
public class HomeServicesSettings {
    private final boolean allowed;

    public HomeServicesSettings(Environment environment) {
        boolean requested = environment.getProperty("app.home-services.enabled", Boolean.class, false);
        boolean internal = Set.of("local", "dev", "test").contains(environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        if (requested && !internal) {
            throw new IllegalStateException("Home Services pilot requires an explicit dev/local/test environment");
        }
        this.allowed = requested && environment.getProperty("app.booking.enabled", Boolean.class, false);
    }

    public boolean allowedByEnvironment() {
        return allowed;
    }
}
