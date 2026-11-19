package kz.kunde.rides;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.rides.RideFleetService.Fleet;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/partner/partners/{partnerId}/rides/fleet")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class RideFleetController {
    private final RideFleetService fleets;
    private final ConsumerIdentityService identity;

    public RideFleetController(RideFleetService fleets, ConsumerIdentityService identity) {
        this.fleets = fleets;
        this.identity = identity;
    }

    @GetMapping
    ResponseEntity<Fleet> view(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return ok(fleets.view(identity.get(principal).id(), partnerId));
    }

    @PostMapping
    ResponseEntity<Fleet> apply(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return ok(fleets.apply(identity.get(principal).id(), partnerId));
    }

    @PutMapping("/drivers/{driverId}")
    ResponseEntity<Fleet> assign(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID driverId, @Valid @RequestBody Assignment request) {
        return ok(fleets.assignment(identity.get(principal).id(), partnerId, driverId, request.attach()));
    }

    private static ResponseEntity<Fleet> ok(Fleet fleet) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(fleet);
    }

    public record Assignment(@NotNull Boolean attach) {}
}
