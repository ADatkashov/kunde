package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceOffers.Action;
import kz.kunde.homeservices.HomeServiceOffers.Actor;
import kz.kunde.homeservices.HomeServiceOffers.Offer;
import kz.kunde.homeservices.HomeServiceOffers.Status;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.authz.AdminGrants;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Staff moderation of Home Services offers. Needs the {@code HOME_SERVICES_CATALOG} grant and works while the product
 * flag is off, so the catalogue can be prepared before the pilot is enabled.
 */
@RestController
@Validated
@RequestMapping("/api/v1/admin/home-services/offers")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesAdminOffersController {
    private final HomeServiceOffers offers;
    private final AdminGrants grants;

    public HomeServicesAdminOffersController(HomeServiceOffers offers, AdminGrants grants) {
        this.offers = offers;
        this.grants = grants;
    }

    public record Decision(@NotNull @Pattern(regexp = "APPROVE|REJECT|SUSPEND|RESTORE") String action,
            @NotNull @Min(1) Long expectedVersion, @NotBlank @Size(max = 200) String reason) {}

    @GetMapping
    ResponseEntity<List<Offer>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) @Pattern(regexp = "DRAFT|PENDING|PUBLISHED|REJECTED|SUSPENDED") String status,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        authorize(principal);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(offers.listForReview(status == null ? null : Status.valueOf(status), limit, offset));
    }

    @PostMapping("/{offerId}/decision")
    ResponseEntity<Offer> decide(@AuthenticationPrincipal Jwt principal, @PathVariable UUID offerId,
            @Valid @RequestBody Decision decision) {
        UUID actor = authorize(principal);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(offers.transition(actor, Actor.ADMIN, null,
                offerId, Action.valueOf(decision.action()), decision.expectedVersion(), decision.reason()));
    }

    private UUID authorize(Jwt principal) {
        UUID actor;
        try {
            actor = UUID.fromString(principal.getSubject());
        } catch (RuntimeException invalidSubject) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Access is not allowed");
        }
        grants.require(actor, AdminGrants.Permission.HOME_SERVICES_CATALOG);
        return actor;
    }
}
