package kz.kunde.rides;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.rides.RideDriverService.Decision;
import kz.kunde.rides.RideDriverService.Driver;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/rides")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class RideAdminController {
    private final RideDriverService drivers;
    private final RideFleetService fleets;
    private final AdminGrants grants;
    private final ConsumerIdentityService identity;

    public RideAdminController(RideDriverService drivers, RideFleetService fleets, AdminGrants grants, ConsumerIdentityService identity) {
        this.drivers = drivers;
        this.fleets = fleets;
        this.grants = grants;
        this.identity = identity;
    }

    @GetMapping("/drivers")
    ResponseEntity<List<UUID>> queue(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "false") boolean includeReviewed) {
        reviewer(principal);
        return noStore(drivers.reviewDrivers(includeReviewed));
    }

    @GetMapping("/drivers/{driverId}")
    ResponseEntity<Driver> driver(@AuthenticationPrincipal Jwt principal, @PathVariable UUID driverId) {
        reviewer(principal);
        return noStore(drivers.profile(driverId));
    }

    @PostMapping("/drivers/{driverId}/decision")
    ResponseEntity<Driver> decide(@AuthenticationPrincipal Jwt principal, @PathVariable UUID driverId,
            @Valid @RequestBody Review request) {
        return noStore(drivers.review(reviewer(principal), driverId, request.vehicleId(), request.decision()));
    }

    @GetMapping("/drivers/{driverId}/audit")
    ResponseEntity<List<RideDriverService.ReviewEvent>> driverAudit(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID driverId) {
        reviewer(principal);
        return noStore(drivers.audit(driverId));
    }

    @GetMapping("/fleets")
    ResponseEntity<List<RideFleetService.FleetReview>> fleetQueue(@AuthenticationPrincipal Jwt principal) {
        reviewer(principal);
        return noStore(fleets.reviewQueue());
    }

    @PostMapping("/fleets/{fleetId}/decision")
    ResponseEntity<Void> decideFleet(@AuthenticationPrincipal Jwt principal, @PathVariable UUID fleetId,
            @Valid @RequestBody FleetDecision request) {
        fleets.review(reviewer(principal), fleetId, request.decision());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/fleets/{fleetId}/audit")
    ResponseEntity<List<RideFleetService.FleetEvent>> fleetAudit(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID fleetId) {
        reviewer(principal);
        return noStore(fleets.audit(fleetId));
    }

    private UUID reviewer(Jwt principal) {
        UUID reviewer = identity.get(principal).id();
        grants.require(reviewer, Permission.RIDE_VERIFICATION);
        return reviewer;
    }

    private static <T> ResponseEntity<T> noStore(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record FleetDecision(@NotNull Decision decision) {}
    public record Review(UUID vehicleId, @NotNull Decision decision) {}
}
