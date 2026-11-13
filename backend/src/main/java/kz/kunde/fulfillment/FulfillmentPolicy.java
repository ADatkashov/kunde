package kz.kunde.fulfillment;

import java.util.EnumSet;
import java.util.Set;

/**
 * Per-method enablement (D-02). Contract only: not read from configuration, persisted or exposed over HTTP yet.
 * Methods are independently configurable, but a method this build does not support can never be enabled, and the
 * default enables nothing. Enabling pickup here does not make any offering orderable (ADR-014 gates stay closed).
 */
public final class FulfillmentPolicy {
    private final Set<FulfillmentMethod> enabled;

    private FulfillmentPolicy(Set<FulfillmentMethod> enabled) { this.enabled = Set.copyOf(enabled); }

    /** Everything disabled: the safe default. */
    public static FulfillmentPolicy disabled() { return new FulfillmentPolicy(Set.of()); }

    /** @throws IllegalArgumentException when a requested method is not supported by this build */
    public static FulfillmentPolicy of(Set<FulfillmentMethod> requested) {
        var methods = EnumSet.noneOf(FulfillmentMethod.class);
        for (var method : requested) {
            if (!method.supported()) {
                throw new IllegalArgumentException(method + " is not supported and cannot be enabled");
            }
            methods.add(method);
        }
        return new FulfillmentPolicy(methods);
    }

    public boolean isEnabled(FulfillmentMethod method) { return enabled.contains(method); }

    public Set<FulfillmentMethod> enabledMethods() { return enabled; }
}
