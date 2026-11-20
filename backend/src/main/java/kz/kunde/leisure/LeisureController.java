package kz.kunde.leisure;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.leisure.LeisureOrderService.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/** Authenticated consumer API: holds, idempotent orders, tickets, cancellation, reviews, favourites, complaints. */
@RestController
@Validated
@RequestMapping("/api/v1/leisure")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class LeisureController {
    private final LeisureOrderService orders;
    private final LeisureCatalogService catalog;
    private final ConsumerIdentityService identity;

    public LeisureController(LeisureOrderService orders, LeisureCatalogService catalog, ConsumerIdentityService identity) {
        this.orders = orders;
        this.catalog = catalog;
        this.identity = identity;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    private UUID user(Jwt principal) { return identity.get(principal).id(); }

    @PostMapping("/sessions/{sessionId}/holds")
    ResponseEntity<HoldView> hold(@AuthenticationPrincipal Jwt p, @PathVariable UUID sessionId, @RequestBody HoldRequest body) {
        return noStore(HttpStatus.CREATED, orders.hold(user(p), sessionId, body));
    }

    @GetMapping("/holds/{id}")
    ResponseEntity<HoldView> getHold(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) { return noStore(HttpStatus.OK, orders.getHold(user(p), id)); }

    @DeleteMapping("/holds/{id}")
    ResponseEntity<Void> release(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        orders.releaseHold(user(p), id);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PostMapping("/orders")
    ResponseEntity<OrderView> place(@AuthenticationPrincipal Jwt p, @RequestHeader(value = "Idempotency-Key", required = false) String key, @RequestBody PlaceBody body) {
        Placed placed = orders.place(user(p), key, body);
        return noStore(placed.created() ? HttpStatus.CREATED : HttpStatus.OK, placed.order());
    }

    @GetMapping("/orders")
    ResponseEntity<List<OrderView>> list(@AuthenticationPrincipal Jwt p, @RequestParam(defaultValue = "upcoming") @Pattern(regexp = "upcoming|completed|cancelled") String scope,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, orders.list(user(p), scope, limit, offset));
    }

    @GetMapping("/orders/{id}")
    ResponseEntity<OrderView> get(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) { return noStore(HttpStatus.OK, orders.order(user(p), id)); }

    @PostMapping("/orders/{id}/cancel")
    ResponseEntity<OrderView> cancel(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) { return noStore(HttpStatus.OK, orders.cancel(user(p), id)); }

    @PostMapping("/orders/{id}/review")
    ResponseEntity<LeisureCatalogService.ReviewView> review(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @RequestBody ReviewBody body) {
        return noStore(HttpStatus.CREATED, orders.review(user(p), id, body));
    }

    @GetMapping("/favorites")
    ResponseEntity<List<String>> favorites(@AuthenticationPrincipal Jwt p) { return noStore(HttpStatus.OK, orders.favoriteIds(user(p))); }

    @PutMapping("/favorites/{eventId}")
    ResponseEntity<Void> favorite(@AuthenticationPrincipal Jwt p, @PathVariable UUID eventId) {
        orders.favorite(user(p), eventId, true);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @DeleteMapping("/favorites/{eventId}")
    ResponseEntity<Void> unfavorite(@AuthenticationPrincipal Jwt p, @PathVariable UUID eventId) {
        orders.favorite(user(p), eventId, false);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PostMapping("/complaints")
    ResponseEntity<Map<String, Object>> complain(@AuthenticationPrincipal Jwt p, @RequestBody ComplaintBody body) {
        return noStore(HttpStatus.CREATED, orders.complain(user(p), body));
    }
}
