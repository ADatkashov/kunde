package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.homeservices.HomeServicePricing.Tariff;
import kz.kunde.homeservices.HomeServicePricing.Zone;
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
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** KUNDE Partner: service zones of the partner's venues and surcharge tariffs of its offers. */
@RestController
@Validated
@RequestMapping("/api/v1/partner/partners/{partnerId}/home-services")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesPartnerPricingController {
    private final HomeServicePricing pricing;
    private final FeatureToggles toggles;

    public HomeServicesPartnerPricingController(HomeServicePricing pricing, FeatureToggles toggles) {
        this.pricing = pricing;
        this.toggles = toggles;
    }

    public record CreateZone(@NotNull UUID venueId, @NotBlank @Size(max = 80) String name,
            @NotNull @DecimalMin("-90") @DecimalMax("90") Double centerLat,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double centerLng,
            @NotNull @Min(300) @Max(100000) Integer radiusM) {}

    public record UpdateZone(@NotBlank @Size(max = 80) String name,
            @NotNull @DecimalMin("-90") @DecimalMax("90") Double centerLat,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double centerLng,
            @NotNull @Min(300) @Max(100000) Integer radiusM, @NotNull Boolean active, @NotNull @Min(1) Long expectedVersion) {}

    /** {@code expectedVersion} 0 creates the tariff, otherwise it must equal the stored version. */
    public record SaveTariff(@NotNull @Min(0) @Max(100000000) Long callOutFeeMinor,
            @NotNull @Min(0) @Max(100) Integer urgentSurchargePercent, @NotNull @Min(0) @Max(100) Integer eveningSurchargePercent,
            @NotNull @jakarta.validation.constraints.Pattern(regexp = "([01][0-9]|2[0-3]):[0-5][0-9]") String eveningFrom,
            @NotNull @Min(0) Long expectedVersion) {}

    @GetMapping("/zones")
    ResponseEntity<List<Zone>> zones(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, pricing.zones(user(principal), partnerId, limit, offset));
    }

    @PostMapping("/zones")
    ResponseEntity<Zone> createZone(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @Valid @RequestBody CreateZone request) {
        return noStore(HttpStatus.CREATED, pricing.createZone(user(principal), partnerId, request.venueId(), request.name(),
                request.centerLat(), request.centerLng(), request.radiusM()));
    }

    @PutMapping("/zones/{zoneId}")
    ResponseEntity<Zone> updateZone(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID zoneId, @Valid @RequestBody UpdateZone request) {
        return noStore(HttpStatus.OK, pricing.updateZone(user(principal), partnerId, zoneId, request.name(), request.centerLat(),
                request.centerLng(), request.radiusM(), request.active(), request.expectedVersion()));
    }

    @PutMapping("/offers/{offerId}/tariff")
    ResponseEntity<Tariff> saveTariff(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID offerId, @Valid @RequestBody SaveTariff request) {
        return noStore(HttpStatus.OK, pricing.saveTariff(user(principal), partnerId, offerId, request.callOutFeeMinor(),
                request.urgentSurchargePercent(), request.eveningSurchargePercent(), LocalTime.parse(request.eveningFrom()),
                request.expectedVersion()));
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
