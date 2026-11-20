package kz.kunde.health;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

@Component
public class HealthSettings {
    private final boolean enabled;
    private final boolean seedDemo;

    public HealthSettings(Environment environment) {
        boolean internal = Set.of("local", "dev", "test").contains(
                environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        boolean requested = environment.getProperty("app.health.enabled", Boolean.class,
                environment.getProperty("HEALTH_ENABLED", Boolean.class, internal));
        seedDemo = environment.getProperty("app.health.seed-demo", Boolean.class, false);
        if (!internal && (requested || seedDemo)) {
            throw new IllegalStateException("Health pilot requires LOCAL, DEV or TEST");
        }
        enabled = requested && environment.getProperty("app.booking.enabled", Boolean.class, false);
        if (seedDemo && !enabled) {
            throw new IllegalStateException("Health synthetic seed requires Health and Booking");
        }
    }

    public boolean enabled() {
        return enabled;
    }

    public boolean seedDemo() {
        return seedDemo;
    }
}
