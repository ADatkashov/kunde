package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class RidesConfigurationTest {
    @Test
    void rejectsSyntheticRoutingOutsideExplicitInternalRides() {
        var environment = new MockEnvironment();
        var disabled = new RidesFlags(false, false, false, false, false, false, true);
        var enabled = new RidesFlags(true, true, false, false, false, false, true);
        assertThatIllegalStateException().isThrownBy(() -> new RidesConfiguration(disabled, environment));
        assertThatIllegalStateException().isThrownBy(() -> new RidesConfiguration(enabled, environment));
    }

    @Test
    void blocksProdAndConflictingProductionProfile() {
        var flags = new RidesFlags(true, true, false, false, false, false);
        assertThatIllegalStateException().isThrownBy(() -> new RidesConfiguration(flags, new MockEnvironment()));

        var production = new MockEnvironment().withProperty("app.environment", "dev")
                .withProperty("app.identity.consumer-enabled", "true");
        production.setActiveProfiles("production");
        assertThatIllegalStateException().isThrownBy(() -> new RidesConfiguration(flags, production));
    }

    @Test
    void allowsOnlyInternalRidesWithExistingIdentityAndWithoutPayments() {
        var internal = new MockEnvironment().withProperty("app.environment", "test");
        var rides = new RidesFlags(true, true, false, false, false, false);
        assertThatIllegalStateException().isThrownBy(() -> new RidesConfiguration(rides, internal));

        internal.setProperty("app.identity.consumer-enabled", "true");
        assertThatCode(() -> new RidesConfiguration(rides, internal)).doesNotThrowAnyException();

        var payment = new RidesFlags(false, false, false, false, false, true);
        assertThatIllegalStateException().isThrownBy(() -> new RidesConfiguration(payment, internal));
    }
}
