package kz.kunde.platform.geo;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

/** API coordinates (same JSON as before the move out of the Rides controller): latitude/longitude as decimals. */
public record Coordinates(
        @NotNull @DecimalMin("-90") @DecimalMax("90") BigDecimal latitude,
        @NotNull @DecimalMin("-180") @DecimalMax("180") BigDecimal longitude) {
    public Point point() {
        return new Point(latitude.doubleValue(), longitude.doubleValue());
    }
}
