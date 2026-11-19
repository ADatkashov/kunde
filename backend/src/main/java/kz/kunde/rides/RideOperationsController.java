package kz.kunde.rides;

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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/rides")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class RideOperationsController {
    private final RideOperationsService operations;
    private final ConsumerIdentityService identity;
    private final AdminGrants grants;

    public RideOperationsController(RideOperationsService operations, ConsumerIdentityService identity, AdminGrants grants) {
        this.operations = operations;
        this.identity = identity;
        this.grants = grants;
    }

    @GetMapping("/trips")
    ResponseEntity<List<RideOperationsService.Trip>> trips(@AuthenticationPrincipal Jwt token) {
        operator(token);
        return ok(operations.trips());
    }

    @GetMapping("/complaints")
    ResponseEntity<List<RideOperationsService.Complaint>> complaints(@AuthenticationPrincipal Jwt token) {
        operator(token);
        return ok(operations.complaints());
    }

    @PostMapping("/complaints/{id}/resolve")
    ResponseEntity<RideOperationsService.Complaint> resolve(@AuthenticationPrincipal Jwt token, @PathVariable UUID id) {
        return ok(operations.resolve(operator(token), id));
    }

    @GetMapping("/complaints/{id}/audit")
    ResponseEntity<List<RideOperationsService.ComplaintEvent>> audit(@AuthenticationPrincipal Jwt token, @PathVariable UUID id) {
        operator(token);
        return ok(operations.complaintAudit(id));
    }

    private UUID operator(Jwt token) {
        var actor = identity.get(token).id();
        grants.require(actor, AdminGrants.Permission.RIDE_OPERATIONS);
        return actor;
    }

    private static <T> ResponseEntity<T> ok(T value) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(value);
    }
}
