package kz.kunde.booking;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Explicit environment opt-in for the Beauty &amp; Care product (flag {@code BEAUTY_ENABLED}, off by default).
 * Like the Home Services pilot it is allowed only in an explicit dev/local/test environment and needs the Booking engine.
 */
@Component
public class BeautySettings {
    private final boolean allowed;

    public BeautySettings(Environment environment) {
        boolean requested = environment.getProperty("app.beauty.enabled", Boolean.class, false);
        boolean internal = Set.of("local", "dev", "test").contains(environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        if (requested && !internal) {
            throw new IllegalStateException("Beauty requires an explicit dev/local/test environment");
        }
        this.allowed = requested && environment.getProperty("app.booking.enabled", Boolean.class, false);
    }

    public boolean allowedByEnvironment() {
        return allowed;
    }
}
