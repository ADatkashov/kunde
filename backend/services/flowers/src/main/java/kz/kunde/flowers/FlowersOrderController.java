package kz.kunde.flowers;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import kz.kunde.flowers.FlowersOrderService.ItemRequest;
import kz.kunde.flowers.FlowersOrderService.OrderRequest;
import kz.kunde.flowers.FlowersOrderService.OrderView;
import kz.kunde.flowers.FlowersOrderService.Quote;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
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

/** Authenticated Flowers &amp; Gifts cart quote, checkout and order history. Every read and write is scoped to the caller. */
@RestController
@Validated
@RequestMapping("/api/v1/flowers")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class FlowersOrderController {
    private final FlowersOrderService orders;
    private final ConsumerIdentityService identity;
    private final FeatureToggles toggles;

    public FlowersOrderController(FlowersOrderService orders, ConsumerIdentityService identity, FeatureToggles toggles) {
        this.orders = orders;
        this.identity = identity;
        this.toggles = toggles;
    }

    private void requireOn() {
        if (!toggles.enabled(Feature.FLOWERS)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "FLOWERS_DISABLED", "Flowers and gifts is unavailable");
        }
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    public record ItemBody(@NotNull UUID productId, @Min(1) @Max(20) int quantity) {}

    public record QuoteBody(@NotNull UUID shopId, @NotEmpty @Size(max = 20) List<@Valid ItemBody> items, @NotNull String deliveryMode,
            Instant scheduledFrom) {}

    public record OrderBody(@NotNull UUID shopId, @NotEmpty @Size(max = 20) List<@Valid ItemBody> items, @NotNull String deliveryMode,
            Instant scheduledFrom, @Size(max = 80) String addressLabel, @NotNull @Size(min = 5, max = 500) String addressText,
            @Size(max = 80) String recipientName, @Size(max = 300) String cardText, @Size(max = 300) String comment,
            @NotNull Long expectedTotalMinor) {}

    private static List<ItemRequest> items(List<ItemBody> body) {
        return body.stream().map(i -> new ItemRequest(i.productId(), i.quantity())).toList();
    }

    @PostMapping("/cart/quote")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<Quote> quote(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody QuoteBody body) {
        requireOn();
        identity.get(principal);
        return noStore(HttpStatus.OK, orders.quote(body.shopId(), items(body.items()), body.deliveryMode(), body.scheduledFrom()));
    }

    @PostMapping("/orders")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<OrderView> place(@AuthenticationPrincipal Jwt principal,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey, @Valid @RequestBody OrderBody body) {
        requireOn();
        UUID user = identity.get(principal).id();
        var placed = orders.place(user, new OrderRequest(body.shopId(), items(body.items()), body.deliveryMode(), body.scheduledFrom(),
                body.addressLabel(), body.addressText(), body.recipientName(), body.cardText(), body.comment(), body.expectedTotalMinor()),
                idempotencyKey);
        return noStore(placed.created() ? HttpStatus.CREATED : HttpStatus.OK, placed.order());
    }

    @GetMapping("/orders")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<List<OrderView>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        requireOn();
        return noStore(HttpStatus.OK, orders.list(identity.get(principal).id(), limit, offset));
    }

    @GetMapping("/orders/{orderId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<OrderView> get(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId) {
        requireOn();
        return noStore(HttpStatus.OK, orders.get(identity.get(principal).id(), orderId));
    }

    @PostMapping("/orders/{orderId}/cancel")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<OrderView> cancel(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId) {
        requireOn();
        return noStore(HttpStatus.OK, orders.cancel(identity.get(principal).id(), orderId));
    }
}
