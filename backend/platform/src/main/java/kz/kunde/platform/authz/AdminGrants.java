package kz.kunde.platform.authz;

import java.util.List;
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
    public enum Permission { PARTNER_VERIFICATION, ADMIN_GRANTS, RIDE_VERIFICATION, RIDE_OPERATIONS, DELIVERY_OPERATIONS, AUTO_OPERATIONS, LEISURE_OPERATIONS, HEALTH_OPERATIONS, FOOD_OPERATIONS, EDUCATION_OPERATIONS, GROCERIES_OPERATIONS, EVENTS_OPERATIONS, HOME_SERVICES_CATALOG, BEAUTY_OPERATIONS, HOME_SERVICES_OPERATIONS }

    /**
     * Server-resolved resource attributes. A missing attribute matches only an unrestricted grant on that
     * dimension. Callers that read platform-wide data must use the unscoped overload.
     */
    public record Scope(String productCode, String regionCode, UUID organizationId, UUID resourceId) {}

    private static final Scope PLATFORM = new Scope(null, null, null, null);

    private final JdbcTemplate db;

    public AdminGrants(JdbcTemplate db) {
        this.db = db;
    }

    public List<Permission> activePermissions(UUID userId) {
        var grants = db.query("""
                SELECT DISTINCT permission, product_code, region_code, organization_id, resource_id
                FROM identity.effective_admin_permissions
                WHERE user_id = ? ORDER BY permission""", (rs, row) -> new EffectivePermission(
                        Permission.valueOf(rs.getString("permission")),
                        new Scope(rs.getString("product_code"), rs.getString("region_code"),
                                rs.getObject("organization_id", UUID.class), rs.getObject("resource_id", UUID.class))), userId);
        if (grants.isEmpty()) {
            throw forbidden();
        }
        return grants.stream().filter(grant -> grant.scope().equals(PLATFORM)).map(EffectivePermission::permission).toList();
    }

    public void require(UUID userId, Permission permission) {
        require(userId, permission, PLATFORM);
    }

    public void require(UUID userId, Permission permission, Scope scope) {
        boolean granted = Boolean.TRUE.equals(db.queryForObject("""
                SELECT EXISTS (
                    SELECT 1 FROM identity.effective_admin_permissions
                    WHERE user_id = ? AND permission = ?
                      AND (product_code IS NULL OR product_code = ?)
                      AND (region_code IS NULL OR region_code = ?)
                      AND (organization_id IS NULL OR organization_id = ?)
                      AND (resource_id IS NULL OR resource_id = ?)
                )""", Boolean.class, userId, permission.name(), scope.productCode(), scope.regionCode(),
                scope.organizationId(), scope.resourceId()));
        if (!granted) {
            throw forbidden();
        }
    }

    private static ApiException forbidden() {
        return new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Administrator permission is required");
    }

    private record EffectivePermission(Permission permission, Scope scope) {}
}
