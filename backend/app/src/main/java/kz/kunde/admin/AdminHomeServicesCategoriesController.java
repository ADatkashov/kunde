package kz.kunde.admin;

import kz.kunde.platform.authz.AdminGrants;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;
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
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/api/v1/admin/home-services/categories")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminHomeServicesCategoriesController {
    private static final String COLUMNS = "code, name_ru, name_kk, name_en, icon, active, sort_order, version";
    private static final String CODE = "[A-Z][A-Z0-9_]{1,31}";

    private final JdbcTemplate db;
    private final AdminGrants grants;

    public AdminHomeServicesCategoriesController(JdbcTemplate db, AdminGrants grants) {
        this.db = db;
        this.grants = grants;
    }

    public record Category(String code, String nameRu, String nameKk, String nameEn, String icon, boolean active,
            int sortOrder, long version) {}

    public record CategoryChange(
            @NotBlank @Size(max = 120) String nameRu,
            @NotBlank @Size(max = 120) String nameKk,
            @NotBlank @Size(max = 120) String nameEn,
            @NotNull @Pattern(regexp = "[a-z][a-z0-9_]{1,39}") String icon,
            @NotNull Boolean active,
            @NotNull @Min(0) Integer sortOrder,
            @NotNull @Min(0) Long expectedVersion,
            @NotBlank @Size(max = 200) String reason) {}

    @GetMapping
    public ResponseEntity<List<Category>> categories(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        authorize(principal);
        var categories = db.query("select " + COLUMNS + " " + """
                from marketplace.home_service_categories order by sort_order, code limit ? offset ?
                """, AdminHomeServicesCategoriesController::category, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(categories);
    }

    @PutMapping("/{code}")
    @Transactional
    public ResponseEntity<Category> save(@AuthenticationPrincipal Jwt principal,
            @PathVariable @Pattern(regexp = CODE) String code, @RequestBody @Valid CategoryChange change) {
        UUID actor = authorize(principal);
        String reason = change.reason().strip();
        if (reason.length() < 3) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of at least 3 characters is required");
        }
        var previous = db.queryForList("""
                select to_jsonb(c)::text from marketplace.home_service_categories c where c.code = ? for update
                """, String.class, code).stream().findFirst();
        List<Category> saved;
        if (change.expectedVersion() == 0) {
            saved = db.query("""
                    insert into marketplace.home_service_categories (code, name_ru, name_kk, name_en, icon, active, sort_order)
                    values (?, ?, ?, ?, ?, ?, ?) on conflict (code) do nothing returning
                    """ + COLUMNS, AdminHomeServicesCategoriesController::category, code, change.nameRu().strip(),
                    change.nameKk().strip(), change.nameEn().strip(), change.icon(), change.active(), change.sortOrder());
        } else {
            saved = db.query("""
                    update marketplace.home_service_categories set name_ru = ?, name_kk = ?, name_en = ?, icon = ?,
                        active = ?, sort_order = ?, version = version + 1, updated_at = now()
                    where code = ? and version = ? returning
                    """ + COLUMNS, AdminHomeServicesCategoriesController::category, change.nameRu().strip(),
                    change.nameKk().strip(), change.nameEn().strip(), change.icon(), change.active(), change.sortOrder(),
                    code, change.expectedVersion());
        }
        if (saved.isEmpty()) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The category version changed or the category no longer exists");
        }
        db.update("""
                insert into marketplace.home_service_category_events (category_code, version, admin_user_id, reason, previous_state, new_state)
                select c.code, c.version, ?, ?, ?::jsonb, to_jsonb(c) from marketplace.home_service_categories c where c.code = ?
                """, actor, reason, previous.orElse(null), code);
        return ResponseEntity.status(change.expectedVersion() == 0 ? HttpStatus.CREATED : HttpStatus.OK)
                .cacheControl(CacheControl.noStore()).body(saved.getFirst());
    }

    private UUID authorize(Jwt principal) {
        UUID actor = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Access is not allowed"));
        grants.require(actor, AdminGrants.Permission.HOME_SERVICES_CATALOG);
        return actor;
    }

    private static Category category(ResultSet row, int index) throws SQLException {
        return new Category(row.getString("code"), row.getString("name_ru"), row.getString("name_kk"),
                row.getString("name_en"), row.getString("icon"), row.getBoolean("active"),
                row.getInt("sort_order"), row.getLong("version"));
    }
}
