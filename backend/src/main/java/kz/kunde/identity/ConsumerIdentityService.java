package kz.kunde.identity;

import java.time.OffsetDateTime;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

@Service
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerIdentityService {
    private final JdbcTemplate db;

    public ConsumerIdentityService(JdbcTemplate db) {
        this.db = db;
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public ConsumerProfile get(Jwt principal) {
        return profile(resolve(principal, true));
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public ConsumerProfile update(Jwt principal, String name, String language, long version) {
        UUID user = resolve(principal, false);
        int updated = db.update("""
                UPDATE profile.consumer_profiles
                SET display_name = ?, preferred_language = ?, updated_at = now(), version = version + 1
                WHERE user_id = ? AND version = ?
                """, name.strip(), language, user, version);
        if (updated == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "PROFILE_VERSION_CONFLICT", "Reload the profile and retry");
        }
        audit(user, "PROFILE_UPDATED");
        return profile(user);
    }

    private UUID resolve(Jwt principal, boolean provision) {
        String issuer = principal.getClaimAsString("iss");
        String subject = principal.getSubject();
        UUID user = find(issuer, subject);
        if (user == null && provision) {
            db.query("SELECT pg_advisory_xact_lock(hashtext(?), hashtext(?))",
                    (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, issuer, subject);
            user = find(issuer, subject);
            if (user == null) {
                user = db.queryForObject("INSERT INTO identity.users DEFAULT VALUES RETURNING id", UUID.class);
                db.update("INSERT INTO identity.external_bindings (issuer, subject, user_id) VALUES (?, ?, ?)",
                        issuer, subject, user);
                db.update("INSERT INTO profile.consumer_profiles (user_id) VALUES (?)", user);
                audit(user, "PROVISIONED");
            }
        }
        if (user == null) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_NOT_PROVISIONED", "Open your profile first");
        }
        String status = db.queryForObject("SELECT status FROM identity.users WHERE id = ? FOR SHARE", String.class, user);
        if (!"ACTIVE".equals(status)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_UNAVAILABLE", "Account access is unavailable");
        }
        return user;
    }

    private UUID find(String issuer, String subject) {
        return db.query("SELECT user_id FROM identity.external_bindings WHERE issuer = ? AND subject = ? FOR SHARE",
                (org.springframework.jdbc.core.ResultSetExtractor<UUID>) rs -> rs.next() ? rs.getObject(1, UUID.class) : null,
                issuer, subject);
    }

    private ConsumerProfile profile(UUID user) {
        return db.queryForObject("""
                SELECT u.id, p.display_name, p.preferred_language, u.status, u.created_at, p.updated_at, p.version
                FROM identity.users u JOIN profile.consumer_profiles p ON p.user_id = u.id WHERE u.id = ?
                """, (rs, row) -> new ConsumerProfile(rs.getObject("id", UUID.class), rs.getString("display_name"),
                rs.getString("preferred_language"), rs.getString("status"),
                rs.getObject("created_at", OffsetDateTime.class).toInstant(),
                rs.getObject("updated_at", OffsetDateTime.class).toInstant(), rs.getLong("version")), user);
    }

    private void audit(UUID user, String event) {
        db.update("INSERT INTO identity.account_events (user_id, event_type) VALUES (?, ?)", user, event);
    }
}
