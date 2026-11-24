package kz.kunde.auth;

import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

/** Startup validation. Any unsafe combination aborts the application instead of degrading. */
public final class PhoneAuthGuard {
    /** KUNDE convention for synthetic DEV numbers: +7 700 000 XXXX. Real subscriber numbers are rejected. */
    static final Pattern SYNTHETIC = Pattern.compile("^\\+7700000[0-9]{4}$");
    private static final Set<String> NON_PRODUCTION = Set.of("dev", "local", "test");
    static final int MIN_SECRET_LENGTH = 32;

    private PhoneAuthGuard() {}

    public static void validate(PhoneAuthProperties props, Environment env) {
        if (!props.enabled()) {
            if (props.devOtp().enabled()) {
                throw new IllegalStateException("DEV OTP requires app.auth.phone.enabled=true");
            }
            return;
        }
        if (props.secret() == null || props.secret().length() < MIN_SECRET_LENGTH) {
            throw new IllegalStateException("app.auth.phone.secret must be at least 32 characters");
        }
        if (!env.getProperty("app.security.oidc.issuer-uri", "").isBlank()) {
            throw new IllegalStateException("Phone authentication and an external OIDC issuer are mutually exclusive");
        }
        if (props.accessTtlSeconds() < 60 || props.accessTtlSeconds() > 3600 || props.otpTtlSeconds() < 60
                || props.otpTtlSeconds() > 900 || props.otpMaxAttempts() < 1 || props.otpMaxAttempts() > 10
                || props.refreshTtlDays() < 1 || props.sessionMaxDays() < props.refreshTtlDays()) {
            throw new IllegalStateException("Phone authentication lifetimes or limits are out of the allowed range");
        }
        if (props.devOtp().enabled()) {
            String environment = env.getProperty("app.environment", "production");
            if (!NON_PRODUCTION.contains(environment)
                    || env.acceptsProfiles(Profiles.of("prod", "production"))) {
                throw new IllegalStateException("DEV OTP is forbidden outside an explicit dev/local/test environment");
            }
            var phones = props.devOtp().allowedPhones();
            if (phones.isEmpty() || phones.size() > 20
                    || phones.stream().anyMatch(phone -> !SYNTHETIC.matcher(phone).matches())) {
                throw new IllegalStateException(
                        "DEV OTP needs a non-empty allowlist (max 20) of synthetic numbers +7700000XXXX");
            }
        }
    }
}
