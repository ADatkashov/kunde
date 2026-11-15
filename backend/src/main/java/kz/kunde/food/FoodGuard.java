package kz.kunde.food;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

/** Startup validation: Food with mock payment/fulfillment is a DEV pilot only; unsafe combinations abort startup. */
public final class FoodGuard {
    private static final Set<String> NON_PRODUCTION = Set.of("dev", "local", "test");

    private FoodGuard() {}

    public static void validate(FoodProperties props, Environment env) {
        if (!props.enabled()) {
            if (props.seedDemo()) {
                throw new IllegalStateException("Demo seed requires app.food.enabled=true");
            }
            return;
        }
        String environment = env.getProperty("app.environment", "production");
        if (!NON_PRODUCTION.contains(environment) || env.acceptsProfiles(Profiles.of("prod", "production"))) {
            throw new IllegalStateException(
                    "KUNDE Food (mock payment and simulated delivery) is forbidden outside an explicit dev/local/test environment");
        }
        if (!"true".equals(env.getProperty("app.identity.consumer-enabled"))) {
            throw new IllegalStateException("KUNDE Food requires app.identity.consumer-enabled=true");
        }
        var sim = props.simulation();
        if (sim.acceptedAfterSeconds() < 1 || sim.preparingAfterSeconds() < sim.acceptedAfterSeconds()
                || sim.onTheWayAfterSeconds() < sim.preparingAfterSeconds()
                || sim.deliveredAfterSeconds() < sim.onTheWayAfterSeconds()) {
            throw new IllegalStateException("Food simulation thresholds must be positive and non-decreasing");
        }
    }
}
