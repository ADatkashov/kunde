package kz.kunde.auto;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class AutoConfigurationTest {
    private static MockEnvironment env(String environment, boolean booking) {
        return new MockEnvironment().withProperty("app.environment", environment).withProperty("app.booking.enabled", String.valueOf(booking));
    }

    @Test
    void offIsAlwaysValidButSeedWithoutFlagIsRejected() {
        assertThatCode(() -> AutoConfiguration.validate(new AutoProperties(false, false), env("production", false))).doesNotThrowAnyException();
        assertThatThrownBy(() -> AutoConfiguration.validate(new AutoProperties(false, true), env("dev", true))).hasMessageContaining("seed");
    }

    @Test
    void enabledNeedsBookingAndANonProductionEnvironment() {
        assertThatCode(() -> AutoConfiguration.validate(new AutoProperties(true, true), env("dev", true))).doesNotThrowAnyException();
        assertThatThrownBy(() -> AutoConfiguration.validate(new AutoProperties(true, false), env("production", true))).hasMessageContaining("forbidden");
        assertThatThrownBy(() -> AutoConfiguration.validate(new AutoProperties(true, false), env("dev", false))).hasMessageContaining("booking");
    }
}
