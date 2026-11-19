package kz.kunde.auto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.auto.AutoService.AutoBooking;
import kz.kunde.auto.AutoService.Quote;
import kz.kunde.auto.AutoService.Vehicle;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/** Authenticated consumer API: vehicles, quotes, idempotent booking, history, reschedule, cancel, price decision. */
@RestController
@Validated
@RequestMapping("/api/v1/auto")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoController {
    private final AutoService auto;
    private final ConsumerIdentityService identity;

    public AutoController(AutoService auto, ConsumerIdentityService identity) {
        this.auto = auto;
        this.identity = identity;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    private UUID user(Jwt principal) { return identity.get(principal).id(); }

    public record VehicleBody(String make, String model, Integer year, String plate) {}

    public record VehicleUpdate(String make, String model, Integer year, String plate, @NotNull Long version) {}

    public record BookBody(@NotNull UUID quoteId) {}

    public record RescheduleBody(@NotNull OffsetDateTime startsAt) {}

    public record PriceDecisionBody(@NotNull Boolean approve) {}

    @GetMapping("/vehicles")
    public ResponseEntity<List<Vehicle>> vehicles(@AuthenticationPrincipal Jwt p) {
        return noStore(HttpStatus.OK, auto.vehicles(user(p)));
    }

    @PostMapping("/vehicles")
    public ResponseEntity<Vehicle> addVehicle(@AuthenticationPrincipal Jwt p, @Valid @RequestBody VehicleBody b) {
        return noStore(HttpStatus.CREATED, auto.addVehicle(user(p), new AutoService.VehicleRequest(b.make(), b.model(), b.year(), b.plate())));
    }

    @PutMapping("/vehicles/{id}")
    public ResponseEntity<Vehicle> updateVehicle(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @Valid @RequestBody VehicleUpdate b) {
        return noStore(HttpStatus.OK, auto.updateVehicle(user(p), id, new AutoService.VehicleRequest(b.make(), b.model(), b.year(), b.plate()), b.version()));
    }

    @DeleteMapping("/vehicles/{id}")
    public ResponseEntity<Void> archiveVehicle(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        auto.archiveVehicle(user(p), id);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PostMapping("/quotes")
    public ResponseEntity<Quote> quote(@AuthenticationPrincipal Jwt p, @RequestBody AutoService.QuoteRequest r) {
        return noStore(HttpStatus.CREATED, auto.quote(user(p), r));
    }

    @PostMapping("/bookings")
    public ResponseEntity<AutoBooking> book(@AuthenticationPrincipal Jwt p, @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody BookBody b) {
        var booked = auto.book(user(p), b.quoteId(), key);
        return noStore(booked.created() ? HttpStatus.CREATED : HttpStatus.OK, booked.booking());
    }

    @GetMapping("/bookings")
    public ResponseEntity<List<AutoBooking>> list(@AuthenticationPrincipal Jwt p, @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, auto.list(user(p), limit, offset));
    }

    @GetMapping("/bookings/{id}")
    public ResponseEntity<AutoBooking> get(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        return noStore(HttpStatus.OK, auto.get(user(p), id));
    }

    @PostMapping("/bookings/{id}/cancel")
    public ResponseEntity<AutoBooking> cancel(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        return noStore(HttpStatus.OK, auto.cancel(user(p), id));
    }

    @PostMapping("/bookings/{id}/reschedule")
    public ResponseEntity<AutoBooking> reschedule(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @Valid @RequestBody RescheduleBody b) {
        return noStore(HttpStatus.OK, auto.reschedule(user(p), id, b.startsAt()));
    }

    @PostMapping("/bookings/{id}/price-decision")
    public ResponseEntity<AutoBooking> priceDecision(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @Valid @RequestBody PriceDecisionBody b) {
        return noStore(HttpStatus.OK, auto.decidePrice(user(p), id, b.approve()));
    }
}
