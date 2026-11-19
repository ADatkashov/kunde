package kz.kunde.admin;

import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Staff directory for existing platform access managers. */
@RestController
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminEmployeeController {
    private final AdminGrants grants;
    private final JdbcTemplate db;

    public AdminEmployeeController(AdminGrants grants, JdbcTemplate db) {
        this.grants = grants;
        this.db = db;
    }

    @GetMapping("/api/v1/admin/employees")
    ResponseEntity<Page> employees(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) UUID after, @RequestParam(defaultValue = "25") int limit) {
        var actor = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(actor, Permission.ADMIN_GRANTS);
        if (limit < 1 || limit > 100) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_EMPLOYEE_PAGE_SIZE", "Page size must be between 1 and 100");
        }

        var staff = db.query("""
                select u.id, u.status, p.display_name,
                    exists (select 1 from identity.effective_admin_permissions g where g.user_id = u.id) as has_access
                from identity.users u
                left join profile.consumer_profiles p on p.user_id = u.id
                where (?::uuid is null or u.id > ?::uuid)
                  and (exists (select 1 from identity.admin_grants g where g.user_id = u.id)
                    or exists (select 1 from identity.admin_role_assignments a where a.user_id = u.id))
                order by u.id
                limit ?
                """, (rs, row) -> new Employee(rs.getObject("id", UUID.class), rs.getString("display_name"),
                        rs.getString("status"), rs.getBoolean("has_access")), after, after, limit + 1);
        UUID next = staff.size() > limit ? staff.get(limit - 1).id() : null;
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new Page(staff.stream().limit(limit).toList(), next));
    }

    public record Page(List<Employee> employees, UUID next) {}
    public record Employee(UUID id, String displayName, String status, boolean hasAccess) {}
}
