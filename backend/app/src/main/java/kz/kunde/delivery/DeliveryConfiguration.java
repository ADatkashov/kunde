package kz.kunde.delivery;

import java.util.Set;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

@Configuration
@EnableConfigurationProperties(DeliveryProperties.class)
class DeliveryConfiguration {
    DeliveryConfiguration(DeliveryProperties properties, Environment environment) {
        if (properties.paymentsEnabled()) {
            throw new IllegalStateException("Delivery payments require an approved integration");
        }
        if (properties.enabled() && (!Set.of("dev", "local", "test").contains(
                environment.getProperty("app.environment", "production"))
                || environment.acceptsProfiles(Profiles.of("prod", "production"))
                || !environment.getProperty("app.identity.consumer-enabled", Boolean.class, false))) {
            throw new IllegalStateException("Delivery requires internal environment and consumer identity");
        }
    }
}
