package kz.kunde.delivery;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.geo.Coordinates;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/executor/deliveries")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class DeliveryExecutorController {
    private final ConsumerIdentityService identity;
    private final DeliveryCouriers couriers;
    private final DeliveryDispatch dispatch;
    private final DeliveryTracking tracking;

    public DeliveryExecutorController(ConsumerIdentityService identity, DeliveryCouriers couriers, DeliveryDispatch dispatch,
            DeliveryTracking tracking) {
        this.identity = identity;
        this.couriers = couriers;
        this.dispatch = dispatch;
        this.tracking = tracking;
    }

    @GetMapping("/profile")
    public ResponseEntity<DeliveryCouriers.Profile> profile(@AuthenticationPrincipal Jwt principal) {
        return noStore(couriers.profile(identity.get(principal).id()));
    }

    @PostMapping("/profile")
    public ResponseEntity<DeliveryCouriers.Profile> register(@AuthenticationPrincipal Jwt principal,
            @Valid @RequestBody Enrollment request) {
        return noStore(couriers.register(identity.get(principal).id(), request.name(), request.vehicle()));
    }

    @PutMapping("/availability")
    public ResponseEntity<DeliveryCouriers.Profile> availability(@AuthenticationPrincipal Jwt principal,
            @Valid @RequestBody Availability request) {
        return noStore(couriers.availability(identity.get(principal).id(), request.online()));
    }

    @PutMapping("/location")
    public ResponseEntity<Void> location(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody Coordinates point) {
        couriers.location(identity.get(principal).id(), point);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PutMapping("/{id}/location")
    public ResponseEntity<Void> publishAssignmentLocation(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
            @Valid @RequestBody Coordinates point) {
        tracking.publish(identity.get(principal).id(), id, point);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @DeleteMapping("/{id}/location")
    public ResponseEntity<Void> stopAssignmentLocation(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        tracking.stop(identity.get(principal).id(), id);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @GetMapping("/offers")
    public ResponseEntity<List<DeliveryDispatch.Offer>> offers(@AuthenticationPrincipal Jwt principal) {
        return noStore(dispatch.offers(identity.get(principal).id()));
    }

    @PostMapping("/offers/{offerId}/response")
    public ResponseEntity<Void> respond(@AuthenticationPrincipal Jwt principal, @PathVariable UUID offerId,
            @Valid @RequestBody OfferResponse response) {
        dispatch.respond(identity.get(principal).id(), offerId, response.accept());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @GetMapping
    public ResponseEntity<List<DeliveryDispatch.CourierShipment>> shipments(@AuthenticationPrincipal Jwt principal) {
        return noStore(dispatch.shipments(identity.get(principal).id()));
    }

    @PostMapping("/{id}/progress")
    public ResponseEntity<StateResponse> progress(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
            @Valid @RequestBody Progress request) {
        return noStore(new StateResponse(dispatch.progress(identity.get(principal).id(), id, request.action())));
    }

    @PostMapping("/{id}/handoff")
    public ResponseEntity<Void> handoff(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
            @Valid @RequestBody Handoff request) {
        boolean success = dispatch.verifyCode(identity.get(principal).id(), id, request.code());
        return (success ? ResponseEntity.noContent() : ResponseEntity.unprocessableEntity())
                .cacheControl(CacheControl.noStore()).build();
    }

    private static <T> ResponseEntity<T> noStore(T value) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(value);
    }

    public record Enrollment(@NotBlank @Size(max = 80) String name, @NotNull DeliveryCouriers.Vehicle vehicle) {}
    public record Availability(@NotNull Boolean online) {}
    public record OfferResponse(@NotNull Boolean accept) {}
    public record Progress(@NotNull DeliveryState.Action action) {}
    public record Handoff(@NotNull @Pattern(regexp = "[0-9]{8}") String code) {
        @Override
        public String toString() {
            return "Handoff[code=redacted]";
        }
    }
    public record StateResponse(DeliveryState status) {}
}
