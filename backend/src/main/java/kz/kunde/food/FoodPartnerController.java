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

    public FoodPartnerController(FoodPartnerService service) {
        this.service = service;
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
        return ok(service.setOpen(user(principal), partnerId, restaurantId, request.open()));
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
                request.stockQty(), Boolean.TRUE.equals(request.clearStock())));
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record StatusRequest(@NotBlank @Pattern(regexp = "ACCEPTED|PREPARING|ON_THE_WAY|DELIVERED|CANCELLED") String status,
            @Size(max = 300) String reason) {}

    public record OpenRequest(@NotNull Boolean open) {}

    public record DishRequest(Boolean available, @Min(0) @Max(100000) Integer stockQty, Boolean clearStock) {}
}
