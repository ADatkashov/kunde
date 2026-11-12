package kz.kunde.identity;

import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerConsentService {
    private final JdbcTemplate db;

    public ConsumerConsentService(JdbcTemplate db) {
        this.db = db;
    }

    public record ConsentStatus(UUID policyId, String purpose, String policyVersion,
                                String locale, String documentSha256, boolean granted) {}

    @Transactional(readOnly = true)
    public List<ConsentStatus> list(Jwt principal) {
        UUID userId = currentUser(principal);
        return db.query("""
                SELECT p.id, p.purpose, p.policy_version, p.locale, p.document_sha256,
                       COALESCE((SELECT e.action = 'GRANTED'
                                 FROM profile.consent_events e
                                 WHERE e.user_id = ? AND e.policy_id = p.id
                                 ORDER BY e.id DESC LIMIT 1), false) AS granted
                FROM profile.consent_policies p
                WHERE p.approved_at IS NOT NULL
                ORDER BY p.purpose, p.policy_version, p.locale
                """, (rs, row) -> new ConsentStatus(rs.getObject(1, UUID.class),
                rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getString(5), rs.getBoolean(6)), userId);
    }

    @Transactional
    public ConsentStatus change(Jwt principal, UUID policyId, boolean grant) {
        UUID userId = currentUser(principal);
        // Serialize writes for the same user/policy pair, including the first event.
        db.query("SELECT pg_advisory_xact_lock(hashtext(?), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {},
                userId.toString(), policyId.toString());
        // Hold a row lock until commit: account restrictions cannot race a grant.
        Boolean active = db.query("""
                SELECT true FROM identity.users
                WHERE id = ? AND status = 'ACTIVE'
                FOR SHARE
                """, rs -> rs.next() ? Boolean.TRUE : Boolean.FALSE, userId);
        if (!Boolean.TRUE.equals(active)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_UNAVAILABLE",
                    "Active consumer account required");
        }
        List<ConsentStatus> policies = db.query("""
                SELECT id, purpose, policy_version, locale, document_sha256
                FROM profile.consent_policies WHERE id = ? AND approved_at IS NOT NULL
                """, (rs, row) -> new ConsentStatus(rs.getObject(1, UUID.class),
                rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getString(5), false), policyId);
        if (policies.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "CONSENT_POLICY_UNAVAILABLE",
                    "Approved consent policy not found");
        }
        Boolean previous = db.query("""
                SELECT action = 'GRANTED' FROM profile.consent_events
                WHERE user_id = ? AND policy_id = ?
                ORDER BY id DESC LIMIT 1
                """, rs -> rs.next() ? rs.getBoolean(1) : null, userId, policyId);
        if (previous == null || previous != grant) {
            // Withdrawal is recorded even if no prior grant exists, without implying consent.
            db.update("""
                    INSERT INTO profile.consent_events (user_id, policy_id, action)
                    VALUES (?, ?, ?)
                    """, userId, policyId, grant ? "GRANTED" : "WITHDRAWN");
        }
        ConsentStatus policy = policies.get(0);
        return new ConsentStatus(policy.policyId(), policy.purpose(), policy.policyVersion(),
                policy.locale(), policy.documentSha256(), grant);
    }

    private UUID currentUser(Jwt principal) {
        UUID userId = db.query("""
                SELECT b.user_id FROM identity.external_bindings b
                JOIN identity.users u ON u.id = b.user_id
                WHERE b.issuer = ? AND b.subject = ? AND u.status = 'ACTIVE'
                """, rs -> rs.next() ? rs.getObject(1, UUID.class) : null,
                principal.getClaimAsString("iss"), principal.getSubject());
        if (userId == null) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_UNAVAILABLE",
                    "Active consumer account required");
        }
        return userId;
    }
}
