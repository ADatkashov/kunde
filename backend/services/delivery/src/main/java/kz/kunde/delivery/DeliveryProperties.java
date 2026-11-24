package kz.kunde.delivery;

import kz.kunde.platform.FeatureGate;
import kz.kunde.platform.FeatureToggles;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties("app.delivery")
public record DeliveryProperties(boolean enabled, boolean consumerEnabled, boolean paymentsEnabled,
        boolean syntheticRoutingEnabled, boolean executorEnabled, boolean dispatchEnabled, boolean partnerEnabled, @Min(1) @Max(3600) int quoteLifetimeSeconds,
        @Min(1) @Max(50000) int maxWeightGrams, @Min(1) @Max(200) int maxSideCm,
        @NotBlank @Size(max = 64) String tariffVersion,
        @NotNull @DecimalMin("0") BigDecimal baseKzt,
        @NotNull @DecimalMin("0") BigDecimal perKmKzt,
        @NotNull @DecimalMin("0") BigDecimal perKgKzt,
        @NotNull @DecimalMin("0") BigDecimal minimumKzt) implements FeatureGate {
    @Override
    public FeatureToggles.Feature feature() {
        return FeatureToggles.Feature.DELIVERY;
    }

    @Override
    public boolean allowedByEnvironment() {
        return enabled();
    }


    /** A copy with the master switch replaced (used by the runtime feature switches). */
    public DeliveryProperties withEnabled(boolean master) {
        return new DeliveryProperties(master, consumerEnabled, paymentsEnabled, syntheticRoutingEnabled, executorEnabled, dispatchEnabled,
                partnerEnabled, quoteLifetimeSeconds, maxWeightGrams, maxSideCm, tariffVersion, baseKzt, perKmKzt, perKgKzt, minimumKzt);
    }

    /** The live view (master switch from the runtime feature switches applied). */
    public static DeliveryProperties live(kz.kunde.platform.FeatureToggles toggles) {
        return toggles.live(kz.kunde.platform.FeatureToggles.Feature.DELIVERY, DeliveryProperties.class);
    }

    @Override
    public java.util.Map<String, Boolean> capabilities() {
        return java.util.Map.of("consumer", consumerAvailable(), "partner", enabled && partnerEnabled,
                "syntheticRouting", enabled && syntheticRoutingEnabled, "executor", enabled && executorEnabled);
    }

    public boolean dispatchAvailable() {
        return enabled && executorEnabled && dispatchEnabled;
    }

    public boolean consumerAvailable() {
        return enabled && consumerEnabled;
    }
}
