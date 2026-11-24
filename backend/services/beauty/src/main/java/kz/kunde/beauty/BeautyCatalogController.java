package kz.kunde.beauty;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
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

/** Beauty &amp; Care category taxonomy. Offers, prices and slots come from the Booking engine; hidden while BEAUTY is off. */
@RestController
@Validated
@RequestMapping("/api/v1/beauty")
public class BeautyCatalogController {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public BeautyCatalogController(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    public record Category(String code, String nameRu, String nameKk, String nameEn, String icon, boolean featured) {}

    @GetMapping("/categories")
    public ResponseEntity<List<Category>> categories(
            @RequestParam(required = false) Boolean featured,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        if (!toggles.enabled(Feature.BEAUTY)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BEAUTY_DISABLED", "Beauty is unavailable");
        }
        var categories = db.query("""
                select code, name_ru, name_kk, name_en, icon, featured
                from marketplace.beauty_categories
                where active and (?::boolean is null or featured = ?)
                order by sort_order, code limit ? offset ?
                """, (rs, row) -> new Category(rs.getString("code"), rs.getString("name_ru"), rs.getString("name_kk"),
                rs.getString("name_en"), rs.getString("icon"), rs.getBoolean("featured")), featured, featured, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(categories);
    }
}
