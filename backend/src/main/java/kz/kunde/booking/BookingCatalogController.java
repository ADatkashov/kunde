package kz.kunde.booking;

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
            boolean available, long pricePerSqmMinor, Integer minAreaSqm, Integer maxAreaSqm) {}

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
        List<Venue> list = jdbc.query(VENUE_SELECT + " where v.category = ? order by v.is_open desc, v.sort_order, v.name",
                BookingCatalogController::mapVenue, category);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    @GetMapping("/venues/{venueId}")
    public ResponseEntity<VenueDetail> venue(@PathVariable UUID venueId) {
        Venue venue = jdbc.query(VENUE_SELECT + " where v.id = ?", BookingCatalogController::mapVenue, venueId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND",
                        "Venue is not available"));
        List<ServiceItem> services = jdbc.query("""
                select id, name, description, duration_minutes, price_minor, available, price_per_sqm_minor, min_area_sqm, max_area_sqm
                from marketplace.booking_services where venue_id = ? order by sort_order, name
                """, (rs, row) -> new ServiceItem(rs.getString("id"), rs.getString("name"), rs.getString("description"),
                rs.getInt("duration_minutes"), rs.getLong("price_minor"), rs.getBoolean("available"),
                rs.getLong("price_per_sqm_minor"), rs.getObject("min_area_sqm", Integer.class),
                rs.getObject("max_area_sqm", Integer.class)), venueId);
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
