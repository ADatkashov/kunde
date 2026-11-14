package kz.kunde.auth;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class PhoneAuthGuardTest {
    private static final String SECRET = "synthetic-test-secret-0123456789abcdef";

    private static PhoneAuthProperties props(boolean enabled, String secret, boolean dev, List<String> phones) {
        return new PhoneAuthProperties(enabled, secret, "kunde-phone-auth", "kunde-api", "kunde-consumer", 900, 30, 90,
                300, 5, 30, 3, 600, 10, new PhoneAuthProperties.DevOtp(dev, phones));
    }

    private static MockEnvironment env(String environment) {
        return new MockEnvironment().withProperty("app.environment", environment);
    }

    @Test
    void disabledFeatureNeedsNothing() {
        assertThatCode(() -> PhoneAuthGuard.validate(props(false, "", false, List.of()), env("production")))
                .doesNotThrowAnyException();
    }

    @Test
    void devOtpWithoutFeatureFlagIsRejected() {
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(false, "", true, List.of("+77000000001")), env("dev")))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void devOtpIsForbiddenInProductionEnvironment() {
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of("+77000000001")), env("production")))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("forbidden");
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of("+77000000001")), env("staging")))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void devOtpIsForbiddenWithProductionProfileEvenIfEnvironmentSaysDev() {
        MockEnvironment withProfile = env("dev");
        withProfile.setActiveProfiles("production");
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of("+77000000001")), withProfile))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("forbidden");
    }

    @Test
    void environmentDefaultsToProductionWhenUnset() {
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of("+77000000001")), new MockEnvironment()))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void devOtpRequiresSyntheticAllowlist() {
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of()), env("dev")))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of("+77771234567")), env("dev")))
                .as("a plausible real subscriber number is not synthetic").isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> PhoneAuthGuard.validate(props(true, SECRET, true, List.of("+77000000001")), env("dev")))
                .doesNotThrowAnyException();
    }

    @Test
    void secretMustBeStrongAndOidcMustBeAbsent() {
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, "short", false, List.of()), env("production")))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("secret");
        assertThatThrownBy(() -> PhoneAuthGuard.validate(props(true, SECRET, false, List.of()),
                env("production").withProperty("app.security.oidc.issuer-uri", "https://idp.example.test")))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("mutually exclusive");
        assertThatCode(() -> PhoneAuthGuard.validate(props(true, SECRET, false, List.of()), env("production")))
                .as("real OTP mode without a DEV provider is allowed (fails closed at request time)")
                .doesNotThrowAnyException();
    }
}
