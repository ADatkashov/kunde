package kz.kunde.food;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.food.FoodCatalogController.RestaurantSummary;
import kz.kunde.food.FoodPromotionService.PromotionView;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Food engagement: public promotions, cuisine categories and reviews; the caller's favorites; verified reviews (one per
 * delivered order of the caller) and review complaints. Ratings are always computed from VISIBLE reviews.
 */
@RestController
@Validated
@RequestMapping("/api/v1/food")
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodEngagementController {
    public record Category(String cuisine, int restaurants) {}

    public record ReviewView(String id, int rating, String comment, String author, OffsetDateTime createdAt) {}

    public record ReviewSummary(Double average, int count, int[] distribution, List<ReviewView> reviews) {}

    public record ReviewRequest(@Min(1) @Max(5) int rating, @Size(max = 1000) String comment) {}

    public record ComplaintRequest(@NotBlank @Size(min = 3, max = 300) String reason) {}

    public record FavoriteState(String restaurantId, boolean favorite) {}

    private final JdbcTemplate db;
    private final ConsumerIdentityService identity;
    private final FoodPromotionService promotions;

    public FoodEngagementController(JdbcTemplate db, ConsumerIdentityService identity, FoodPromotionService promotions) {
        this.db = db;
        this.identity = identity;
        this.promotions = promotions;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    // ---- public ---------------------------------------------------------------------------------------------

    @GetMapping("/promotions")
    public ResponseEntity<List<PromotionView>> promotions(@RequestParam(required = false) UUID restaurantId,
            @RequestParam(defaultValue = "FOOD") String vertical) {
        return noStore(HttpStatus.OK, promotions.active(restaurantId, vertical));
    }

    /** Cuisines with the number of open restaurants: the Food home categories come from real data. */
    @GetMapping("/categories")
    public ResponseEntity<List<Category>> categories(@RequestParam(defaultValue = "FOOD") String vertical) {
        return noStore(HttpStatus.OK, db.query("""
                select cuisine, count(*) from marketplace.food_restaurants where vertical = ? and is_open and moderation_status = 'ACTIVE'
                group by cuisine order by count(*) desc, cuisine""", (rs, n) -> new Category(rs.getString(1), rs.getInt(2)), vertical));
    }

    @GetMapping("/restaurants/{restaurantId}/reviews")
    public ResponseEntity<ReviewSummary> reviews(@PathVariable UUID restaurantId,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, summary(restaurantId, limit, offset));
    }

    ReviewSummary summary(UUID restaurantId, int limit, int offset) {
        int[] distribution = new int[5];
        double[] sum = {0};
        int[] count = {0};
        db.query("select rating, count(*) from marketplace.food_reviews where restaurant_id = ? and status = 'VISIBLE' group by rating",
                rs -> {
                    int rating = rs.getInt(1);
                    int n = rs.getInt(2);
                    distribution[rating - 1] = n;
                    sum[0] += (double) rating * n;
                    count[0] += n;
                }, restaurantId);
        List<ReviewView> list = db.query("""
                select id, rating, comment, author_name, created_at from marketplace.food_reviews
                where restaurant_id = ? and status = 'VISIBLE' order by created_at desc, id limit ? offset ?""",
                (rs, n) -> new ReviewView(rs.getString(1), rs.getInt(2), rs.getString(3), rs.getString(4),
                        rs.getObject(5, OffsetDateTime.class)), restaurantId, limit, offset);
        Double avg = count[0] == 0 ? null : Math.round(sum[0] / count[0] * 10.0) / 10.0;
        return new ReviewSummary(avg, count[0], distribution, list);
    }

    // ---- authenticated --------------------------------------------------------------------------------------

    @GetMapping("/favorites")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<List<RestaurantSummary>> favorites(@AuthenticationPrincipal Jwt principal) {
        UUID user = identity.get(principal).id();
        return noStore(HttpStatus.OK, db.query(FoodCatalogController.RESTAURANT_SELECT
                + " where r.id in (select restaurant_id from marketplace.food_favorites where user_id = ?)"
                + " order by (r.is_open and r.moderation_status = 'ACTIVE') desc, r.sort_order, r.name, r.id", FoodCatalogController::mapRestaurant, user));
    }

    @PutMapping("/favorites/{restaurantId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<FavoriteState> addFavorite(@AuthenticationPrincipal Jwt principal, @PathVariable UUID restaurantId) {
        UUID user = identity.get(principal).id();
        Integer exists = db.queryForObject("select count(*) from marketplace.food_restaurants where id = ?", Integer.class, restaurantId);
        if (exists == null || exists == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant is not available");
        }
        Integer count = db.queryForObject("select count(*) from marketplace.food_favorites where user_id = ?", Integer.class, user);
        if (count != null && count >= 200) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FAVORITES_LIMIT", "Too many favorites");
        }
        db.update("insert into marketplace.food_favorites (user_id, restaurant_id) values (?, ?) on conflict do nothing", user, restaurantId);
        return noStore(HttpStatus.OK, new FavoriteState(restaurantId.toString(), true));
    }

    @DeleteMapping("/favorites/{restaurantId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<FavoriteState> removeFavorite(@AuthenticationPrincipal Jwt principal, @PathVariable UUID restaurantId) {
        UUID user = identity.get(principal).id();
        db.update("delete from marketplace.food_favorites where user_id = ? and restaurant_id = ?", user, restaurantId);
        return noStore(HttpStatus.OK, new FavoriteState(restaurantId.toString(), false));
    }

    /** A review needs the caller's own DELIVERED order; one review per order, so ratings cannot be farmed. */
    @PostMapping("/orders/{orderId}/review")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<ReviewView> review(@AuthenticationPrincipal Jwt principal, @PathVariable UUID orderId,
            @Valid @RequestBody ReviewRequest request) {
        UUID user = identity.get(principal).id();
        var order = db.query("select restaurant_id, status from transactions.food_orders where id = ? and user_id = ? for update",
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2)}, orderId, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        if (!"DELIVERED".equals(order[1])) {
            throw new ApiException(HttpStatus.CONFLICT, "REVIEW_NOT_ALLOWED", "You can review an order after it is delivered");
        }
        Integer exists = db.queryForObject("select count(*) from marketplace.food_reviews where order_id = ?", Integer.class, orderId);
        if (exists != null && exists > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "REVIEW_EXISTS", "This order already has a review");
        }
        String comment = request.comment() == null || request.comment().isBlank() ? null : request.comment().strip();
        ReviewView view = db.queryForObject("""
                insert into marketplace.food_reviews (order_id, restaurant_id, user_id, rating, comment)
                values (?, ?, ?, ?, ?) returning id, rating, comment, author_name, created_at""",
                (rs, n) -> new ReviewView(rs.getString(1), rs.getInt(2), rs.getString(3), rs.getString(4),
                        rs.getObject(5, OffsetDateTime.class)), orderId, order[0], user, request.rating(), comment);
        return noStore(HttpStatus.CREATED, view);
    }

    @PostMapping("/reviews/{reviewId}/complaints")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<FavoriteState> complain(@AuthenticationPrincipal Jwt principal, @PathVariable UUID reviewId,
            @Valid @RequestBody ComplaintRequest request) {
        UUID user = identity.get(principal).id();
        Integer exists = db.queryForObject("select count(*) from marketplace.food_reviews where id = ? and status = 'VISIBLE'", Integer.class, reviewId);
        if (exists == null || exists == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Review not found");
        }
        db.update("""
                insert into marketplace.food_review_complaints (review_id, reporter_user_id, reason) values (?, ?, ?)
                on conflict (review_id, reporter_user_id) do nothing""", reviewId, user, request.reason().strip());
        return noStore(HttpStatus.ACCEPTED, new FavoriteState(reviewId.toString(), false));
    }
}
