package kz.kunde.rides;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.ConstructorBinding;

@ConfigurationProperties("app.rides")
public record RidesFlags(boolean enabled, boolean consumerEnabled, boolean executorEnabled,
        boolean partnerEnabled, boolean dispatchEnabled, boolean paymentsEnabled, boolean syntheticRoutingEnabled) {

    @ConstructorBinding
    public RidesFlags {}

    public RidesFlags(boolean enabled, boolean consumerEnabled, boolean executorEnabled,
            boolean partnerEnabled, boolean dispatchEnabled, boolean paymentsEnabled) {
        this(enabled, consumerEnabled, executorEnabled, partnerEnabled, dispatchEnabled, paymentsEnabled, false);
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
