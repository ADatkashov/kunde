package kz.kunde.admin;

import java.util.List;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.delivery.DeliveryOperations;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Reports only the caller's current grants for permission-aware navigation. */
@RestController
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminCapabilitiesController {
    private final AdminGrants grants;

    private final DeliveryOperations delivery;

    public AdminCapabilitiesController(AdminGrants grants, DeliveryOperations delivery) {
        this.grants = grants;
        this.delivery = delivery;
    }

    @GetMapping("/api/v1/admin/me/capabilities")
    ResponseEntity<Capabilities> capabilities(@AuthenticationPrincipal Jwt principal) {
        var userId = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(new Capabilities(grants.activePermissions(userId), delivery.canReadShipments(userId)));
    }

    public record Capabilities(List<Permission> permissions, boolean deliveryShipmentRead) {}
}
