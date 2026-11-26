package kz.kunde.homeservices;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
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
    private final HomeServicePricing pricing;
    private final PartnerDirectory partners;

    public HomeServicesOffersController(JdbcTemplate db, FeatureToggles toggles, HomeServicePricing pricing,
            PartnerDirectory partners) {
        this.db = db;
        this.toggles = toggles;
        this.pricing = pricing;
        this.partners = partners;
    }

    /** Itemised price of one published offer for an address, time and size: exactly what a booking made now would cost. */
    @GetMapping("/{offerId}/quote")
    public ResponseEntity<HomeServicePricing.Quote> quote(@PathVariable UUID offerId,
            @RequestParam(required = false) @Min(1) @Max(1000) Integer areaSqm,
            @RequestParam(required = false) @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE_TIME) java.time.OffsetDateTime startsAt,
            @RequestParam(required = false) @jakarta.validation.constraints.DecimalMin("-90") @jakarta.validation.constraints.DecimalMax("90") Double lat,
            @RequestParam(required = false) @jakarta.validation.constraints.DecimalMin("-180") @jakarta.validation.constraints.DecimalMax("180") Double lng,
            @RequestParam(defaultValue = "false") boolean urgent) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(pricing.quote(offerId, areaSqm, startsAt, lat, lng, urgent));
    }

    public record OfferCard(String id, String serviceId, String venueId, String venueName, String definitionCode,
            String categoryCode, String nameRu, String nameKk, String nameEn, String serviceName, long priceMinor,
            String pricingModel, int durationMinutes, boolean homeVisit, int warrantyDays, long pricePerSqmMinor) {}

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
                       s.duration_minutes, o.home_visit, o.warranty_days, s.price_per_sqm_minor
                from marketplace.home_service_offers o
                join marketplace.home_service_definitions d on d.code = o.definition_code
                join marketplace.home_service_categories c on c.code = d.category_code
                join marketplace.booking_services s on s.id = o.service_id
                join marketplace.booking_venues v on v.id = s.venue_id
                where o.status = 'PUBLISHED' and d.active and c.active and s.available and v.is_open
                  and v.partner_id = any(?::uuid[])
                  and (?::text is null or d.category_code = ?) and (?::text is null or d.code = ?)
                order by c.sort_order, d.code, s.price_minor, o.id limit ? offset ?
                """, (rs, row) -> new OfferCard(rs.getString("id"), rs.getString("service_id"), rs.getString("venue_id"),
                rs.getString("venue_name"), rs.getString("code"), rs.getString("category_code"), rs.getString("name_ru"),
                rs.getString("name_kk"), rs.getString("name_en"), rs.getString("service_name"), rs.getLong("price_minor"),
                rs.getString("pricing_model"), rs.getInt("duration_minutes"), rs.getBoolean("home_visit"),
                rs.getInt("warranty_days"), rs.getLong("price_per_sqm_minor")), arrayLiteral(partners.approvedPartnerIds()), category, category, definition, definition, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(cards);
    }

    /** PostgreSQL array literal of ids; an empty set matches nothing. */
    static String arrayLiteral(java.util.Set<UUID> ids) {
        return ids.stream().map(UUID::toString).collect(java.util.stream.Collectors.joining(",", "{", "}"));
    }
}
