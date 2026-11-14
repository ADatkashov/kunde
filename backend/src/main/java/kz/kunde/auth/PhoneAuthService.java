package kz.kunde.auth;

import java.security.MessageDigest;
import java.security.SecureRandom;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * OTP challenge, session and refresh-token lifecycle. Public failures are deliberately uniform so
 * the API never reveals whether a phone number is registered. Codes and tokens are stored only as
 * keyed hashes and are never logged.
 */
public class PhoneAuthService {
    public record OtpChallenge(int expiresInSeconds, int resendAfterSeconds) {}
    public record Tokens(String accessToken, String refreshToken, int expiresIn, int refreshExpiresIn) {}

    private static final SecureRandom RANDOM = new SecureRandom();
    private final JdbcTemplate db;
    private final TransactionTemplate tx;
    private final PhoneAuthProperties props;
    private final AuthKeys keys;
    private final AccessTokenIssuer issuer;
    private final OtpDeliveryProvider provider;

    public PhoneAuthService(JdbcTemplate db, PlatformTransactionManager txManager, PhoneAuthProperties props,
            AuthKeys keys, AccessTokenIssuer issuer, OtpDeliveryProvider provider) {
        this.db = db;
        this.tx = new TransactionTemplate(txManager);
        this.props = props;
        this.keys = keys;
        this.issuer = issuer;
        this.provider = provider;
    }

    // ---- OTP request -------------------------------------------------------------------------

    public OtpChallenge requestOtp(String rawPhone) {
        String phone = PhoneNumber.normalize(rawPhone)
                .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PHONE", "Phone number is invalid"));
        if (!provider.available()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_DELIVERY_UNAVAILABLE",
                    "Code delivery is not available");
        }
        String phoneHash = keys.phoneHash(phone);
        String code = tx.execute(status -> {
            lockPhone(phone);
            if (throttled(phone)) {
                event("OTP_THROTTLED", null, phoneHash);
                return null;
            }
            // Only the newest challenge may ever succeed.
            db.update("UPDATE identity.otp_challenges SET consumed_at = now() WHERE phone_e164 = ? AND consumed_at IS NULL", phone);
            UUID id = UUID.randomUUID();
            String value = provider.fixedCode(phone).orElseGet(PhoneAuthService::randomCode);
            db.update("INSERT INTO identity.otp_challenges (id, phone_e164, code_hash, expires_at) VALUES (?, ?, ?, ?)",
                    id, phone, keys.otpHash(phone, id, value),
                    OffsetDateTime.now(ZoneOffset.UTC).plusSeconds(props.otpTtlSeconds()));
            event("OTP_REQUESTED", null, phoneHash);
            return value;
        });
        if (code == null) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "OTP_RATE_LIMITED", "Too many code requests; retry later");
        }
        if (provider.canDeliver(phone)) {
            try {
                provider.deliver(phone, code);
            } catch (OtpDeliveryProvider.OtpDeliveryException failure) {
                db.update("UPDATE identity.otp_challenges SET consumed_at = now() WHERE phone_e164 = ? AND consumed_at IS NULL", phone);
                event("OTP_DELIVERY_FAILED", null, phoneHash);
                throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_DELIVERY_UNAVAILABLE",
                        "Code delivery is not available");
            }
        }
        return new OtpChallenge(props.otpTtlSeconds(), props.otpCooldownSeconds());
    }

    private boolean throttled(String phone) {
        Integer cooling = db.queryForObject("""
                SELECT count(*) FROM identity.otp_challenges
                WHERE phone_e164 = ? AND created_at > now() - make_interval(secs => ?)
                """, Integer.class, phone, props.otpCooldownSeconds());
        Integer window = db.queryForObject("""
                SELECT count(*) FROM identity.otp_challenges
                WHERE phone_e164 = ? AND created_at > now() - make_interval(secs => ?)
                """, Integer.class, phone, props.otpWindowSeconds());
        Integer day = db.queryForObject("""
                SELECT count(*) FROM identity.otp_challenges
                WHERE phone_e164 = ? AND created_at > now() - interval '1 day'
                """, Integer.class, phone);
        return cooling > 0 || window >= props.otpMaxPerWindow() || day >= props.otpMaxPerDay();
    }

    // ---- OTP verification --------------------------------------------------------------------

    private record Verification(Tokens tokens, ApiException failure) {}

    public Tokens verifyOtp(String rawPhone, String code) {
        Optional<String> normalized = PhoneNumber.normalize(rawPhone);
        if (normalized.isEmpty() || code == null || !code.matches("[0-9]{6}")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Phone number or code format is invalid");
        }
        String phone = normalized.get();
        String phoneHash = keys.phoneHash(phone);
        // Failed attempts must commit (the counter is the brute-force defence), so failures are
        // returned out of the transaction and thrown afterwards.
        Verification result = tx.execute(status -> {
            lockPhone(phone);
            var challenge = db.query("""
                    SELECT id, code_hash, attempts, expires_at > now() AS live FROM identity.otp_challenges
                    WHERE phone_e164 = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE
                    """, rs -> rs.next() ? new Challenge(rs.getObject("id", UUID.class), rs.getString("code_hash"),
                    rs.getInt("attempts"), rs.getBoolean("live")) : null, phone);
            if (challenge == null || !challenge.live() || challenge.attempts() >= props.otpMaxAttempts()) {
                return new Verification(null, invalidCode());
            }
            String expected = keys.otpHash(phone, challenge.id(), code);
            boolean match = MessageDigest.isEqual(expected.getBytes(StandardCharsets.US_ASCII),
                    challenge.hash().getBytes(StandardCharsets.US_ASCII));
            if (!match) {
                int attempts = challenge.attempts() + 1;
                boolean locked = attempts >= props.otpMaxAttempts();
                db.update("UPDATE identity.otp_challenges SET attempts = ?, consumed_at = CASE WHEN ? THEN now() END WHERE id = ?",
                        attempts, locked, challenge.id());
                event(locked ? "OTP_LOCKED" : "OTP_FAILED", null, phoneHash);
                return new Verification(null, invalidCode());
            }
            db.update("UPDATE identity.otp_challenges SET consumed_at = now() WHERE id = ?", challenge.id());
            UUID user = findOrCreateUser(phone);
            String status2 = db.queryForObject("SELECT status FROM identity.users WHERE id = ?", String.class, user);
            if (!"ACTIVE".equals(status2)) {
                return new Verification(null,
                        new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_UNAVAILABLE", "Account access is unavailable"));
            }
            db.update("UPDATE identity.phone_identities SET last_login_at = now() WHERE user_id = ?", user);
            event("OTP_VERIFIED", user, phoneHash);
            UUID session = UUID.randomUUID();
            db.update("INSERT INTO identity.auth_sessions (id, user_id, expires_at) VALUES (?, ?, ?)", session, user,
                    OffsetDateTime.now(ZoneOffset.UTC).plusDays(props.sessionMaxDays()));
            event("SESSION_STARTED", user, null);
            return new Verification(newTokens(user, session, OffsetDateTime.now(ZoneOffset.UTC).plusDays(props.refreshTtlDays())), null);
        });
        if (result.failure() != null) throw result.failure();
        return result.tokens();
    }

    private record Challenge(UUID id, String hash, int attempts, boolean live) {}

    private static ApiException invalidCode() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CODE", "The code is invalid or expired");
    }

    private UUID findOrCreateUser(String phone) {
        UUID existing = db.query("SELECT user_id FROM identity.phone_identities WHERE phone_e164 = ?",
                rs -> rs.next() ? rs.getObject(1, UUID.class) : null, phone);
        if (existing != null) return existing;
        UUID user = db.queryForObject("INSERT INTO identity.users DEFAULT VALUES RETURNING id", UUID.class);
        db.update("INSERT INTO identity.phone_identities (user_id, phone_e164) VALUES (?, ?)", user, phone);
        // The consumer domain resolves accounts by (issuer, subject); bind it up front.
        db.update("INSERT INTO identity.external_bindings (issuer, subject, user_id) VALUES (?, ?, ?)",
                props.issuer(), user.toString(), user);
        db.update("INSERT INTO profile.consumer_profiles (user_id) VALUES (?)", user);
        db.update("INSERT INTO identity.account_events (user_id, event_type) VALUES (?, 'PROVISIONED')", user);
        return user;
    }

    // ---- Refresh and logout ------------------------------------------------------------------

    private record RefreshOutcome(Tokens tokens, boolean replay) {}

    public Tokens refresh(String refreshToken) {
        String hash = keys.refreshHash(refreshToken);
        RefreshOutcome outcome = tx.execute(status -> {
            var row = db.query("""
                    SELECT t.id, t.session_id, t.used_at IS NOT NULL AS used, t.expires_at > now() AS token_live,
                           s.user_id, s.revoked_at IS NULL AND s.expires_at > now() AS session_live, s.expires_at
                    FROM identity.refresh_tokens t JOIN identity.auth_sessions s ON s.id = t.session_id
                    WHERE t.token_hash = ? FOR UPDATE OF t, s
                    """, rs -> rs.next() ? new RefreshRow(rs.getObject("id", UUID.class),
                    rs.getObject("session_id", UUID.class), rs.getObject("user_id", UUID.class),
                    rs.getBoolean("used"), rs.getBoolean("token_live"), rs.getBoolean("session_live"),
                    rs.getObject("expires_at", OffsetDateTime.class)) : null, hash);
            if (row == null || !row.sessionLive() || !row.tokenLive()) return new RefreshOutcome(null, false);
            if (row.used()) {
                // A rotated token was presented again: assume theft and kill the whole session.
                db.update("UPDATE identity.auth_sessions SET revoked_at = now(), revoke_reason = 'REFRESH_REPLAY' WHERE id = ?",
                        row.sessionId());
                event("REFRESH_REPLAY", row.userId(), null);
                return new RefreshOutcome(null, true);
            }
            String userStatus = db.queryForObject("SELECT status FROM identity.users WHERE id = ?", String.class, row.userId());
            if (!"ACTIVE".equals(userStatus)) return new RefreshOutcome(null, false);
            db.update("UPDATE identity.refresh_tokens SET used_at = now() WHERE id = ?", row.id());
            db.update("UPDATE identity.auth_sessions SET last_used_at = now() WHERE id = ?", row.sessionId());
            OffsetDateTime until = OffsetDateTime.now(ZoneOffset.UTC).plusDays(props.refreshTtlDays());
            if (until.isAfter(row.sessionExpires())) until = row.sessionExpires();
            event("TOKEN_REFRESHED", row.userId(), null);
            return new RefreshOutcome(newTokens(row.userId(), row.sessionId(), until), false);
        });
        if (outcome.tokens() == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "The session is no longer valid");
        }
        return outcome.tokens();
    }

    private record RefreshRow(UUID id, UUID sessionId, UUID userId, boolean used, boolean tokenLive,
            boolean sessionLive, OffsetDateTime sessionExpires) {}

    /** Idempotent: an unknown or already revoked token produces the same silent success. */
    public void logout(String refreshToken) {
        String hash = keys.refreshHash(refreshToken);
        tx.executeWithoutResult(status -> {
            var found = db.query("""
                    SELECT s.id, s.user_id FROM identity.refresh_tokens t JOIN identity.auth_sessions s ON s.id = t.session_id
                    WHERE t.token_hash = ? AND s.revoked_at IS NULL FOR UPDATE OF s
                    """, rs -> rs.next() ? new UUID[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class)} : null, hash);
            if (found == null) return;
            db.update("UPDATE identity.auth_sessions SET revoked_at = now(), revoke_reason = 'LOGOUT' WHERE id = ?", found[0]);
            event("LOGOUT", found[1], null);
        });
    }

    /** Used by the resource server so logout and replay detection take effect before access-token expiry. */
    public boolean sessionActive(UUID sessionId) {
        Boolean live = db.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM identity.auth_sessions WHERE id = ? AND revoked_at IS NULL AND expires_at > now())",
                Boolean.class, sessionId);
        return Boolean.TRUE.equals(live);
    }

    // ---- helpers -----------------------------------------------------------------------------

    private Tokens newTokens(UUID user, UUID session, OffsetDateTime refreshUntil) {
        byte[] raw = new byte[32];
        RANDOM.nextBytes(raw);
        String refresh = Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        db.update("INSERT INTO identity.refresh_tokens (session_id, token_hash, expires_at) VALUES (?, ?, ?)",
                session, keys.refreshHash(refresh), refreshUntil);
        long refreshSeconds = Math.max(0, refreshUntil.toEpochSecond() - Instant.now().getEpochSecond());
        return new Tokens(issuer.issue(user, session, Instant.now()), refresh, issuer.ttlSeconds(), (int) refreshSeconds);
    }

    private void lockPhone(String phone) {
        db.query("SELECT pg_advisory_xact_lock(hashtext('phone-auth'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, phone);
    }

    private void event(String type, UUID user, String phoneHash) {
        db.update("INSERT INTO identity.auth_events (event_type, user_id, phone_hash) VALUES (?, ?, ?)", type, user, phoneHash);
    }

    static String randomCode() {
        return String.format("%06d", RANDOM.nextInt(1_000_000));
    }
}
