package kz.kunde.rides;

import kz.kunde.platform.FeatureGate;
import kz.kunde.platform.FeatureToggles;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.ConstructorBinding;

@ConfigurationProperties("app.rides")
public record RidesFlags(boolean enabled, boolean consumerEnabled, boolean executorEnabled,
        boolean partnerEnabled, boolean dispatchEnabled, boolean paymentsEnabled, boolean syntheticRoutingEnabled) implements FeatureGate {
    @Override
    public FeatureToggles.Feature feature() {
        return FeatureToggles.Feature.RIDES;
    }

    @Override
    public boolean allowedByEnvironment() {
        return enabled();
    }


    @ConstructorBinding
    public RidesFlags {}

    public RidesFlags(boolean enabled, boolean consumerEnabled, boolean executorEnabled,
            boolean partnerEnabled, boolean dispatchEnabled, boolean paymentsEnabled) {
        this(enabled, consumerEnabled, executorEnabled, partnerEnabled, dispatchEnabled, paymentsEnabled, false);
    }

    /** A copy with the master switch replaced (used by the runtime feature switches). */
    public RidesFlags withEnabled(boolean master) {
        return new RidesFlags(master, consumerEnabled, executorEnabled, partnerEnabled, dispatchEnabled, paymentsEnabled,
                syntheticRoutingEnabled);
    }

    public boolean consumerAvailable() {
        return enabled && consumerEnabled;
    }

    public boolean executorAvailable() {
        return enabled && executorEnabled;
    }

    public boolean partnerAvailable() {
        return enabled && partnerEnabled;
    }

    public boolean dispatchAvailable() {
        return enabled && dispatchEnabled && executorEnabled;
    }
}
