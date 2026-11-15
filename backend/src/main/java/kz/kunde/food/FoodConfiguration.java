package kz.kunde.food;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

@Configuration
@EnableConfigurationProperties(FoodProperties.class)
public class FoodConfiguration {
    /** Runs on every start, including when Food is off, so unsafe flag combinations abort startup. */
    @Bean
    FoodStartupCheck foodStartupCheck(FoodProperties props, Environment env) {
        FoodGuard.validate(props, env);
        return new FoodStartupCheck();
    }

    public static final class FoodStartupCheck {}
}
