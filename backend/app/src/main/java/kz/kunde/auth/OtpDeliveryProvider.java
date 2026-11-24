package kz.kunde.auth;

import java.util.Optional;

/**
 * Port for delivering one-time codes. {@link SmsOtpProvider} and {@link WhatsAppOtpProvider} are
 * placeholders for production; the authentication service depends only on this interface.
 */
public interface OtpDeliveryProvider {
    /** Whether the provider can currently send codes at all. When false OTP requests fail with 503. */
    boolean available();

    /** Channel name for audit/metrics, never user data. */
    String channel();

    /** A fixed code for the number (DEV synthetic numbers only); real providers return empty. */
    default Optional<String> fixedCode(String phoneE164) {
        return Optional.empty();
    }

    /** Whether delivery to this number should be attempted. A false value must look identical to callers. */
    boolean canDeliver(String phoneE164);

    /** Must never log or persist the code or the phone number. */
    void deliver(String phoneE164, String code) throws OtpDeliveryException;

    class OtpDeliveryException extends Exception {
        public OtpDeliveryException(String message) {
            super(message);
        }
    }
}
