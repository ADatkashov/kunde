package kz.kunde.delivery;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.List;
import java.util.UUID;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.partner.PartnerService;
import kz.kunde.platform.ApiException;
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
@RequestMapping("/api/v1/partner/partners/{partnerId}/deliveries")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class DeliveryPartnerController {
    private final PartnerService partners;
    private final DeliveryService deliveries;
    private final DeliveryDispatch dispatch;

    public DeliveryPartnerController(PartnerService partners, DeliveryService deliveries, DeliveryDispatch dispatch) {
        this.partners = partners;
        this.deliveries = deliveries;
        this.dispatch = dispatch;
    }

    @PostMapping("/quotes")
    public ResponseEntity<DeliveryService.Quote> quote(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @Valid @RequestBody DeliveryController.QuoteRequest request) {
        return noStore(HttpStatus.CREATED, deliveries.quote(actor(principal, partnerId), partnerId, request));
    }

    @PostMapping
    public ResponseEntity<DeliveryService.Order> create(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody DeliveryController.CreateRequest request) {
        var result = deliveries.create(actor(principal, partnerId), partnerId, key, request);
        return noStore(result.created() ? HttpStatus.CREATED : HttpStatus.OK, result.order());
    }

    @GetMapping
    public ResponseEntity<List<DeliveryService.Order>> list(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, deliveries.list(actor(principal, partnerId), partnerId, limit, offset));
    }

    @GetMapping("/{id}")
    public ResponseEntity<DeliveryService.Order> detail(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @PathVariable UUID id) {
        return noStore(HttpStatus.OK, deliveries.get(actor(principal, partnerId), partnerId, id));
    }

    @GetMapping("/totals")
    public ResponseEntity<List<DeliveryService.ShipmentTotal>> totals(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId) {
        actor(principal, partnerId);
        return noStore(HttpStatus.OK, deliveries.totals(partnerId));
    }

    @PostMapping("/{id}/cancel")
    public ResponseEntity<DeliveryService.Order> cancel(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @PathVariable UUID id) {
        return noStore(HttpStatus.OK, deliveries.cancel(actor(principal, partnerId), partnerId, id));
    }

    @PostMapping("/{id}/dispatch")
    public ResponseEntity<DeliveryService.Order> dispatch(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @PathVariable UUID id) {
        UUID actor = actor(principal, partnerId);
        dispatch.search(actor, partnerId, id);
        return noStore(HttpStatus.OK, deliveries.get(actor, partnerId, id));
    }

    @PostMapping("/{id}/handoff-code")
    public ResponseEntity<DeliveryDispatch.HandoffCode> handoffCode(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @PathVariable UUID id) {
        return noStore(HttpStatus.CREATED, dispatch.issueCode(actor(principal, partnerId), partnerId, id));
    }

    private UUID actor(Jwt principal, UUID partnerId) {
        UUID actor = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        partners.requireProcessing(actor, partnerId);
        return actor;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }
}
