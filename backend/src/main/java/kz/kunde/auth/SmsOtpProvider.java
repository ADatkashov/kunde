package kz.kunde.auth;

/** Production placeholder (TASK/D-11: no SMS vendor approved). Not a bean; intentionally unusable. */
public final class SmsOtpProvider implements OtpDeliveryProvider {
    @Override public boolean available() { return false; }
    @Override public String channel() { return "sms"; }
    @Override public boolean canDeliver(String phoneE164) { return false; }
    @Override public void deliver(String phoneE164, String code) throws OtpDeliveryException {
        throw new OtpDeliveryException("SMS provider is not connected");
    }
}
