package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceOffers.Action;
import kz.kunde.homeservices.HomeServiceOffers.Actor;
import kz.kunde.homeservices.HomeServiceOffers.Offer;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.partner.PartnerService;
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
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** KUNDE Partner: offers of the partner's own Home Services venues; submit for moderation or withdraw. */
@RestController
@Validated
@RequestMapping("/api/v1/partner/partners/{partnerId}/home-services/offers")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesPartnerOffersController {
    private final HomeServiceOffers offers;
    private final PartnerService partners;
    private final FeatureToggles toggles;

    public HomeServicesPartnerOffersController(HomeServiceOffers offers, PartnerService partners, FeatureToggles toggles) {
        this.offers = offers;
        this.partners = partners;
        this.toggles = toggles;
    }

    public record CreateOffer(
            @NotNull UUID serviceId,
            @NotNull @Pattern(regexp = "[A-Z][A-Z0-9_]{1,39}") String definitionCode,
            @NotNull @Pattern(regexp = "[A-Z_]{3,16}") String pricingModel,
            Boolean homeVisit,
            @Min(0) @Max(1095) Integer warrantyDays) {}

    public record TransitionRequest(@NotNull @Pattern(regexp = "SUBMIT|WITHDRAW") String action,
            @NotNull @Min(1) Long expectedVersion) {}

    @GetMapping
    ResponseEntity<List<Offer>> list(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        authorize(principal, partnerId);
        return ok(HttpStatus.OK, offers.listForPartner(partnerId, limit, offset));
    }

    @PostMapping
    ResponseEntity<Offer> create(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @Valid @RequestBody CreateOffer request) {
        UUID user = authorize(principal, partnerId);
        return ok(HttpStatus.CREATED, offers.create(user, partnerId, request.serviceId(), request.definitionCode(),
                request.pricingModel(), request.homeVisit() == null || request.homeVisit(),
                request.warrantyDays() == null ? 0 : request.warrantyDays()));
    }

    @PostMapping("/{offerId}/transition")
    ResponseEntity<Offer> transition(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID offerId, @Valid @RequestBody TransitionRequest request) {
        UUID user = authorize(principal, partnerId);
        return ok(HttpStatus.OK, offers.transition(user, Actor.PARTNER, partnerId, offerId,
                Action.valueOf(request.action()), request.expectedVersion(), null));
    }

    private UUID authorize(Jwt principal, UUID partnerId) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        UUID user = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        partners.requireProcessing(user, partnerId);
        return user;
    }

    private static <T> ResponseEntity<T> ok(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }
}
