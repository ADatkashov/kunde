package kz.kunde.auth;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Domain-separated subkeys derived from the single configured secret. Never logged. */
public final class AuthKeys {
    private final byte[] jwt;
    private final byte[] otp;
    private final byte[] refresh;
    private final byte[] phone;

    public AuthKeys(String secret) {
        byte[] root = secret.getBytes(StandardCharsets.UTF_8);
        this.jwt = hmac(root, "kunde/jwt/v1");
        this.otp = hmac(root, "kunde/otp/v1");
        this.refresh = hmac(root, "kunde/refresh/v1");
        this.phone = hmac(root, "kunde/phone-audit/v1");
    }

    public byte[] jwtKey() { return jwt.clone(); }
    public String otpHash(String phone, Object challengeId, String code) {
        return hex(hmac(otp, phone + "|" + challengeId + "|" + code));
    }
    public String refreshHash(String token) { return hex(hmac(refresh, token)); }
    public String phoneHash(String phoneE164) { return hex(hmac(phone, phoneE164)); }

    static byte[] hmac(byte[] key, String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException failure) {
            throw new IllegalStateException("HMAC-SHA256 is unavailable", failure);
        }
    }

    private static String hex(byte[] value) { return HexFormat.of().formatHex(value); }
}
