package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceMasters.MasterRow;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** KUNDE Partner: masters of the partner's cleaning venues and the one-time invite codes the Executor app links with. */
@RestController
@RequestMapping("/api/v1/partner/partners/{partnerId}/home-services/masters")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesPartnerMastersController {
    private final HomeServiceMasters masters;
    private final FeatureToggles toggles;

    public HomeServicesPartnerMastersController(HomeServiceMasters masters, FeatureToggles toggles) {
        this.masters = masters;
        this.toggles = toggles;
    }

    public record CreateMaster(@NotNull UUID venueId, @NotBlank @Size(max = 120) String name) {}

    @GetMapping
    ResponseEntity<List<MasterRow>> list(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return noStore(HttpStatus.OK, masters.masters(user(principal), partnerId));
    }

    @PostMapping
    ResponseEntity<MasterRow> create(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @Valid @RequestBody CreateMaster request) {
        return noStore(HttpStatus.CREATED, masters.create(user(principal), partnerId, request.venueId(), request.name()));
    }

    @PostMapping("/{masterId}/invite")
    ResponseEntity<MasterRow> reissue(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId, @PathVariable UUID masterId) {
        return noStore(HttpStatus.OK, masters.reissueInvite(user(principal), partnerId, masterId));
    }

    @PostMapping("/{masterId}/deactivate")
    ResponseEntity<Void> deactivate(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId, @PathVariable UUID masterId) {
        masters.deactivate(user(principal), partnerId, masterId);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private UUID user(Jwt principal) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        try {
            return UUID.fromString(principal.getSubject());
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed");
        }
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }
}
