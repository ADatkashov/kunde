package kz.kunde.booking;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class BeautySettingsTest {
    @Test
    void isOffByDefaultAndNeedsExplicitOptInAndBookingCapability() {
        var environment = new MockEnvironment().withProperty("app.environment", "dev");
        assertThat(new BeautySettings(environment).allowedByEnvironment()).isFalse();

        environment.setProperty("app.beauty.enabled", "true");
        assertThat(new BeautySettings(environment).allowedByEnvironment()).isFalse();

        environment.setProperty("app.booking.enabled", "true");
        assertThat(new BeautySettings(environment).allowedByEnvironment()).isTrue();
    }

    @Test
    void refusesOptInOutsideInternalEnvironments() {
        var environment = new MockEnvironment().withProperty("app.beauty.enabled", "true");
        assertThatThrownBy(() -> new BeautySettings(environment)).isInstanceOf(IllegalStateException.class);

        environment.setProperty("app.environment", "dev");
        environment.setActiveProfiles("production");
        assertThatThrownBy(() -> new BeautySettings(environment)).isInstanceOf(IllegalStateException.class);
    }
}
