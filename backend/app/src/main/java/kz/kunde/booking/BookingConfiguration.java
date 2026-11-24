package kz.kunde.booking;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

@Configuration
@EnableConfigurationProperties(BookingProperties.class)
public class BookingConfiguration {
    /** Runs on every start, including when booking is off, so unsafe flag combinations abort startup. */
    @Bean
    BookingStartupCheck bookingStartupCheck(BookingProperties props, Environment env) {
        BookingGuard.validate(props, env);
        return new BookingStartupCheck();
    }

    public static final class BookingStartupCheck {}
}
