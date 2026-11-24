package kz.kunde.rides;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

public record RideTariff(
        String version, BigDecimal baseKzt, BigDecimal perKilometerKzt,
        BigDecimal perMinuteKzt, BigDecimal minimumKzt, BigDecimal fixedFeeKzt) {

    public RideTariff {
        if (version == null || version.isBlank()) {
            throw new IllegalArgumentException("Tariff version is required");
        }
        for (BigDecimal amount : new BigDecimal[] {baseKzt, perKilometerKzt, perMinuteKzt, minimumKzt, fixedFeeKzt}) {
            if (Objects.requireNonNull(amount).signum() < 0) {
                throw new IllegalArgumentException("Tariff amounts must be nonnegative");
            }
        }
    }

    public BigDecimal estimateKzt(int meters, int seconds) {
        if (meters <= 0 || seconds <= 0) {
            throw new IllegalArgumentException("Route distance and duration must be positive");
        }
        // Use a common denominator so time conversion is rounded only with the final KZT amount.
        BigDecimal denominator = BigDecimal.valueOf(3000);
        BigDecimal total = baseKzt.add(fixedFeeKzt).multiply(denominator)
                .add(perKilometerKzt.multiply(BigDecimal.valueOf(3L * meters)))
                .add(perMinuteKzt.multiply(BigDecimal.valueOf(50L * seconds)));
        return total.max(minimumKzt.multiply(denominator)).divide(denominator, 2, RoundingMode.HALF_UP);
    }
}
