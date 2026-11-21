package kz.kunde.events;

import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Environment ceiling of Events & Tickets. Events share the ticketing engine of {@code kz.kunde.leisure}; this only decides whether the product is
 * offered: on by default in local/dev/test, never in production, and an explicit {@code EVENTS_ENABLED=true} outside those is refused.
 */
@Component
public class EventsSettings {
    private final boolean allowed;

    public EventsSettings(Environment environment) {
        boolean internal = Set.of("local", "dev", "test").contains(environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        Boolean explicit = environment.getProperty("app.events.enabled", Boolean.class);
        if (Boolean.TRUE.equals(explicit) && !internal) {
            throw new IllegalStateException("KUNDE Events is forbidden outside an explicit dev/local/test environment");
        }
        this.allowed = internal && (explicit == null || explicit);
    }

    public boolean allowedByEnvironment() { return allowed; }
}
