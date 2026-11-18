package kz.kunde.rides;

import java.util.Set;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

@Configuration
@EnableConfigurationProperties({RidesFlags.class, RidePricingProperties.class})
public class RidesConfiguration {
    private static final Set<String> INTERNAL_ENVIRONMENTS = Set.of("dev", "local", "test");

    public RidesConfiguration(RidesFlags flags, Environment environment) {
        if (flags.paymentsEnabled()) {
            throw new IllegalStateException("Rides payments require an approved integration");
        }
        if (!flags.enabled()) {
            return;
        }
        if (!INTERNAL_ENVIRONMENTS.contains(environment.getProperty("app.environment", "production"))
                || environment.acceptsProfiles(Profiles.of("prod", "production"))) {
            throw new IllegalStateException("Rides can only be enabled in an internal environment");
        }
        if (!environment.getProperty("app.identity.consumer-enabled", Boolean.class, false)) {
            throw new IllegalStateException("Rides requires canonical consumer identity");
        }
    }
}
