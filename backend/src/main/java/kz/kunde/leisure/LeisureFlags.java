package kz.kunde.leisure;

import kz.kunde.platform.FeatureGate;
import kz.kunde.platform.FeatureToggles;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/** Environment ceiling of Leisure: the value an administrator can only switch off (and back on) at runtime. */
@Component
public class LeisureFlags implements FeatureGate {
    @Override
    public FeatureToggles.Feature feature() {
        return FeatureToggles.Feature.LEISURE;
    }

    private static final Set<String> NON_PRODUCTION = Set.of("dev", "local", "test");
    private final boolean allowed;
    private final boolean testPayments;

    public LeisureFlags(LeisureProperties props, Environment env) {
        String environment = env.getProperty("app.environment", "production");
        boolean nonProduction = NON_PRODUCTION.contains(environment) && !env.acceptsProfiles(Profiles.of("prod", "production"));
        if (Boolean.TRUE.equals(props.enabled()) && !nonProduction) {
            throw new IllegalStateException("KUNDE Leisure is forbidden outside an explicit dev/local/test environment");
        }
        if (props.seedDemo() && !nonProduction) {
            throw new IllegalStateException("The Leisure demo seed is forbidden outside an explicit dev/local/test environment");
        }
        this.allowed = props.enabled() == null ? nonProduction : props.enabled();
        this.testPayments = nonProduction;
        if (props.seedDemo() && !allowed) {
            throw new IllegalStateException("The Leisure demo seed requires Leisure to be enabled");
        }
    }

    /** Whether the environment allows Leisure at all (before the administrator switch). */
    @Override
    public boolean allowedByEnvironment() { return allowed; }

    /** Test payments (TEST_CARD) exist only outside production. */
    public boolean testPaymentsAllowed() { return testPayments; }
}
