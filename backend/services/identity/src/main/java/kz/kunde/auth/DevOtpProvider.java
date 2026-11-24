package kz.kunde.auth;

import java.util.Optional;
import java.util.Set;

/**
 * DEV only. Accepts the fixed code for allowlisted synthetic numbers and delivers nothing. Never a
 * Spring bean unless {@link PhoneAuthConfiguration} passed {@link PhoneAuthGuard}.
 */
public final class DevOtpProvider implements OtpDeliveryProvider {
    public static final String TEST_CODE = "123456";
    private final Set<String> allowed;

    public DevOtpProvider(Set<String> allowedSyntheticPhones) {
        this.allowed = Set.copyOf(allowedSyntheticPhones);
    }

    @Override public boolean available() { return true; }
    @Override public String channel() { return "dev"; }
    @Override public Optional<String> fixedCode(String phoneE164) {
        return allowed.contains(phoneE164) ? Optional.of(TEST_CODE) : Optional.empty();
    }
    @Override public boolean canDeliver(String phoneE164) { return false; }
    @Override public void deliver(String phoneE164, String code) { /* nothing is sent in DEV */ }
}
