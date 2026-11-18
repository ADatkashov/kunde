package kz.kunde.rides;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("app.rides")
public record RidesFlags(boolean enabled, boolean consumerEnabled, boolean executorEnabled,
        boolean partnerEnabled, boolean dispatchEnabled, boolean paymentsEnabled) {

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
