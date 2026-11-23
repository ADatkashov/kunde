package kz.kunde.auto;

import kz.kunde.platform.FeatureGate;
import kz.kunde.platform.FeatureToggles;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** KUNDE Auto DEV pilot. Off by default. When off, no NEW booking or quote is accepted; existing bookings can still be completed or cancelled. */
@ConfigurationProperties("app.auto")
public record AutoProperties(
        @DefaultValue("false") boolean enabled,
        @DefaultValue("false") boolean seedDemo) implements FeatureGate {
    @Override
    public FeatureToggles.Feature feature() {
        return FeatureToggles.Feature.AUTO;
    }

    @Override
    public boolean allowedByEnvironment() {
        return enabled();
    }
}
