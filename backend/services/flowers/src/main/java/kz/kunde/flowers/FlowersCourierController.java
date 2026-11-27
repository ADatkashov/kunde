package kz.kunde.flowers;

import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Executor (courier) API for flowers hand-off tasks. Needs an approved courier profile (Delivery registry). */
@RestController
@RequestMapping("/api/v1/executor/flowers")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class FlowersCourierController {
    private final FlowersCourierService tasks;
    private final ConsumerIdentityService identity;
    private final FeatureToggles toggles;

    public FlowersCourierController(FlowersCourierService tasks, ConsumerIdentityService identity, FeatureToggles toggles) {
        this.tasks = tasks;
        this.identity = identity;
        this.toggles = toggles;
    }

    private void on() {
        if (!toggles.enabled(Feature.FLOWERS)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "FLOWERS_DISABLED", "Flowers and gifts is unavailable");
        }
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    @GetMapping("/tasks/open")
    public ResponseEntity<List<FlowersCourierService.Task>> open(@AuthenticationPrincipal Jwt principal) {
        on();
        return ok(tasks.open(identity.get(principal).id()));
    }

    @GetMapping("/tasks/mine")
    public ResponseEntity<List<FlowersCourierService.Task>> mine(@AuthenticationPrincipal Jwt principal) {
        on();
        return ok(tasks.mine(identity.get(principal).id()));
    }

    @PostMapping("/tasks/{taskId}/accept")
    public ResponseEntity<FlowersCourierService.Task> accept(@AuthenticationPrincipal Jwt principal, @PathVariable UUID taskId) {
        on();
        return ok(tasks.accept(identity.get(principal).id(), taskId));
    }

    @PostMapping("/tasks/{taskId}/pickup")
    public ResponseEntity<FlowersCourierService.Task> pickUp(@AuthenticationPrincipal Jwt principal, @PathVariable UUID taskId) {
        on();
        return ok(tasks.pickUp(identity.get(principal).id(), taskId));
    }

    @PostMapping("/tasks/{taskId}/deliver")
    public ResponseEntity<FlowersCourierService.Task> deliver(@AuthenticationPrincipal Jwt principal, @PathVariable UUID taskId) {
        on();
        return ok(tasks.deliver(identity.get(principal).id(), taskId));
    }
}
