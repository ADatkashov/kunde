package kz.kunde.booking;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
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

/** Public read-only booking catalog: venues, services, masters and free slots. Only when app.booking.enabled. */
@RestController
@Validated
@RequestMapping("/api/v1/booking")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BookingCatalogController {
    public record Venue(String id, String slug, String category, String name, String description, String addressText,
            String emoji, String tone, String imageUrl, boolean open, boolean synthetic, Long fromPriceMinor) {}

    public record ServiceItem(String id, String name, String description, int durationMinutes, long priceMinor,
            boolean available, long pricePerSqmMinor, Integer minAreaSqm, Integer maxAreaSqm, boolean wellness) {}

    public record Master(String id, String name, String bio, String emoji, String tone, List<String> serviceIds) {}

    public record VenueDetail(Venue venue, List<ServiceItem> services, List<Master> masters) {}

    private final JdbcTemplate jdbc;
    private final BookingSlots slots;

    public BookingCatalogController(JdbcTemplate jdbc, BookingSlots slots) {
        this.jdbc = jdbc;
        this.slots = slots;
    }

    private static final String VENUE_SELECT = """
            select v.id, v.slug, v.category, v.name, v.description, v.address_text, v.emoji, v.tone, v.image_url,
                   v.is_open, v.is_synthetic,
                   (select min(s.price_minor + s.price_per_sqm_minor * coalesce(s.min_area_sqm, 0)) from marketplace.booking_services s where s.venue_id = v.id and s.available) as from_price
            from marketplace.booking_venues v
            """;

    private static Venue mapVenue(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Venue(rs.getString("id"), rs.getString("slug"), rs.getString("category"), rs.getString("name"),
                rs.getString("description"), rs.getString("address_text"), rs.getString("emoji"), rs.getString("tone"),
                rs.getString("image_url"), rs.getBoolean("is_open"), rs.getBoolean("is_synthetic"),
                rs.getObject("from_price", Long.class));
    }

    @GetMapping("/venues")
    public ResponseEntity<List<Venue>> venues(@RequestParam(defaultValue = "BARBER") String category) {
        if (!"BARBER".equals(category) && !"CLEANING".equals(category)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CATEGORY_INVALID", "category must be BARBER or CLEANING");
        }
        if ("CLEANING".equals(category)) {
            slots.requireHomeServices();
        }
        if ("BARBER".equals(category)) {
            slots.requireBeauty();
        }
        List<Venue> list = jdbc.query(VENUE_SELECT + " where v.category = ? order by v.is_open desc, v.sort_order, v.name",
                BookingCatalogController::mapVenue, category);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    @GetMapping("/health/venues")
    public ResponseEntity<List<Venue>> healthVenues(
            @RequestParam(defaultValue = "") @Size(max = 100) String q,
            @RequestParam(defaultValue = "") @Size(max = 24) String direction,
            @RequestParam(defaultValue = "") @Size(max = 100) String district,
            @RequestParam(defaultValue = "") @Size(max = 100) String organization,
            @RequestParam(defaultValue = "") @Size(max = 100) String service,
            @RequestParam(defaultValue = "") @Size(max = 100) String specialist,
            @RequestParam(defaultValue = "") @Size(max = 100) String specialty,
            @RequestParam(defaultValue = "0") @Min(0) long minPriceMinor,
            @RequestParam(defaultValue = "9223372036854775807") @Min(0) long maxPriceMinor,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        slots.requireHealthCatalog();
        if (minPriceMinor > maxPriceMinor) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "HEALTH_PRICE_RANGE_INVALID",
                    "minPriceMinor must not exceed maxPriceMinor");
        }
        String query = q.strip();
        String filters = """
                where v.category = 'HEALTH' and v.is_open and v.is_synthetic and v.health_published
                and strpos(lower(coalesce(v.address_text, '')), lower(?)) > 0
                and strpos(lower(v.name), lower(?)) > 0
                and exists (select 1 from marketplace.booking_services s where s.venue_id = v.id and s.available
                    and (? = '' or s.health_category = ?)
                    and strpos(lower(s.name), lower(?)) > 0
                    and s.price_minor between ? and ?
                    and ((? = '' and ? = '') or exists (
                        select 1 from marketplace.booking_master_services ms
                        join marketplace.booking_masters m on m.id = ms.master_id
                        where ms.service_id = s.id and m.venue_id = v.id and m.active
                        and (? = '' or strpos(lower(m.name), lower(?)) > 0)
                        and (? = '' or strpos(lower(m.bio), lower(?)) > 0)))
                    and (? = '' or strpos(lower(v.name), lower(?)) > 0 or strpos(lower(v.address_text), lower(?)) > 0
                        or strpos(lower(s.name), lower(?)) > 0
                        or exists (select 1 from marketplace.booking_master_services ms
                            join marketplace.booking_masters m on m.id = ms.master_id
                            where ms.service_id = s.id and m.venue_id = v.id and m.active
                            and (strpos(lower(m.name), lower(?)) > 0 or strpos(lower(m.bio), lower(?)) > 0))))
                """;
        Object[] parameters = {
            district.strip(), organization.strip(), direction, direction, service.strip(), minPriceMinor, maxPriceMinor,
            specialist.strip(), specialty.strip(), specialist.strip(), specialist.strip(), specialty.strip(), specialty.strip(),
            query, query, query, query, query, query, limit, offset
        };
        // Both the page and total come from one statement snapshot, even when the offset exceeds the result size.
        String pageQuery = """
                with matching as materialized (
                    select v.id, v.sort_order from marketplace.booking_venues v
                """ + filters + """
                ), page as (
                    select id, sort_order from matching order by sort_order, id limit ? offset ?
                ), total as (select count(*) as count from matching)
                select total.count, venues.* from total
                left join page on true
                left join lateral (
                """ + VENUE_SELECT + """
                    where v.id = page.id
                ) venues on true
                order by page.sort_order, page.id
                """;
        return jdbc.query(pageQuery, rs -> {
            rs.next();
            long total = rs.getLong("count");
            List<Venue> venues = new ArrayList<>();
            do {
                if (rs.getString("id") != null) {
                    venues.add(mapVenue(rs, venues.size()));
                }
            } while (rs.next());
            return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                    .header("X-Total-Count", Long.toString(total)).body(venues);
        }, parameters);
    }

    @GetMapping("/venues/{venueId}")
    public ResponseEntity<VenueDetail> venue(@PathVariable UUID venueId) {
        Venue venue = jdbc.query(VENUE_SELECT + " where v.id = ? and (v.category <> 'HEALTH' or (v.is_open and v.is_synthetic and v.health_published))", BookingCatalogController::mapVenue, venueId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND",
                        "Venue is not available"));
        if ("HEALTH".equals(venue.category())) { slots.requireHealthCatalog(); }
        if ("BARBER".equals(venue.category())) {
            slots.requireBeauty();
        }
        if ("CLEANING".equals(venue.category())) {
            slots.requireHomeServices();
        }
        List<ServiceItem> services = jdbc.query("""
                select id, name, description, duration_minutes, price_minor, available, price_per_sqm_minor,
                    min_area_sqm, max_area_sqm, exists(select 1 from marketplace.health_categories c
                        where c.code = s.health_category and not c.medical) as wellness
                from marketplace.booking_services s where venue_id = ? and (not ? or available) order by sort_order, name
                """, (rs, row) -> new ServiceItem(rs.getString("id"), rs.getString("name"), rs.getString("description"),
                rs.getInt("duration_minutes"), rs.getLong("price_minor"), rs.getBoolean("available"),
                rs.getLong("price_per_sqm_minor"), rs.getObject("min_area_sqm", Integer.class),
                rs.getObject("max_area_sqm", Integer.class), rs.getBoolean("wellness")), venueId, "HEALTH".equals(venue.category()));
        Map<UUID, List<String>> serviceIds = new LinkedHashMap<>();
        jdbc.query("""
                select ms.master_id, ms.service_id from marketplace.booking_master_services ms
                join marketplace.booking_masters m on m.id = ms.master_id where m.venue_id = ?
                """, rs -> {
                    serviceIds.computeIfAbsent(rs.getObject(1, UUID.class), k -> new ArrayList<>()).add(rs.getString(2));
                }, venueId);
        List<Master> masters = jdbc.query("""
                select id, name, bio, emoji, tone from marketplace.booking_masters
                where venue_id = ? and active order by sort_order, name
                """, (rs, row) -> {
                    UUID id = rs.getObject("id", UUID.class);
                    return new Master(id.toString(), rs.getString("name"), rs.getString("bio"), rs.getString("emoji"),
                            rs.getString("tone"), serviceIds.getOrDefault(id, List.of()));
                }, venueId);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new VenueDetail(venue, services, masters));
    }

    /** Free start times for a service on a date (venue time zone), for one master or for any master who can do it. */
    @GetMapping("/slots")
    public ResponseEntity<List<BookingSlots.Slot>> slots(@RequestParam UUID venueId, @RequestParam UUID serviceId,
            @RequestParam(required = false) UUID masterId, @RequestParam LocalDate date) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(slots.freeSlots(venueId, serviceId, masterId, date));
    }
}
