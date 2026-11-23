package kz.kunde.booking;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.sql.Array;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
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

/**
 * Public Beauty discovery: salons with server-side filtering, sorting and pagination, salon and service details,
 * and active promotions. Rating and review count are always calculated from published reviews. Hidden while BEAUTY is off.
 */
@RestController
@Validated
@RequestMapping("/api/v1/beauty")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BeautySalonsController {
    public record Salon(String id, String slug, String name, String addressText, String emoji, String imageUrl, boolean open,
            List<String> categories, Double latitude, Double longitude, boolean verified, Double rating, long reviewCount,
            Long fromPriceMinor, Integer discountPercent, Long distanceMeters) {}

    public record ServiceItem(String id, String name, String description, int durationMinutes, long priceMinor, boolean priceFrom,
            String categoryCode, List<String> tags) {}

    public record Master(String id, String name, String bio, String specialty, Integer experienceYears, Double rating,
            long reviewCount, List<String> serviceIds, OffsetDateTime nextSlotAt) {}

    public record Review(String id, String authorName, int rating, String comment, String masterName, String serviceName,
            OffsetDateTime createdAt) {}

    public record SalonDetail(Salon salon, String description, String phone, String cancellationPolicy, List<String> gallery,
            List<ServiceItem> services, List<Master> masters, List<Review> reviews) {}

    public record ServiceDetail(ServiceItem service, List<String> includes, String preparation, String cancellationPolicy,
            List<String> gallery, Salon salon, List<Master> masters) {}

    public record Promotion(String id, String venueId, String title, int percent, OffsetDateTime endsAt) {}

    public record Promotions(Integer maxPercent, List<Promotion> items) {}

    private static final String ACTIVE_DISCOUNT = """
            (select max(pr.percent) from marketplace.beauty_promotions pr
              where pr.active and now() >= pr.starts_at and now() < pr.ends_at and (pr.venue_id = v.id or pr.venue_id is null))""";

    private static final String SALON_SELECT = """
            select v.id, v.slug, v.name, v.description, v.address_text, v.emoji, v.image_url, v.is_open, v.sort_order,
                   p.category_codes, p.latitude, p.longitude, p.verified, p.phone, p.cancellation_policy, p.gallery_urls,
                   (select round(avg(r.rating)::numeric, 1) from marketplace.beauty_reviews r where r.venue_id = v.id and r.status = 'PUBLISHED') as rating,
                   (select count(*) from marketplace.beauty_reviews r where r.venue_id = v.id and r.status = 'PUBLISHED') as review_count,
                   (select min(s.price_minor) from marketplace.booking_services s where s.venue_id = v.id and s.available) as from_price,
            """ + ACTIVE_DISCOUNT + """
             as discount,
                   case when ?::float8 is null or ?::float8 is null or p.latitude is null then null
                        else 2 * 6371000 * asin(sqrt(least(1, power(sin(radians((p.latitude::float8 - ?::float8) / 2)), 2)
                            + cos(radians(?::float8)) * cos(radians(p.latitude::float8))
                            * power(sin(radians((p.longitude::float8 - ?::float8) / 2)), 2)))) end as distance
            from marketplace.booking_venues v join marketplace.beauty_salon_profiles p on p.venue_id = v.id
            """;

    private final JdbcTemplate db;
    private final FeatureToggles toggles;
    private final BookingSlots slots;

    public BeautySalonsController(JdbcTemplate db, FeatureToggles toggles, BookingSlots slots) {
        this.db = db;
        this.toggles = toggles;
        this.slots = slots;
    }

    private void requireEnabled() {
        if (!toggles.enabled(Feature.BEAUTY)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BEAUTY_DISABLED", "Beauty is unavailable");
        }
    }

    private static List<String> array(ResultSet rs, String column) throws SQLException {
        Array value = rs.getArray(column);
        return value == null ? List.of() : List.of((String[]) value.getArray());
    }

    private static Salon mapSalon(ResultSet rs, int row) throws SQLException {
        Double rating = rs.getObject("rating", java.math.BigDecimal.class) == null ? null : rs.getBigDecimal("rating").doubleValue();
        Double distance = rs.getObject("distance", Double.class);
        return new Salon(rs.getString("id"), rs.getString("slug"), rs.getString("name"), rs.getString("address_text"),
                rs.getString("emoji"), rs.getString("image_url"), rs.getBoolean("is_open"), array(rs, "category_codes"),
                rs.getObject("latitude", java.math.BigDecimal.class) == null ? null : rs.getBigDecimal("latitude").doubleValue(),
                rs.getObject("longitude", java.math.BigDecimal.class) == null ? null : rs.getBigDecimal("longitude").doubleValue(),
                rs.getBoolean("verified"), rating, rs.getLong("review_count"), rs.getObject("from_price", Long.class),
                rs.getObject("discount", Integer.class), distance == null ? null : Math.round(distance));
    }

    /**
     * {@code filter}: ALL (default order), NEARBY (by distance; without coordinates falls back to the default order),
     * RATING (best rated first) or PROMO (only salons with an active promotion, biggest discount first).
     */
    @GetMapping("/salons")
    public ResponseEntity<List<Salon>> salons(
            @RequestParam(defaultValue = "ALL") @Pattern(regexp = "ALL|NEARBY|RATING|PROMO") String filter,
            @RequestParam(required = false) @Pattern(regexp = "[A-Z][A-Z0-9_]{1,31}") String category,
            @RequestParam(required = false) @Size(max = 80) String q,
            @RequestParam(required = false) @Min(0) Long minPriceMinor,
            @RequestParam(required = false) @Min(0) Long maxPriceMinor,
            @RequestParam(required = false) @DecimalMin("-90") @DecimalMax("90") Double lat,
            @RequestParam(required = false) @DecimalMin("-180") @DecimalMax("180") Double lng,
            @RequestParam(required = false) @Min(100) @Max(100000) Integer maxDistanceMeters,
            @RequestParam(defaultValue = "false") boolean verifiedOnly,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        requireEnabled();
        if ((lat == null) != (lng == null)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "LOCATION_INVALID", "lat and lng must be given together");
        }
        String text = q == null || q.isBlank() ? null : "%" + q.trim().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        String order = switch (filter) {
            case "NEARBY" -> "distance asc nulls last, sort_order, name";
            case "RATING" -> "rating desc nulls last, review_count desc, name";
            case "PROMO" -> "discount desc, name";
            default -> "sort_order, name";
        };
        long[] total = {0};
        List<Salon> salons = db.query("select t.*, count(*) over() as total from (" + SALON_SELECT + """
                where v.category = 'BARBER' and v.is_open
                ) t where (?::text is null or ? = any(t.category_codes))
                  and (?::text is null or t.name ilike ? or t.address_text ilike ?
                       or exists (select 1 from marketplace.booking_services s where s.venue_id = t.id and s.available and s.name ilike ?)
                       or exists (select 1 from marketplace.booking_masters m where m.venue_id = t.id and m.active and m.name ilike ?))
                  and (?::bigint is null or t.from_price >= ?) and (?::bigint is null or t.from_price <= ?)
                  and (?::int is null or t.distance <= ?) and (not ? or t.verified) and (? <> 'PROMO' or t.discount is not null)
                order by """ + " " + order + " limit ? offset ?", (rs, row) -> {
            total[0] = rs.getLong("total");
            return mapSalon(rs, row);
        }, lat, lng, lat, lat, lng, category, category, text, text, text, text, text, minPriceMinor, minPriceMinor,
                maxPriceMinor, maxPriceMinor, maxDistanceMeters, maxDistanceMeters, verifiedOnly, filter, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).header("X-Total-Count", Long.toString(total[0])).body(salons);
    }

    private static ServiceItem mapService(ResultSet rs, int row) throws SQLException {
        return new ServiceItem(rs.getString("id"), rs.getString("name"), rs.getString("description"), rs.getInt("duration_minutes"),
                rs.getLong("price_minor"), rs.getBoolean("price_from"), rs.getString("category_code"), array(rs, "tags"));
    }

    private static final String SERVICE_SELECT = """
            select s.id, s.name, s.description, s.duration_minutes, s.price_minor, coalesce(sp.price_from, false) as price_from,
                   sp.category_code, coalesce(sp.tags, '{}') as tags
            from marketplace.booking_services s left join marketplace.beauty_service_profiles sp on sp.service_id = s.id
            """;

    private List<Master> masters(UUID venueId, UUID serviceId, boolean withNextSlot) {
        List<Master> masters = db.query("""
                select m.id, m.name, m.bio, m.specialty, m.experience_years,
                       (select round(avg(r.rating)::numeric, 1) from marketplace.beauty_reviews r where r.master_id = m.id and r.status = 'PUBLISHED') as rating,
                       (select count(*) from marketplace.beauty_reviews r where r.master_id = m.id and r.status = 'PUBLISHED') as review_count,
                       array(select ms.service_id::text from marketplace.booking_master_services ms where ms.master_id = m.id order by 1) as service_ids
                from marketplace.booking_masters m
                where m.venue_id = ? and m.active and (?::uuid is null or exists (
                    select 1 from marketplace.booking_master_services x where x.master_id = m.id and x.service_id = ?::uuid))
                order by m.sort_order, m.name
                """, (rs, row) -> new Master(rs.getString("id"), rs.getString("name"), rs.getString("bio"), rs.getString("specialty"),
                rs.getObject("experience_years", Integer.class),
                rs.getObject("rating", java.math.BigDecimal.class) == null ? null : rs.getBigDecimal("rating").doubleValue(),
                rs.getLong("review_count"), array(rs, "service_ids"), null), venueId, serviceId, serviceId);
        if (!withNextSlot || serviceId == null) {
            return masters;
        }
        return masters.stream().map(m -> new Master(m.id(), m.name(), m.bio(), m.specialty(), m.experienceYears(), m.rating(),
                m.reviewCount(), m.serviceIds(), nextSlot(venueId, serviceId, UUID.fromString(m.id())))).toList();
    }

    /** The earliest free start of a master for a service within the booking horizon, or null. */
    private OffsetDateTime nextSlot(UUID venueId, UUID serviceId, UUID masterId) {
        LocalDate day = LocalDate.now(slots.venue(venueId).zone());
        for (int i = 0; i < 7; i++) {
            var free = slots.freeSlots(venueId, serviceId, masterId, day.plusDays(i));
            if (!free.isEmpty()) {
                return free.getFirst().startsAt();
            }
        }
        return null;
    }

    private Salon salon(UUID id) {
        return db.query(SALON_SELECT + " where v.id = ? and v.category = 'BARBER' and v.is_open", BeautySalonsController::mapSalon,
                null, null, null, null, null, id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SALON_NOT_FOUND", "Salon is not available"));
    }

    @GetMapping("/salons/{id}")
    public ResponseEntity<SalonDetail> salonDetail(@PathVariable UUID id) {
        requireEnabled();
        Salon salon = salon(id);
        var extra = db.queryForMap("""
                select v.description, p.phone, p.cancellation_policy from marketplace.booking_venues v
                join marketplace.beauty_salon_profiles p on p.venue_id = v.id where v.id = ?
                """, id);
        List<String> gallery = db.query("select unnest(gallery_urls) from marketplace.beauty_salon_profiles where venue_id = ?",
                (rs, row) -> rs.getString(1), id);
        List<ServiceItem> services = db.query(SERVICE_SELECT + " where s.venue_id = ? and s.available order by s.sort_order, s.name",
                BeautySalonsController::mapService, id);
        List<Review> reviews = db.query("""
                select r.id, r.author_name, r.rating, r.comment, m.name as master_name, s.name as service_name, r.created_at
                from marketplace.beauty_reviews r left join marketplace.booking_masters m on m.id = r.master_id
                left join marketplace.booking_services s on s.id = r.service_id
                where r.venue_id = ? and r.status = 'PUBLISHED' order by r.created_at desc, r.id limit 20
                """, (rs, row) -> new Review(rs.getString("id"), rs.getString("author_name"), rs.getInt("rating"), rs.getString("comment"),
                rs.getString("master_name"), rs.getString("service_name"), rs.getObject("created_at", OffsetDateTime.class)), id);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new SalonDetail(salon, (String) extra.get("description"),
                (String) extra.get("phone"), (String) extra.get("cancellation_policy"), gallery, services, masters(id, null, false), reviews));
    }

    @GetMapping("/services/{id}")
    public ResponseEntity<ServiceDetail> serviceDetail(@PathVariable UUID id) {
        requireEnabled();
        UUID venueId = db.query("select s.venue_id from marketplace.booking_services s join marketplace.beauty_salon_profiles p on p.venue_id = s.venue_id where s.id = ? and s.available",
                (rs, row) -> rs.getObject(1, UUID.class), id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SERVICE_NOT_FOUND", "Service is not available"));
        ServiceItem service = db.query(SERVICE_SELECT + " where s.id = ?", BeautySalonsController::mapService, id).getFirst();
        var profile = db.queryForMap("""
                select coalesce(sp.includes, '{}') as includes, coalesce(sp.preparation, '') as preparation,
                       coalesce(sp.gallery_urls, '{}') as gallery, p.cancellation_policy
                from marketplace.booking_services s join marketplace.beauty_salon_profiles p on p.venue_id = s.venue_id
                left join marketplace.beauty_service_profiles sp on sp.service_id = s.id where s.id = ?
                """, id);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new ServiceDetail(service, strings(profile.get("includes")),
                (String) profile.get("preparation"), (String) profile.get("cancellation_policy"), strings(profile.get("gallery")),
                salon(venueId), masters(venueId, id, true)));
    }

    private static List<String> strings(Object value) throws IllegalStateException {
        try {
            return value == null ? List.of() : List.of((String[]) ((Array) value).getArray());
        } catch (SQLException e) {
            throw new IllegalStateException(e);
        }
    }

    @GetMapping("/promotions")
    public ResponseEntity<Promotions> promotions() {
        requireEnabled();
        List<Promotion> items = db.query("""
                select pr.id, pr.venue_id, pr.title, pr.percent, pr.ends_at from marketplace.beauty_promotions pr
                where pr.active and now() >= pr.starts_at and now() < pr.ends_at
                order by pr.percent desc, pr.ends_at, pr.id limit 50
                """, (rs, row) -> new Promotion(rs.getString("id"), rs.getString("venue_id"), rs.getString("title"), rs.getInt("percent"),
                rs.getObject("ends_at", OffsetDateTime.class)));
        Integer max = items.isEmpty() ? null : items.getFirst().percent();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new Promotions(max, items));
    }
}
