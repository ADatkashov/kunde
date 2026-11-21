package kz.kunde.food;

import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Executor (courier) API for Food and Groceries hand-off tasks. Needs an approved courier profile (Delivery registry). */
@RestController
@RequestMapping("/api/v1/executor/food")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodCourierController {
    private final FoodCourierService tasks;
    private final ConsumerIdentityService identity;

    public FoodCourierController(FoodCourierService tasks, ConsumerIdentityService identity) {
        this.tasks = tasks;
        this.identity = identity;
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    @GetMapping("/tasks/open")
    public ResponseEntity<List<FoodCourierService.Task>> open(@AuthenticationPrincipal Jwt principal) {
        return ok(tasks.open(identity.get(principal).id()));
    }

    @GetMapping("/tasks/mine")
    public ResponseEntity<List<FoodCourierService.Task>> mine(@AuthenticationPrincipal Jwt principal) {
        return ok(tasks.mine(identity.get(principal).id()));
    }

    @PostMapping("/tasks/{taskId}/accept")
    public ResponseEntity<FoodCourierService.Task> accept(@AuthenticationPrincipal Jwt principal, @PathVariable UUID taskId) {
        return ok(tasks.accept(identity.get(principal).id(), taskId));
    }

    @PostMapping("/tasks/{taskId}/pickup")
    public ResponseEntity<FoodCourierService.Task> pickUp(@AuthenticationPrincipal Jwt principal, @PathVariable UUID taskId) {
        return ok(tasks.pickUp(identity.get(principal).id(), taskId));
    }

    @PostMapping("/tasks/{taskId}/deliver")
    public ResponseEntity<FoodCourierService.Task> deliver(@AuthenticationPrincipal Jwt principal, @PathVariable UUID taskId) {
        return ok(tasks.deliver(identity.get(principal).id(), taskId));
    }
}
