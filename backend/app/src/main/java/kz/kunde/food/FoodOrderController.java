package kz.kunde.food;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.List;
import java.util.UUID;
import kz.kunde.food.FoodOrderService.OrderRequest;
import kz.kunde.food.FoodOrderService.OrderView;
import kz.kunde.food.FoodOrderService.Quote;
import kz.kunde.food.FoodOrderService.QuoteRequest;
import kz.kunde.food.FoodOrderService.RepeatResult;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Authenticated Food cart quote, checkout and order history. Every read and write is scoped to the caller. */
@RestController
@Validated
@RequestMapping("/api/v1/food")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodOrderController {
    private final FoodOrderService orders;
    private final ConsumerIdentityService identity;

    public FoodOrderController(FoodOrderService orders, ConsumerIdentityService identity) {
        this.orders = orders;
        this.identity = identity;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    @PostMapping("/cart/quote")
    public ResponseEntity<Quote> quote(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody QuoteRequest request) {
        UUID user = identity.get(principal).id();
        return noStore(HttpStatus.OK, orders.quote(request.restaurantId(), request.items(),
                request.fulfillmentType(), request.promoCode(), user));
    }

    @PostMapping("/orders")
    public ResponseEntity<OrderView> place(@AuthenticationPrincipal Jwt principal,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody OrderRequest request) {
        UUID user = identity.get(principal).id();
        var placed = orders.place(user, request, idempotencyKey);
        return noStore(placed.created() ? HttpStatus.CREATED : HttpStatus.OK, placed.order());
    }

    @GetMapping("/orders")
    public ResponseEntity<List<OrderView>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, orders.list(identity.get(principal).id(), limit, offset));
    }

    @GetMapping("/orders/{orderId}")
    public ResponseEntity<OrderView> get(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId) {
        return noStore(HttpStatus.OK, orders.get(identity.get(principal).id(), orderId));
    }

    @PostMapping("/orders/{orderId}/cancel")
    public ResponseEntity<OrderView> cancel(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId) {
        return noStore(HttpStatus.OK, orders.cancel(identity.get(principal).id(), orderId));
    }

    @PostMapping("/orders/{orderId}/items/{itemId}/decision")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<FoodOrderService.OrderView> decision(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId,
            @PathVariable UUID itemId, @Valid @RequestBody DecisionRequest request) {
        return ResponseEntity.ok().cacheControl(org.springframework.http.CacheControl.noStore())
                .body(orders.decideReplacement(identity.get(principal).id(), orderId, itemId, request.approve()));
    }

    public record DecisionRequest(@jakarta.validation.constraints.NotNull Boolean approve) {}

    @GetMapping("/orders/{orderId}/repeat")
    public ResponseEntity<RepeatResult> repeat(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId) {
        return noStore(HttpStatus.OK, orders.repeat(identity.get(principal).id(), orderId));
    }
}
