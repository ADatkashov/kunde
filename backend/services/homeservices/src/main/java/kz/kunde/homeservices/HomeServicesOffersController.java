package kz.kunde.homeservices;

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

/** Public catalogue of Home Services offers: only PUBLISHED offers of open venues and available services. */
@RestController
@Validated
@RequestMapping("/api/v1/home-services/offers")
public class HomeServicesOffersController {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public HomeServicesOffersController(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    public record OfferCard(String id, String serviceId, String venueId, String venueName, String definitionCode,
            String categoryCode, String nameRu, String nameKk, String nameEn, String serviceName, long priceMinor,
            String pricingModel, int durationMinutes, boolean homeVisit, int warrantyDays) {}

    @GetMapping
    public ResponseEntity<List<OfferCard>> offers(
            @RequestParam(required = false) @Pattern(regexp = "[A-Z][A-Z0-9_]{1,31}") String category,
            @RequestParam(required = false) @Pattern(regexp = "[A-Z][A-Z0-9_]{1,39}") String definition,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        var cards = db.query("""
                select o.id, o.service_id, v.id as venue_id, v.name as venue_name, d.code, d.category_code,
                       d.name_ru, d.name_kk, d.name_en, s.name as service_name, s.price_minor, o.pricing_model,
                       s.duration_minutes, o.home_visit, o.warranty_days
                from marketplace.home_service_offers o
                join marketplace.home_service_definitions d on d.code = o.definition_code
                join marketplace.home_service_categories c on c.code = d.category_code
                join marketplace.booking_services s on s.id = o.service_id
                join marketplace.booking_venues v on v.id = s.venue_id
                where o.status = 'PUBLISHED' and d.active and c.active and s.available and v.is_open
                  and (?::text is null or d.category_code = ?) and (?::text is null or d.code = ?)
                order by c.sort_order, d.code, s.price_minor, o.id limit ? offset ?
                """, (rs, row) -> new OfferCard(rs.getString("id"), rs.getString("service_id"), rs.getString("venue_id"),
                rs.getString("venue_name"), rs.getString("code"), rs.getString("category_code"), rs.getString("name_ru"),
                rs.getString("name_kk"), rs.getString("name_en"), rs.getString("service_name"), rs.getLong("price_minor"),
                rs.getString("pricing_model"), rs.getInt("duration_minutes"), rs.getBoolean("home_visit"),
                rs.getInt("warranty_days")), category, category, definition, definition, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(cards);
    }
}
