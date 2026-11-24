package kz.kunde.booking;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Service booking (barbershops) DEV pilot. Off by default; the demo seed is allowed only in dev/local/test. */
@ConfigurationProperties("app.booking")
public record BookingProperties(
        @DefaultValue("false") boolean enabled,
        @DefaultValue("false") boolean seedDemo) {}
