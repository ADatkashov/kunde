package kz.kunde.delivery;

import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.rides.RideRoutingController.Coordinates;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/deliveries")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class DeliveryController {
    private final ConsumerIdentityService identity;
    private final DeliveryService service;
    private final DeliveryDispatch dispatch;

    public DeliveryController(ConsumerIdentityService identity, DeliveryService service, DeliveryDispatch dispatch) {
        this.identity = identity;
        this.service = service;
        this.dispatch = dispatch;
    }

    @PostMapping("/quotes")
    public ResponseEntity<DeliveryService.Quote> quote(@AuthenticationPrincipal Jwt principal,
            @Valid @RequestBody QuoteRequest request) {
        return response(HttpStatus.CREATED, service.quote(identity.get(principal).id(), null, request));
    }

    @PostMapping
    public ResponseEntity<DeliveryService.Order> create(@AuthenticationPrincipal Jwt principal,
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody CreateRequest request) {
        var result = service.create(identity.get(principal).id(), null, key, request);
        return response(result.created() ? HttpStatus.CREATED : HttpStatus.OK, result.order());
    }

    @GetMapping
    public ResponseEntity<List<DeliveryService.Order>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return response(HttpStatus.OK, service.list(identity.get(principal).id(), null, limit, offset));
    }

    @GetMapping("/{id}")
    public ResponseEntity<DeliveryService.Order> detail(@AuthenticationPrincipal Jwt principal, @PathVariable("id") UUID id) {
        return response(HttpStatus.OK, service.get(identity.get(principal).id(), null, id));
    }

    @PostMapping("/{id}/cancel")
    public ResponseEntity<DeliveryService.Order> cancel(@AuthenticationPrincipal Jwt principal, @PathVariable("id") UUID id) {
        return response(HttpStatus.OK, service.cancel(identity.get(principal).id(), null, id));
    }

    @PostMapping("/{id}/dispatch")
    public ResponseEntity<DeliveryService.Order> dispatch(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        UUID sender = identity.get(principal).id();
        dispatch.search(sender, null, id);
        return response(HttpStatus.OK, service.get(sender, null, id));
    }

    @PostMapping("/{id}/handoff-code")
    public ResponseEntity<DeliveryDispatch.HandoffCode> handoffCode(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID id) {
        return response(HttpStatus.CREATED, dispatch.issueCode(identity.get(principal).id(), null, id));
    }

    private static <T> ResponseEntity<T> response(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    public enum ParcelType { DOCUMENTS, SMALL_PARCEL, MEDIUM_PARCEL, PERSONAL_ITEMS, OTHER_ALLOWED_GOODS }

    public record QuoteRequest(@NotNull ParcelType parcelType, @Min(1) @Max(50000) int weightGrams,
            @Min(1) @Max(200) int lengthCm, @Min(1) @Max(200) int widthCm, @Min(1) @Max(200) int heightCm,
            @Valid @NotNull Coordinates pickup, @Valid @NotNull Coordinates destination) {}

    public record CreateRequest(@NotNull UUID quoteId, @NotBlank @Size(max = 240) String pickupAddress,
            @NotBlank @Size(max = 240) String destinationAddress, @NotBlank @Size(max = 120) String recipientName,
            @NotNull @Pattern(regexp = "[+][1-9][0-9]{7,14}") String recipientPhone,
            @NotBlank @Size(max = 300) String description, @Size(max = 300) String courierNote,
            @AssertTrue boolean allowedGoodsConfirmed) {}
}
