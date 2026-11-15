package kz.kunde.admin;

import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * ADR-018: the {@code kunde.admin} scope is only an entry gate. Every admin request re-checks, in the database, that
 * the user is ACTIVE and holds an unrevoked grant for the needed permission, so revocation is immediate.
 */
@Component
public class AdminGrants {
    public enum Permission { PARTNER_VERIFICATION, ADMIN_GRANTS }

    private final JdbcTemplate db;

    public AdminGrants(JdbcTemplate db) {
        this.db = db;
    }

    public void require(UUID userId, Permission permission) {
        boolean granted = Boolean.TRUE.equals(db.queryForObject("""
                SELECT EXISTS (SELECT 1 FROM identity.admin_grants g JOIN identity.users u ON u.id = g.user_id
                               WHERE g.user_id = ? AND g.permission = ? AND g.revoked_at IS NULL AND u.status = 'ACTIVE')""",
                Boolean.class, userId, permission.name()));
        if (!granted) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Administrator permission is required");
        }
    }
}
