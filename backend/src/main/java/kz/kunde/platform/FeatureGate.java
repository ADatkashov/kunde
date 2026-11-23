package kz.kunde.platform;

/**
 * Environment ceiling of one product, implemented by the product's own module. {@link FeatureToggles} collects all gates,
 * so the platform kernel does not depend on any domain's settings class (microservice-readiness V1).
 */
public interface FeatureGate {
    FeatureToggles.Feature feature();

    /** Whether the environment (profile and flags) allows the feature at all, before the administrator switch. */
    boolean allowedByEnvironment();
}
