package kz.kunde.homeservices;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceReviews.Rating;
import kz.kunde.homeservices.HomeServiceReviews.ReviewPage;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** KUNDE Executor: the master's own rating, completed-order count and review history. Never another master's. */
@RestController
@Validated
@RequestMapping("/api/v1/executor/home-services")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HomeServicesExecutorReviewsController {
    public record MyStats(Rating rating, long completedOrders) {}

    private final HomeServiceReviews reviews;
    private final FeatureToggles toggles;
    private final JdbcTemplate db;

    public HomeServicesExecutorReviewsController(HomeServiceReviews reviews, FeatureToggles toggles, JdbcTemplate db) {
        this.reviews = reviews;
        this.toggles = toggles;
        this.db = db;
    }

    @GetMapping("/rating")
    ResponseEntity<MyStats> rating(@AuthenticationPrincipal Jwt principal) {
        UUID master = master(principal);
        long completed = db.queryForObject("select count(*) from transactions.bookings where master_id = ? and category = 'CLEANING' and status = 'COMPLETED'",
                Long.class, master);
        return ok(new MyStats(reviews.masterRating(master), completed));
    }

    @GetMapping("/reviews")
    ResponseEntity<ReviewPage> history(@AuthenticationPrincipal Jwt principal, @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(reviews.page("master_id", master(principal), null, null, null, limit, offset));
    }

    private UUID master(Jwt principal) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        UUID user;
        try {
            user = UUID.fromString(principal.getSubject());
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed");
        }
        return db.query("select id from marketplace.booking_masters where user_id = ? and active", (rs, n) -> rs.getObject(1, UUID.class), user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_A_MASTER", "This account is not linked to a master"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
