package kz.kunde.groceries;

import kz.kunde.platform.FeatureGate;
import kz.kunde.platform.FeatureToggles;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Environment ceiling of KUNDE Groceries (the value an administrator can only switch off and on again at runtime).
 * {@code app.groceries.enabled} left empty follows the environment: on in local/dev/test when Food is on, off elsewhere.
 * Stores, products and orders live in the Food tables, so Groceries cannot be allowed without Food. Explicitly enabling
 * it outside local/dev/test aborts startup (same rule as Food).
 */
@Component
public class GroceriesSettings implements FeatureGate {
    @Override
    public FeatureToggles.Feature feature() {
        return FeatureToggles.Feature.GROCERIES;
    }

    private static final Set<String> NON_PRODUCTION = Set.of("dev", "local", "test");
    private final boolean allowed;

    public GroceriesSettings(Environment env) {
        boolean internal = NON_PRODUCTION.contains(env.getProperty("app.environment", "production"))
                && !env.acceptsProfiles(Profiles.of("prod", "production"));
        boolean food = env.getProperty("app.food.enabled", Boolean.class, false);
        Boolean requested = env.getProperty("app.groceries.enabled", Boolean.class);
        if (Boolean.TRUE.equals(requested) && !internal) {
            throw new IllegalStateException("KUNDE Groceries is forbidden outside an explicit dev/local/test environment");
        }
        if (Boolean.TRUE.equals(requested) && !food) {
            throw new IllegalStateException("KUNDE Groceries requires app.food.enabled=true");
        }
        this.allowed = (requested == null ? internal : requested) && food;
    }

    @Override

    public boolean allowedByEnvironment() { return allowed; }
}
