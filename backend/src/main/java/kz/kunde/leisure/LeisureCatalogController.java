package kz.kunde.leisure;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.leisure.LeisureCatalogService.*;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/** Public read-only Leisure catalog. Empty while the Leisure switch is off. */
@RestController
@Validated
@RequestMapping("/api/v1/leisure")
public class LeisureCatalogController {
    private final LeisureCatalogService catalog;

    public LeisureCatalogController(LeisureCatalogService catalog) { this.catalog = catalog; }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    @GetMapping("/categories")
    ResponseEntity<List<Category>> categories() { return ok(catalog.categories()); }

    @GetMapping("/home")
    ResponseEntity<Map<String, List<Card>>> home(@RequestParam(required = false) Double lat, @RequestParam(required = false) Double lng) {
        return ok(catalog.home(lat, lng));
    }

    @GetMapping("/events")
    ResponseEntity<List<Card>> events(@RequestParam(required = false) String q, @RequestParam(required = false) String category,
            @RequestParam(required = false) String district, @RequestParam(required = false) LocalDate date,
            @RequestParam(required = false) LocalTime timeFrom, @RequestParam(required = false) LocalTime timeTo,
            @RequestParam(required = false) @Min(0) Long minPrice, @RequestParam(required = false) @Min(0) Long maxPrice,
            @RequestParam(required = false) @Min(0) @Max(21) Integer age, @RequestParam(required = false) @Min(1) @Max(100) Integer guests,
            @RequestParam(defaultValue = "false") boolean available, @RequestParam(required = false) Boolean family,
            @RequestParam(required = false) @Min(1) @Max(5) Double minRating, @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lng, @RequestParam(required = false) @Min(1) @Max(200) Double radiusKm,
            @RequestParam(defaultValue = "time") String sort, @RequestParam(required = false) String preset,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        if (!List.of("time", "price", "popular", "distance").contains(sort)) { sort = "time"; }
        return ok(catalog.search(new Search(q, category, district, date, timeFrom, timeTo, minPrice, maxPrice, age, guests, available, family, minRating,
                lat, lng, radiusKm, sort, preset, limit, offset)));
    }

    @GetMapping("/events/{id}")
    ResponseEntity<Detail> event(@PathVariable UUID id) { return ok(catalog.detail(id)); }

    @GetMapping("/events/{id}/sessions")
    ResponseEntity<List<SessionView>> sessions(@PathVariable UUID id, @RequestParam(required = false) LocalDate date,
            @RequestParam(defaultValue = "14") @Min(1) @Max(31) int days) {
        return ok(catalog.sessions(id, date, days));
    }

    @GetMapping("/events/{id}/reviews")
    ResponseEntity<List<ReviewView>> reviews(@PathVariable UUID id, @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(catalog.reviews(id, limit, offset));
    }

    @GetMapping("/sessions/{id}/seats")
    ResponseEntity<List<Seat>> seats(@PathVariable UUID id) { return ok(catalog.seats(id)); }
}
