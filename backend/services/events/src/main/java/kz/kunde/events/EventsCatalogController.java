package kz.kunde.events;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.leisure.LeisureCatalogService;
import kz.kunde.leisure.LeisureCatalogService.*;
import kz.kunde.platform.ApiException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/**
 * Public read-only catalog of KUNDE Events &amp; Tickets. It is a product view over the ONE ticketing engine of {@code kz.kunde.leisure}
 * (sessions, seat maps, holds, orders, QR tickets, validation): no second inventory exists, so a seat can never be sold twice. Purchases use the
 * shared {@code /api/v1/leisure/sessions/{id}/holds} and {@code /orders}; they are gated by the EVENTS switch for event categories.
 * Empty while the EVENTS switch is off; Leisure activities are never listed here.
 */
@RestController
@Validated
@RequestMapping("/api/v1/events")
public class EventsCatalogController {
    private static final String PRODUCT = LeisureCatalogService.EVENTS;
    private final LeisureCatalogService catalog;

    public EventsCatalogController(LeisureCatalogService catalog) { this.catalog = catalog; }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    @GetMapping("/categories")
    ResponseEntity<List<Category>> categories() { return ok(catalog.categories(PRODUCT)); }

    @GetMapping("/home")
    ResponseEntity<Map<String, List<Card>>> home(@RequestParam(required = false) Double lat, @RequestParam(required = false) Double lng) {
        return ok(catalog.home(lat, lng, PRODUCT));
    }

    @GetMapping
    ResponseEntity<List<Card>> list(@RequestParam(required = false) String q, @RequestParam(required = false) String category,
            @RequestParam(required = false) String district, @RequestParam(required = false) LocalDate date,
            @RequestParam(required = false) LocalTime timeFrom, @RequestParam(required = false) LocalTime timeTo,
            @RequestParam(required = false) @Min(0) Long minPrice, @RequestParam(required = false) @Min(0) Long maxPrice,
            @RequestParam(required = false) @Min(0) @Max(21) Integer age, @RequestParam(defaultValue = "false") boolean available,
            @RequestParam(required = false) Boolean family, @RequestParam(required = false) Double lat, @RequestParam(required = false) Double lng,
            @RequestParam(required = false) @Min(1) @Max(200) Double radiusKm, @RequestParam(defaultValue = "time") String sort,
            @RequestParam(required = false) String preset, @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        if (!List.of("time", "price", "popular", "distance").contains(sort)) { sort = "time"; }
        return ok(catalog.search(new Search(q, category, district, date, timeFrom, timeTo, minPrice, maxPrice, age, null, available, family, null,
                lat, lng, radiusKm, sort, preset, limit, offset), PRODUCT));
    }

    /** One canonical card: an id that belongs to Leisure is not an event (404), so the same offer is never presented as both products. */
    @GetMapping("/{id}")
    ResponseEntity<Detail> detail(@PathVariable UUID id) {
        Detail d = catalog.detail(id);
        if (!PRODUCT.equals(d.product())) { throw new ApiException(HttpStatus.NOT_FOUND, "EVENT_NOT_FOUND", "Event not found"); }
        return ok(d);
    }

    @GetMapping("/{id}/sessions")
    ResponseEntity<List<SessionView>> sessions(@PathVariable UUID id, @RequestParam(required = false) LocalDate date,
            @RequestParam(defaultValue = "30") @Min(1) @Max(31) int days) {
        return ok(catalog.sessions(id, date, days));
    }
}
