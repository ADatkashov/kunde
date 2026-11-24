package kz.kunde.booking;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class BookingGuardTest {
    private static MockEnvironment env(String environment) {
        return new MockEnvironment().withProperty("app.environment", environment)
                .withProperty("app.identity.consumer-enabled", "true");
    }

    @Test
    void offByDefaultAndSeedNeedsBooking() {
        assertThatCode(() -> BookingGuard.validate(new BookingProperties(false, false), env("production"))).doesNotThrowAnyException();
        assertThatThrownBy(() -> BookingGuard.validate(new BookingProperties(false, true), env("dev"))).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void bookingIsForbiddenOutsideDevLocalTestAndNeedsConsumerIdentity() {
        assertThatThrownBy(() -> BookingGuard.validate(new BookingProperties(true, false), env("production"))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> BookingGuard.validate(new BookingProperties(true, true), env("staging"))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> BookingGuard.validate(new BookingProperties(true, false),
                new MockEnvironment().withProperty("app.environment", "dev"))).isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> BookingGuard.validate(new BookingProperties(true, true), env("dev"))).doesNotThrowAnyException();
    }
}
