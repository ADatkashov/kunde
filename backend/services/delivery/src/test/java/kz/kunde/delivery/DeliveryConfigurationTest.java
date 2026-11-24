package kz.kunde.delivery;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class DeliveryConfigurationTest {
    @Test
    void rejectsProductionEvenWhenEnvironmentPropertyClaimsTest() {
        var enabled = settings(true, false);
        assertThatIllegalStateException().isThrownBy(() -> new DeliveryConfiguration(enabled, new MockEnvironment()));
        var test = new MockEnvironment().withProperty("app.environment", "test")
                .withProperty("app.identity.consumer-enabled", "true");
        assertThatCode(() -> new DeliveryConfiguration(enabled, test)).doesNotThrowAnyException();

        test.setActiveProfiles("production");
        assertThatIllegalStateException().isThrownBy(() -> new DeliveryConfiguration(enabled, test));
    }

    @Test
    void rejectsPaymentActivationAndKeepsIntakeDisabledByTheMasterFlag() {
        assertThat(settings(false, false).consumerAvailable()).isFalse();
        assertThatIllegalStateException().isThrownBy(() ->
                new DeliveryConfiguration(settings(false, true), new MockEnvironment()));
    }

    private static DeliveryProperties settings(boolean enabled, boolean paymentsEnabled) {
        return new DeliveryProperties(enabled, true, paymentsEnabled, false, false, false, false, 300, 5000, 50,
                "test-v1", BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO);
    }
}
