package kz.kunde.food;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class FoodGuardTest {
    private static FoodProperties props(boolean enabled, boolean seed) {
        return new FoodProperties(enabled, seed, new FoodProperties.Simulation(20, 45, 120, 240));
    }

    private static MockEnvironment env(String environment) {
        return new MockEnvironment().withProperty("app.environment", environment)
                .withProperty("app.identity.consumer-enabled", "true");
    }

    @Test
    void offByDefaultAndSeedNeedsFood() {
        assertThatCode(() -> FoodGuard.validate(props(false, false), env("production"))).doesNotThrowAnyException();
        assertThatThrownBy(() -> FoodGuard.validate(props(false, true), env("dev"))).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void foodIsForbiddenOutsideDevLocalTest() {
        assertThatThrownBy(() -> FoodGuard.validate(props(true, false), env("production"))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> FoodGuard.validate(props(true, false), env("staging"))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> FoodGuard.validate(props(true, true), env("dev").withProperty("spring.profiles.active", "prod")
                .withProperty("app.environment", "production"))).isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> FoodGuard.validate(props(true, true), env("dev"))).doesNotThrowAnyException();
    }

    @Test
    void foodNeedsConsumerIdentityAndSaneSimulation() {
        assertThatThrownBy(() -> FoodGuard.validate(props(true, false),
                new MockEnvironment().withProperty("app.environment", "dev"))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> FoodGuard.validate(new FoodProperties(true, false, new FoodProperties.Simulation(50, 40, 120, 240)),
                env("dev"))).isInstanceOf(IllegalStateException.class);
    }
}
