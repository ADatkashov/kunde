package kz.kunde.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import kz.kunde.platform.FeatureToggles.FeatureView;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Feature switches for Auto, Rides and Delivery. The environment decides what is allowed (and still carries the production
 * guards); this API only switches an allowed feature on or off. Needs the ADMIN_GRANTS grant on every request, a written
 * reason, and appends every change to the immutable journal.
 */
@RestController
@RequestMapping("/api/v1/admin/features")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminFeatureController {
    public record SwitchBody(@NotNull Boolean enabled, @NotNull String reason, Long version) {}

    private final AdminGrants grants;
    private final FeatureToggles toggles;

    public AdminFeatureController(AdminGrants grants, FeatureToggles toggles) {
        this.grants = grants;
        this.toggles = toggles;
    }

    private UUID admin(Jwt principal) {
        UUID id = PartnerAccessPolicy.userId(principal).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(id, Permission.ADMIN_GRANTS);
        return id;
    }

    @GetMapping
    ResponseEntity<List<FeatureView>> list(@AuthenticationPrincipal Jwt principal) {
        admin(principal);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(toggles.views());
    }

    @PutMapping("/{feature}")
    ResponseEntity<FeatureView> set(@AuthenticationPrincipal Jwt principal, @PathVariable String feature, @Valid @RequestBody SwitchBody body) {
        UUID admin = admin(principal);
        Feature parsed;
        try {
            parsed = Feature.valueOf(feature.toUpperCase(java.util.Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ApiException(HttpStatus.NOT_FOUND, "FEATURE_NOT_FOUND", "Unknown feature");
        }
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(toggles.set(admin, parsed, body.enabled(), body.reason(), body.version()));
    }
}
