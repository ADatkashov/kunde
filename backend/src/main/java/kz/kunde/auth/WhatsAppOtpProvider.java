package kz.kunde.auth;

/** Production placeholder (D-11: no WhatsApp vendor approved). Not a bean; intentionally unusable. */
public final class WhatsAppOtpProvider implements OtpDeliveryProvider {
    @Override public boolean available() { return false; }
    @Override public String channel() { return "whatsapp"; }
    @Override public boolean canDeliver(String phoneE164) { return false; }
    @Override public void deliver(String phoneE164, String code) throws OtpDeliveryException {
        throw new OtpDeliveryException("WhatsApp provider is not connected");
    }
}
