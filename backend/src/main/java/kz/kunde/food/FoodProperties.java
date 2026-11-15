package kz.kunde.food;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * KUNDE Food (DEV pilot). Off by default. {@code seedDemo} loads clearly synthetic demo restaurants and is
 * only allowed in a dev/local/test environment (see {@link FoodGuard}). The simulator thresholds drive the
 * explicit DEV mock fulfillment: seconds since the order was placed at which each status is reached.
 */
@ConfigurationProperties("app.food")
public record FoodProperties(
        @DefaultValue("false") boolean enabled,
        @DefaultValue("false") boolean seedDemo,
        @DefaultValue Simulation simulation) {

    public record Simulation(
            @DefaultValue("20") int acceptedAfterSeconds,
            @DefaultValue("45") int preparingAfterSeconds,
            @DefaultValue("120") int onTheWayAfterSeconds,
            @DefaultValue("240") int deliveredAfterSeconds) {}
}
