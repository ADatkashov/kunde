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
import kz.kunde.homeservices.HomeServiceReviews.Complaint;
import kz.kunde.homeservices.HomeServiceReviews.StaffReview;
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
 * Staff moderation of Home Services reviews and complaints about them (grant {@code HOME_SERVICES_OPERATIONS}). Reviews with an open
 * complaint come first. Hiding or republishing needs a reason and the version the screen saw; everything is audited.
 */
@RestController
@Validated
@RequestMapping("/api/v1/admin/home-services")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled", "app.booking.enabled"}, havingValue = "true")
public class HomeServicesAdminReviewsController {
    public record Moderation(@NotNull @Pattern(regexp = "HIDE|PUBLISH") String action, @NotNull @Min(1) Long expectedVersion,
            @NotBlank @Size(min = 3, max = 200) String reason) {}

    public record Resolution(@NotBlank @Size(min = 3, max = 300) String resolution, boolean hideReview) {}

    private final HomeServiceReviews reviews;
    private final AdminGrants grants;

    public HomeServicesAdminReviewsController(HomeServiceReviews reviews, AdminGrants grants) {
        this.reviews = reviews;
        this.grants = grants;
    }

    @GetMapping("/reviews")
    ResponseEntity<List<StaffReview>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) @Pattern(regexp = "PUBLISHED|HIDDEN") String status,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        authorize(principal);
        return ok(reviews.staffReviews(status, limit, offset));
    }

    @PostMapping("/reviews/{reviewId}/moderation")
    ResponseEntity<StaffReview> moderate(@AuthenticationPrincipal Jwt principal, @PathVariable UUID reviewId, @Valid @RequestBody Moderation body) {
        UUID admin = authorize(principal);
        return ok(reviews.moderate(admin, reviewId, "HIDE".equals(body.action()), body.expectedVersion(), body.reason()));
    }

    @GetMapping("/review-complaints")
    ResponseEntity<List<Complaint>> complaints(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) @Pattern(regexp = "OPEN|RESOLVED") String status,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        authorize(principal);
        return ok(reviews.staffComplaints(status, limit, offset));
    }

    @PostMapping("/review-complaints/{complaintId}/resolve")
    ResponseEntity<Complaint> resolve(@AuthenticationPrincipal Jwt principal, @PathVariable UUID complaintId, @Valid @RequestBody Resolution body) {
        UUID admin = authorize(principal);
        return ok(reviews.resolve(admin, complaintId, body.resolution(), body.hideReview()));
    }

    private UUID authorize(Jwt principal) {
        UUID actor;
        try {
            actor = UUID.fromString(principal.getSubject());
        } catch (RuntimeException invalidSubject) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Access is not allowed");
        }
        grants.require(actor, AdminGrants.Permission.HOME_SERVICES_OPERATIONS);
        return actor;
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
