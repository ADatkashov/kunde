package kz.kunde.auto;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** KUNDE Auto DEV pilot. Off by default. When off, no NEW booking or quote is accepted; existing bookings can still be completed or cancelled. */
@ConfigurationProperties("app.auto")
public record AutoProperties(
        @DefaultValue("false") boolean enabled,
        @DefaultValue("false") boolean seedDemo) {}
