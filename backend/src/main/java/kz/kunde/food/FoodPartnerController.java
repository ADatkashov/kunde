package kz.kunde.food;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.food.FoodPartnerService.DishView;
import kz.kunde.food.FoodPartnerService.PartnerOrder;
import kz.kunde.food.FoodPartnerService.RestaurantView;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/** Partner order inbox and availability for Food/Grocery (ADR-018 partner scope + per-request membership check). */
@RestController
@Validated
@RequestMapping("/api/v1/partner/partners/{partnerId}/food")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.food.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class FoodPartnerController {
    private final FoodPartnerService service;
    private final FoodPromotionService promotions;
    private final FoodEngagementController engagement;

    public FoodPartnerController(FoodPartnerService service, FoodPromotionService promotions, FoodEngagementController engagement) {
        this.service = service;
        this.promotions = promotions;
        this.engagement = engagement;
    }

    @GetMapping("/orders")
    ResponseEntity<List<PartnerOrder>> orders(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @RequestParam(defaultValue = "active") @Pattern(regexp = "active|history") String scope,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(service.list(user(principal), partnerId, scope, limit, offset));
    }

    @GetMapping("/orders/{orderId}")
    ResponseEntity<PartnerOrder> order(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID orderId) {
        return ok(service.get(user(principal), partnerId, orderId));
    }

    @PostMapping("/orders/{orderId}/status")
    ResponseEntity<PartnerOrder> status(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID orderId, @Valid @RequestBody StatusRequest request) {
        return ok(service.transition(user(principal), partnerId, orderId, request.status(), request.reason()));
    }

    @GetMapping("/restaurants")
    ResponseEntity<List<RestaurantView>> restaurants(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return ok(service.restaurants(user(principal), partnerId));
    }

    @PatchMapping("/restaurants/{restaurantId}")
    ResponseEntity<RestaurantView> restaurant(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID restaurantId, @Valid @RequestBody OpenRequest request) {
        return ok(service.updateRestaurant(user(principal), partnerId, restaurantId, new FoodPartnerService.RestaurantUpdate(
                request.open(), request.pickupEnabled(), request.prepMinutes(), request.etaMinMinutes(), request.etaMaxMinutes(),
                request.deliveryFeeMinor(), request.minOrderMinor(), request.addressText(), request.description())));
    }

    @GetMapping("/summary")
    ResponseEntity<FoodPartnerService.Summary> summary(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return ok(service.summary(user(principal), partnerId));
    }

    @GetMapping("/promotions")
    ResponseEntity<List<FoodPromotionService.PromotionView>> promotions(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        service.requireAccess(user(principal), partnerId);
        return ok(promotions.forPartner(partnerId));
    }

    @PostMapping("/promotions")
    ResponseEntity<FoodPromotionService.PromotionView> createPromotion(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @Valid @RequestBody PromotionRequest r) {
        service.requireManager(user(principal), partnerId);
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(promotions.createForPartner(
                user(principal), partnerId, new FoodPromotionService.CreatePromotion(r.code(), r.title(), r.description(), r.kind(),
                        r.value(), r.maxDiscountMinor(), r.minSubtotalMinor(), r.restaurantId(), r.startsAt(), r.endsAt(),
                        r.maxRedemptions(), r.perUserLimit(), r.banner())));
    }

    @PostMapping("/promotions/{promotionId}/status")
    ResponseEntity<FoodPromotionService.PromotionView> promotionStatus(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID promotionId, @Valid @RequestBody PromotionStatusRequest r) {
        service.requireManager(user(principal), partnerId);
        return ok(promotions.setPartnerStatus(user(principal), partnerId, promotionId, r.status()));
    }

    @GetMapping("/restaurants/{restaurantId}/reviews")
    ResponseEntity<FoodEngagementController.ReviewSummary> reviews(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID restaurantId, @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        service.requireOwnedRestaurantFor(user(principal), partnerId, restaurantId);
        return ok(engagement.summary(restaurantId, limit, offset));
    }

    @GetMapping("/restaurants/{restaurantId}/dishes")
    ResponseEntity<List<DishView>> dishes(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID restaurantId) {
        return ok(service.dishes(user(principal), partnerId, restaurantId));
    }

    @PatchMapping("/restaurants/{restaurantId}/dishes/{dishId}")
    ResponseEntity<DishView> dish(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID restaurantId, @PathVariable UUID dishId, @Valid @RequestBody DishRequest request) {
        return ok(service.updateDish(user(principal), partnerId, restaurantId, dishId, request.available(),
                request.stockQty(), Boolean.TRUE.equals(request.clearStock()), request.name(), request.description(),
                request.priceMinor()));
    }

    @PostMapping("/restaurants/{restaurantId}/dishes")
    ResponseEntity<DishView> createDish(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID restaurantId, @Valid @RequestBody CreateDishRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(service.createDish(
                user(principal), partnerId, restaurantId, request.sectionId(), request.name(), request.description(),
                request.priceMinor()));
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record StatusRequest(@NotBlank @Pattern(regexp = "ACCEPTED|PREPARING|READY_FOR_PICKUP|ON_THE_WAY|DELIVERED|CANCELLED") String status,
            @Size(max = 300) String reason) {}

    public record OpenRequest(Boolean open, Boolean pickupEnabled, @Min(1) @Max(240) Integer prepMinutes,
            @Min(1) @Max(240) Integer etaMinMinutes, @Min(1) @Max(240) Integer etaMaxMinutes,
            @Min(0) @Max(10000000) Long deliveryFeeMinor, @Min(0) @Max(100000000) Long minOrderMinor,
            @Size(max = 300) String addressText, @Size(max = 500) String description) {}

    public record PromotionRequest(@Size(max = 32) String code, @NotBlank @Size(max = 120) String title, @Size(max = 300) String description,
            @NotBlank @jakarta.validation.constraints.Pattern(regexp = "PERCENT|FIXED") String kind, @Min(1) @Max(100000000) long value,
            @Min(1) Long maxDiscountMinor, @Min(0) long minSubtotalMinor, @NotNull UUID restaurantId, java.time.OffsetDateTime startsAt,
            @NotNull java.time.OffsetDateTime endsAt, @Min(1) Integer maxRedemptions, @Min(1) @Max(100) Integer perUserLimit, boolean banner) {}

    public record PromotionStatusRequest(@NotBlank @jakarta.validation.constraints.Pattern(regexp = "ACTIVE|PAUSED") String status) {}

    public record DishRequest(Boolean available, @Min(0) @Max(100000) Integer stockQty, Boolean clearStock,
            @Size(max = 160) String name, @Size(max = 500) String description, @Min(0) @Max(100000000) Long priceMinor) {}

    public record CreateDishRequest(@NotNull UUID sectionId, @NotBlank @Size(max = 160) String name,
            @Size(max = 500) String description, @NotNull @Min(0) @Max(100000000) Long priceMinor) {}
}
