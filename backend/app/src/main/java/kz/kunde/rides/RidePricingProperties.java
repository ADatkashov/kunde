package kz.kunde.rides;

import java.util.Map;
import kz.kunde.rides.RideMatching.RideClass;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("app.rides.pricing")
public record RidePricingProperties(Map<RideClass, RideTariff> tariffs, Integer quoteLifetimeSeconds) {
    public RidePricingProperties {
        tariffs = tariffs == null ? Map.of() : Map.copyOf(tariffs);
        quoteLifetimeSeconds = quoteLifetimeSeconds == null ? 120 : quoteLifetimeSeconds;
        if (quoteLifetimeSeconds < 15 || quoteLifetimeSeconds > 900) {
            throw new IllegalArgumentException("Rides quote lifetime must be 15 to 900 seconds");
        }
        if (tariffs.values().stream().anyMatch(tariff -> tariff.version().length() > 64)) {
            throw new IllegalArgumentException("Rides tariff version must be at most 64 characters");
        }
    }
}
