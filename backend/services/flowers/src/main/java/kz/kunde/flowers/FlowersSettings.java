package kz.kunde.flowers;

import kz.kunde.platform.FeatureGate;
import kz.kunde.platform.FeatureToggles;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Explicit environment opt-in for Flowers &amp; Gifts (flag {@code FLOWERS_ENABLED}, off by default, ADR-026).
 * Allowed only in an explicit dev/local/test environment. The domain has no behaviour yet: the flag only reserves the switch.
 */
@Component
public class FlowersSettings implements FeatureGate {
    @Override
    public FeatureToggles.Feature feature() {
        return FeatureToggles.Feature.FLOWERS;
    }

    private final boolean allowed;

    public FlowersSettings(Environment environment) {
        boolean requested = environment.getProperty("app.flowers.enabled", Boolean.class, false);
        boolean internal = Set.of("local", "dev", "test").contains(environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        if (requested && !internal) {
            throw new IllegalStateException("Flowers requires an explicit dev/local/test environment");
        }
        this.allowed = requested;
    }

    @Override
    public boolean allowedByEnvironment() {
        return allowed;
    }
}
