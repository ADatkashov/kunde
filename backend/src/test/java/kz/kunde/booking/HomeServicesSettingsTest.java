package kz.kunde.booking;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class HomeServicesSettingsTest {
    @Test
    void requiresExplicitOptInAndBookingCapability() {
        var environment = new MockEnvironment().withProperty("app.environment", "dev");
        assertThat(new HomeServicesSettings(environment).allowedByEnvironment()).isFalse();

        environment.setProperty("app.home-services.enabled", "true");
        assertThat(new HomeServicesSettings(environment).allowedByEnvironment()).isFalse();

        environment.setProperty("app.booking.enabled", "true");
        assertThat(new HomeServicesSettings(environment).allowedByEnvironment()).isTrue();
    }

    @Test
    void refusesOptInInProductionEvenIfEnvironmentSaysDev() {
        var environment = new MockEnvironment().withProperty("app.home-services.enabled", "true");
        assertThatThrownBy(() -> new HomeServicesSettings(environment)).isInstanceOf(IllegalStateException.class);

        environment.setProperty("app.environment", "dev");
        environment.setActiveProfiles("production");
        assertThatThrownBy(() -> new HomeServicesSettings(environment)).isInstanceOf(IllegalStateException.class);
    }
}
