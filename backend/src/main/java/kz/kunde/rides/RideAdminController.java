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
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/rides/drivers")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class RideAdminController {
    private final RideDriverService drivers;
    private final AdminGrants grants;
    private final ConsumerIdentityService identity;

    public RideAdminController(RideDriverService drivers, AdminGrants grants, ConsumerIdentityService identity) {
        this.drivers = drivers;
        this.grants = grants;
        this.identity = identity;
    }

    @GetMapping
    ResponseEntity<List<UUID>> queue(@AuthenticationPrincipal Jwt principal) {
        reviewer(principal);
        return noStore(drivers.pendingDrivers());
    }

    @GetMapping("/{driverId}")
    ResponseEntity<Driver> driver(@AuthenticationPrincipal Jwt principal, @PathVariable UUID driverId) {
        reviewer(principal);
        return noStore(drivers.profile(driverId));
    }

    @PostMapping("/{driverId}/decision")
    ResponseEntity<Driver> decide(@AuthenticationPrincipal Jwt principal, @PathVariable UUID driverId,
            @Valid @RequestBody Review request) {
        return noStore(drivers.review(reviewer(principal), driverId, request.vehicleId(), request.decision()));
    }

    private UUID reviewer(Jwt principal) {
        UUID reviewer = identity.get(principal).id();
        grants.require(reviewer, Permission.RIDE_VERIFICATION);
        return reviewer;
    }

    private static <T> ResponseEntity<T> noStore(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record Review(UUID vehicleId, @NotNull Decision decision) {}
}
