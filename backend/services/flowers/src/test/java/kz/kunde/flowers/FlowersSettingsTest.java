package kz.kunde.flowers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import kz.kunde.platform.FeatureToggles;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class FlowersSettingsTest {
    @Test
    void isOffByDefault() {
        assertThat(new FlowersSettings(new MockEnvironment().withProperty("app.environment", "dev")).allowedByEnvironment()).isFalse();
    }

    @Test
    void canBeSwitchedOnInDevLocalAndTest() {
        for (String environment : new String[] {"local", "dev", "test"}) {
            var env = new MockEnvironment().withProperty("app.environment", environment).withProperty("app.flowers.enabled", "true");
            assertThat(new FlowersSettings(env).allowedByEnvironment()).as(environment).isTrue();
        }
    }

    @Test
    void refusesToStartEnabledOutsideInternalEnvironments() {
        var env = new MockEnvironment().withProperty("app.flowers.enabled", "true");
        assertThatThrownBy(() -> new FlowersSettings(env)).isInstanceOf(IllegalStateException.class).hasMessageContaining("Flowers");
        var prod = new MockEnvironment().withProperty("app.environment", "dev").withProperty("app.flowers.enabled", "true");
        prod.setActiveProfiles("prod");
        assertThatThrownBy(() -> new FlowersSettings(prod)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void ownsTheFlowersFeature() {
        assertThat(new FlowersSettings(new MockEnvironment()).feature()).isEqualTo(FeatureToggles.Feature.FLOWERS);
    }
}
