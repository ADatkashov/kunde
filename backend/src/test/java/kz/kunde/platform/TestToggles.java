package kz.kunde.platform;

import static org.mockito.Mockito.mock;

import java.math.BigDecimal;
import kz.kunde.auto.AutoProperties;
import kz.kunde.delivery.DeliveryProperties;
import kz.kunde.rides.RidesFlags;
import org.springframework.jdbc.core.JdbcTemplate;

/** Unit-test feature switches that follow the given environment flags (no stored switches). */
public final class TestToggles {
    private TestToggles() {}

    public static FeatureToggles of(RidesFlags rides) {
        return new FeatureToggles(mock(JdbcTemplate.class), new AutoProperties(false, false), rides, new DeliveryProperties(false, false, false, false, false, false, false, 300, 1000, 50, "test",
                BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO), new kz.kunde.health.HealthSettings(new org.springframework.mock.env.MockEnvironment()));
    }
}
