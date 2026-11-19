package kz.kunde.auto;

import java.util.Set;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

@Configuration
@EnableConfigurationProperties(AutoProperties.class)
public class AutoConfiguration {
    private static final Set<String> NON_PRODUCTION = Set.of("dev", "local", "test");

    /** Runs on every start: Auto needs Booking and is forbidden outside an explicit dev/local/test environment. */
    @Bean
    AutoStartupCheck autoStartupCheck(AutoProperties props, Environment env) {
        validate(props, env);
        return new AutoStartupCheck();
    }

    static void validate(AutoProperties props, Environment env) {
        if (!props.enabled()) {
            if (props.seedDemo()) {
                throw new IllegalStateException("Auto demo seed requires app.auto.enabled=true");
            }
            return;
        }
        String environment = env.getProperty("app.environment", "production");
        if (!NON_PRODUCTION.contains(environment) || env.acceptsProfiles(Profiles.of("prod", "production"))) {
            throw new IllegalStateException("KUNDE Auto (DEV pilot) is forbidden outside an explicit dev/local/test environment");
        }
        if (!"true".equals(env.getProperty("app.booking.enabled"))) {
            throw new IllegalStateException("KUNDE Auto requires app.booking.enabled=true");
        }
    }

    public static final class AutoStartupCheck {}
}
