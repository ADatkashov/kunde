package kz.kunde.booking;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

/** Startup validation: the booking pilot uses a DEV mock confirmation, so it is forbidden outside dev/local/test. */
public final class BookingGuard {
    private static final Set<String> NON_PRODUCTION = Set.of("dev", "local", "test");

    private BookingGuard() {}

    public static void validate(BookingProperties props, Environment env) {
        if (!props.enabled()) {
            if (props.seedDemo()) {
                throw new IllegalStateException("Booking demo seed requires app.booking.enabled=true");
            }
            return;
        }
        String environment = env.getProperty("app.environment", "production");
        if (!NON_PRODUCTION.contains(environment) || env.acceptsProfiles(Profiles.of("prod", "production"))) {
            throw new IllegalStateException(
                    "Service booking (DEV mock confirmation) is forbidden outside an explicit dev/local/test environment");
        }
        if (!"true".equals(env.getProperty("app.identity.consumer-enabled"))) {
            throw new IllegalStateException("Service booking requires app.identity.consumer-enabled=true");
        }
    }
}
