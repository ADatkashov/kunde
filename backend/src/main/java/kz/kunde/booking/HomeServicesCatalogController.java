package kz.kunde.booking;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The taxonomy of household services. Availability, prices and booking are supplied by partner offers. */
@RestController
@Validated
@RequestMapping("/api/v1/home-services")
public class HomeServicesCatalogController {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public HomeServicesCatalogController(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    public record Category(String code, String nameRu, String nameKk, String nameEn, String icon) {}

    public record Definition(String code, String categoryCode, String nameRu, String nameKk, String nameEn) {}

    @GetMapping("/categories")
    public ResponseEntity<List<Category>> categories(
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        requireEnabled();
        var categories = db.query("""
                select code, name_ru, name_kk, name_en, icon
                from marketplace.home_service_categories where active
                order by sort_order, code limit ? offset ?
                """, (rs, row) -> new Category(rs.getString("code"), rs.getString("name_ru"),
                rs.getString("name_kk"), rs.getString("name_en"), rs.getString("icon")), limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(categories);
    }

    @GetMapping("/definitions")
    public ResponseEntity<List<Definition>> definitions(
            @RequestParam(required = false) @Pattern(regexp = "[A-Z][A-Z0-9_]{1,31}") String category,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        requireEnabled();
        var definitions = db.query("""
                select d.code, d.category_code, d.name_ru, d.name_kk, d.name_en
                from marketplace.home_service_definitions d
                join marketplace.home_service_categories c on c.code = d.category_code
                where d.active and c.active and (?::text is null or d.category_code = ?)
                order by c.sort_order, c.code, d.code limit ? offset ?
                """, (rs, row) -> new Definition(rs.getString("code"), rs.getString("category_code"),
                rs.getString("name_ru"), rs.getString("name_kk"), rs.getString("name_en")), category, category, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(definitions);
    }

    private void requireEnabled() {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
    }
}
