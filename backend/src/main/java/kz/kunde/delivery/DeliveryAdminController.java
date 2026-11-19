package kz.kunde.delivery;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RequestParam;

@RestController
@RequestMapping("/api/v1/admin/deliveries")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class DeliveryAdminController {
    private final ConsumerIdentityService identity;
    private final AdminGrants grants;
    private final DeliveryCouriers couriers;
    private final DeliveryDispatch dispatch;
    private final DeliveryOperations operations;

    public DeliveryAdminController(ConsumerIdentityService identity, AdminGrants grants, DeliveryCouriers couriers,
            DeliveryDispatch dispatch, DeliveryOperations operations) {
        this.identity = identity;
        this.grants = grants;
        this.couriers = couriers;
        this.dispatch = dispatch;
        this.operations = operations;
    }

    @GetMapping("/couriers")
    public ResponseEntity<List<DeliveryCouriers.Profile>> queue(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "false") boolean includeReviewed) {
        reviewer(principal);
        return noStore(couriers.forReview(includeReviewed));
    }

    @PostMapping("/couriers/{id}/decision")
    public ResponseEntity<DeliveryCouriers.Profile> review(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID id, @Valid @RequestBody Review review) {
        return noStore(couriers.review(reviewer(principal), id, review.decision(), review.maxGrams(),
                review.maxSideCm(), review.reason()));
    }

    @PostMapping("/{id}/return")
    public ResponseEntity<DeliveryExecutorController.StateResponse> requestReturn(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID id) {
        return noStore(new DeliveryExecutorController.StateResponse(dispatch.requestReturn(reviewer(principal), id)));
    }

    @GetMapping
    public ResponseEntity<List<DeliveryOperations.Shipment>> shipments(@AuthenticationPrincipal Jwt principal) {
        return noStore(operations.shipments(identity.get(principal).id()));
    }

    @GetMapping("/{id}/audit")
    public ResponseEntity<List<DeliveryOperations.Event>> audit(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID id) {
        return noStore(operations.audit(identity.get(principal).id(), id));
    }

    @GetMapping("/complaints")
    public ResponseEntity<List<DeliveryOperations.Complaint>> complaints(@AuthenticationPrincipal Jwt principal) {
        reviewer(principal);
        return noStore(operations.complaints());
    }

    @PostMapping("/complaints/{id}/resolve")
    public ResponseEntity<DeliveryOperations.Complaint> resolve(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID id) {
        return noStore(operations.resolve(reviewer(principal), id));
    }

    private UUID reviewer(Jwt principal) {
        UUID actor = identity.get(principal).id();
        grants.require(actor, AdminGrants.Permission.DELIVERY_OPERATIONS);
        return actor;
    }

    private static <T> ResponseEntity<T> noStore(T value) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(value);
    }

    public record Review(@NotNull DeliveryCouriers.Decision decision, @Min(1) @Max(50000) int maxGrams,
            @Min(1) @Max(200) int maxSideCm, @NotBlank @Size(max = 200) String reason) {}
}
