package kz.kunde.auto;

import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/** Customer complaints and reviews of Auto bookings and on-site jobs. */
@RestController
@RequestMapping("/api/v1/auto")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoFeedbackController {
    private final AutoFeedbackService feedback;
    private final ConsumerIdentityService identity;

    public AutoFeedbackController(AutoFeedbackService feedback, ConsumerIdentityService identity) {
        this.feedback = feedback;
        this.identity = identity;
    }

    private static <T> ResponseEntity<T> ok(HttpStatus s, T body) {
        return ResponseEntity.status(s).cacheControl(CacheControl.noStore()).body(body);
    }

    public record ComplaintBody(UUID bookingId, UUID jobId, String kind, String description) {}

    public record ReviewBody(Integer rating, String text) {}

    @PostMapping("/complaints")
    public ResponseEntity<AutoFeedbackService.Complaint> complain(@AuthenticationPrincipal Jwt p, @Valid @RequestBody ComplaintBody b) {
        return ok(HttpStatus.CREATED, feedback.complain(identity.get(p).id(), new AutoFeedbackService.ComplaintRequest(b.bookingId(), b.jobId(), b.kind(), b.description())));
    }

    @GetMapping("/complaints")
    public ResponseEntity<List<AutoFeedbackService.Complaint>> mine(@AuthenticationPrincipal Jwt p) {
        return ok(HttpStatus.OK, feedback.mine(identity.get(p).id()));
    }

    @PostMapping("/bookings/{id}/review")
    public ResponseEntity<AutoFeedbackService.Review> review(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @Valid @RequestBody ReviewBody b) {
        return ok(HttpStatus.CREATED, feedback.review(identity.get(p).id(), id, new AutoFeedbackService.ReviewRequest(b.rating(), b.text())));
    }

    @GetMapping("/bookings/{id}/review")
    public ResponseEntity<AutoFeedbackService.Review> review(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        return ok(HttpStatus.OK, feedback.reviewOf(identity.get(p).id(), id));
    }
}
