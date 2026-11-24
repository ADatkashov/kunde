package kz.kunde.auto;

import kz.kunde.platform.FeatureToggles;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingSlots;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
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

/** Public read-only Auto catalog: categories, stations / car washes with search and filters, services, free slots. Empty while Auto is off. */
@RestController
@Validated
@RequestMapping("/api/v1/auto")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoCatalogController {
    public record Category(String code, String nameRu, String nameKk, String nameEn, boolean mobile, boolean enabled) {}

    public record Venue(String id, String name, String description, String addressText, boolean open, boolean synthetic,
            Long fromPriceMinor, List<String> categories, Double rating, int reviews) {}

    public record ServiceItem(String id, String name, String description, String category, int durationMinutes, long priceMinor,
            String priceKind, String conditions, boolean available) {}

    public record VenueDetail(Venue venue, List<ServiceItem> services, String cancellationTerms) {}

    private final JdbcTemplate db;
    private final BookingSlots slots;
    private final FeatureToggles toggles;

    public AutoCatalogController(JdbcTemplate db, BookingSlots slots, FeatureToggles toggles) {
        this.db = db;
        this.slots = slots;
        this.toggles = toggles;
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    @GetMapping("/categories")
    public ResponseEntity<List<Category>> categories() {
        if (!toggles.enabled(FeatureToggles.Feature.AUTO)) { return ok(List.of()); }
        return ok(db.query("select code, name_ru, name_kk, name_en, mobile, enabled from marketplace.auto_service_categories order by sort_order",
                (rs, n) -> new Category(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getBoolean(5), rs.getBoolean(6))));
    }

    /** {@code category}: only venues with an available service of that kind; {@code q}: name or address contains the text. */
    @GetMapping("/venues")
    public ResponseEntity<List<Venue>> venues(@RequestParam(required = false) String category, @RequestParam(required = false) String q) {
        if (!toggles.enabled(FeatureToggles.Feature.AUTO)) { return ok(List.of()); }
        String text = q == null ? null : q.strip();
        if (text != null && text.length() > 60) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "QUERY_TOO_LONG", "q is at most 60 characters");
        }
        return ok(db.query("""
                select v.id, v.name, v.description, v.address_text, v.is_open, v.is_synthetic,
                       (select min(s.price_minor) from marketplace.booking_services s where s.venue_id = v.id and s.available
                            and (?::text is null or s.auto_category = ?::text)) as from_price,
                       (select round(avg(r.rating), 1) from transactions.auto_reviews r where r.venue_id = v.id) as rating,
                       (select count(*) from transactions.auto_reviews r where r.venue_id = v.id) as reviews,
                       coalesce((select array_agg(distinct s.auto_category order by s.auto_category) from marketplace.booking_services s
                            join marketplace.auto_service_categories c on c.code = s.auto_category and c.enabled
                            where s.venue_id = v.id and s.available), '{}') as cats
                from marketplace.booking_venues v
                where v.category = 'AUTO' and (?::text is null or exists (select 1 from marketplace.booking_services s
                        join marketplace.auto_service_categories c on c.code = s.auto_category and c.enabled
                        where s.venue_id = v.id and s.available and s.auto_category = ?::text))
                  and (?::text is null or v.name ilike '%' || replace(replace(?::text, '%', ''), '_', '') || '%'
                       or v.address_text ilike '%' || replace(replace(?::text, '%', ''), '_', '') || '%')
                order by v.is_open desc, v.sort_order, v.name
                """, (rs, n) -> {
                    var arr = (String[]) rs.getArray("cats").getArray();
                    return new Venue(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getBoolean(5), rs.getBoolean(6),
                            rs.getObject("from_price", Long.class), List.of(arr), rs.getBigDecimal("rating") == null ? null : rs.getBigDecimal("rating").doubleValue(), rs.getInt("reviews"));
                }, category, category, category, category, text, text, text));
    }

    @GetMapping("/venues/{venueId}")
    public ResponseEntity<VenueDetail> venue(@PathVariable UUID venueId) {
        if (!toggles.enabled(FeatureToggles.Feature.AUTO)) { throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue is not available"); }
        Venue venue = venues(null, null).getBody().stream().filter(v -> v.id().equals(venueId.toString())).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue is not available"));
        List<ServiceItem> services = db.query("""
                select s.id, s.name, s.description, s.auto_category, s.duration_minutes, s.price_minor, s.price_kind, s.conditions, s.available
                from marketplace.booking_services s join marketplace.auto_service_categories c on c.code = s.auto_category and c.enabled
                where s.venue_id = ? order by s.sort_order, s.name
                """, (rs, n) -> new ServiceItem(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getInt(5), rs.getLong(6),
                rs.getString(7), rs.getString(8), rs.getBoolean(9)), venueId);
        return ok(new VenueDetail(venue, services, AutoService.CANCELLATION_TERMS));
    }

    /** Free start times (venue time zone, Asia/Almaty by default) for a service on a date, any post. */
    @GetMapping("/slots")
    public ResponseEntity<List<BookingSlots.Slot>> slots(@RequestParam UUID venueId, @RequestParam UUID serviceId, @RequestParam LocalDate date) {
        if (!toggles.enabled(FeatureToggles.Feature.AUTO)) { return ok(List.of()); }
        return ok(slots.freeSlots(venueId, serviceId, null, date));
    }
}
