package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceReviews.Created;
import kz.kunde.homeservices.HomeServiceReviews.MyReview;
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

/**
 * Consumer side of Home Services reviews: the owner of a completed order leaves one review (repeating the same request is harmless),
 * reads it back, and anyone signed in reads the published reviews and the computed rating of an offer or a master.
 */
@RestController
@Validated
@RequestMapping("/api/v1/home-services")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesReviewsController {
    public record ReviewRequest(@NotNull @Min(1) @Max(5) Integer rating, @Min(1) @Max(5) Integer qualityRating,
            @Min(1) @Max(5) Integer punctualityRating, @Size(max = 1000) String comment) {}

    private final HomeServiceReviews reviews;
    private final FeatureToggles toggles;
    private final org.springframework.jdbc.core.JdbcTemplate db;

    public HomeServicesReviewsController(HomeServiceReviews reviews, FeatureToggles toggles, org.springframework.jdbc.core.JdbcTemplate db) {
        this.reviews = reviews;
        this.toggles = toggles;
        this.db = db;
    }

    @PostMapping("/bookings/{bookingId}/review")
    ResponseEntity<MyReview> create(@AuthenticationPrincipal Jwt principal, @PathVariable UUID bookingId, @Valid @RequestBody ReviewRequest request) {
        Created created = reviews.create(user(principal), bookingId, request.rating(), request.qualityRating(), request.punctualityRating(),
                request.comment());
        return ResponseEntity.status(created.created() ? HttpStatus.CREATED : HttpStatus.OK).cacheControl(CacheControl.noStore()).body(created.review());
    }

    @GetMapping("/bookings/{bookingId}/review")
    ResponseEntity<MyReview> mine(@AuthenticationPrincipal Jwt principal, @PathVariable UUID bookingId) {
        return ok(reviews.mine(user(principal), bookingId));
    }

    @GetMapping("/offers/{offerId}/reviews")
    ResponseEntity<ReviewPage> offerReviews(@AuthenticationPrincipal Jwt principal, @PathVariable UUID offerId,
            @RequestParam(required = false) @Min(1) @Max(5) Integer rating,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        user(principal);
        UUID service = db.query("select service_id from marketplace.home_service_offers where id = ? and status = 'PUBLISHED'",
                (rs, n) -> rs.getObject(1, UUID.class), offerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "OFFER_NOT_FOUND", "Offer not found"));
        return ok(reviews.page("service_id", service, rating, null, null, limit, offset));
    }

    @GetMapping("/masters/{masterId}/reviews")
    ResponseEntity<ReviewPage> masterReviews(@AuthenticationPrincipal Jwt principal, @PathVariable UUID masterId,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        user(principal);
        return ok(reviews.page("master_id", masterId, null, null, null, limit, offset));
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

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
