package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceReviews.Complaint;
import kz.kunde.homeservices.HomeServiceReviews.PartnerSummary;
import kz.kunde.homeservices.HomeServiceReviews.ReviewPage;
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

/** KUNDE Partner: published reviews of the partner's own venues, organisation and master ratings, and complaints about a review. */
@RestController
@Validated
@RequestMapping("/api/v1/partner/partners/{partnerId}/home-services/reviews")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesPartnerReviewsController {
    public record ComplaintRequest(@NotBlank @Size(min = 3, max = 300) String reason) {}

    private final HomeServiceReviews reviews;
    private final FeatureToggles toggles;

    public HomeServicesPartnerReviewsController(HomeServiceReviews reviews, FeatureToggles toggles) {
        this.reviews = reviews;
        this.toggles = toggles;
    }

    @GetMapping
    ResponseEntity<ReviewPage> list(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @RequestParam(required = false) @Min(1) @Max(5) Integer rating, @RequestParam(required = false) UUID masterId,
            @RequestParam(required = false) UUID venueId, @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, reviews.partnerReviews(user(principal), partnerId, rating, masterId, venueId, limit, offset));
    }

    @GetMapping("/summary")
    ResponseEntity<PartnerSummary> summary(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return noStore(HttpStatus.OK, reviews.partnerSummary(user(principal), partnerId));
    }

    @PostMapping("/{reviewId}/complaint")
    ResponseEntity<Complaint> complain(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId, @PathVariable UUID reviewId,
            @Valid @RequestBody ComplaintRequest request) {
        return noStore(HttpStatus.CREATED, reviews.complain(user(principal), partnerId, reviewId, request.reason()));
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
