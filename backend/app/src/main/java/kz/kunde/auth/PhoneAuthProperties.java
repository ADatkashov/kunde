package kz.kunde.auth;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Phone OTP authentication settings (ADR-015, amended 2026-11-14). Everything is off by default;
 * {@link PhoneAuthGuard} validates the combination at startup and fails closed.
 */
@ConfigurationProperties("app.auth.phone")
public record PhoneAuthProperties(
        @DefaultValue("false") boolean enabled,
        @DefaultValue("") String secret,
        @DefaultValue("kunde-phone-auth") String issuer,
        @DefaultValue("kunde-api") String audience,
        @DefaultValue("kunde-consumer") String clientId,
        @DefaultValue("900") int accessTtlSeconds,
        @DefaultValue("30") int refreshTtlDays,
        @DefaultValue("90") int sessionMaxDays,
        @DefaultValue("300") int otpTtlSeconds,
        @DefaultValue("5") int otpMaxAttempts,
        @DefaultValue("30") int otpCooldownSeconds,
        @DefaultValue("3") int otpMaxPerWindow,
        @DefaultValue("600") int otpWindowSeconds,
        @DefaultValue("10") int otpMaxPerDay,
        @DefaultValue DevOtp devOtp) {

    public record DevOtp(@DefaultValue("false") boolean enabled, @DefaultValue List<String> allowedPhones) {
        public DevOtp {
            allowedPhones = allowedPhones == null ? List.of() : List.copyOf(allowedPhones);
        }
    }
}
