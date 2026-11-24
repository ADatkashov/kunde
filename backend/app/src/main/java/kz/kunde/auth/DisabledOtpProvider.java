package kz.kunde.auth;

/** Fail-closed default: no delivery channel is connected, so OTP requests are refused with 503. */
public final class DisabledOtpProvider implements OtpDeliveryProvider {
    @Override public boolean available() { return false; }
    @Override public String channel() { return "none"; }
    @Override public boolean canDeliver(String phoneE164) { return false; }
    @Override public void deliver(String phoneE164, String code) throws OtpDeliveryException {
        throw new OtpDeliveryException("No OTP delivery channel is connected");
    }
}
