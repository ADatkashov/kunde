package kz.kunde.platform;

import static org.mockito.Mockito.mock;

import java.math.BigDecimal;
import kz.kunde.auto.AutoProperties;
import kz.kunde.delivery.DeliveryProperties;
import kz.kunde.leisure.LeisureFlags;
import kz.kunde.leisure.LeisureProperties;
import kz.kunde.rides.RidesFlags;
import org.springframework.jdbc.core.JdbcTemplate;

/** Unit-test feature switches that follow the given environment flags (no stored switches). */
public final class TestToggles {
    private TestToggles() {}

    public static FeatureToggles of(RidesFlags rides) {
        var env = new org.springframework.mock.env.MockEnvironment();
        var delivery = new DeliveryProperties(false, false, false, false, false, false, false, 300, 1000, 50, "test",
                BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO);
        return new FeatureToggles(mock(JdbcTemplate.class), java.util.List.of(new AutoProperties(false, false), rides, delivery,
                new LeisureFlags(new LeisureProperties(false, false), new org.springframework.mock.env.MockEnvironment().withProperty("app.environment", "test")),
                new kz.kunde.health.HealthSettings(env),
                new kz.kunde.education.EducationSettings(env),
                new kz.kunde.groceries.GroceriesSettings(env),
                new kz.kunde.events.EventsSettings(env),
                new kz.kunde.booking.HomeServicesSettings(env),
                new kz.kunde.booking.BeautySettings(env)));
    }
}
