package kz.kunde.leisure;

import jakarta.validation.constraints.Pattern;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.leisure.LeisureExecutorService.Assignment;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/** Executor (guide, host, instructor, animator) API for the Leisure sessions a partner offered to the signed-in user. */
@RestController
@Validated
@RequestMapping("/api/v1/executor/leisure")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class LeisureExecutorController {
    private final LeisureExecutorService service;
    private final ConsumerIdentityService identity;

    public LeisureExecutorController(LeisureExecutorService service, ConsumerIdentityService identity) {
        this.service = service;
        this.identity = identity;
    }

    public record StepBody(@Pattern(regexp = "ACCEPT|DECLINE|START|COMPLETE|CANCEL") String step) {}

    private static <T> ResponseEntity<T> ok(T body) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body); }

    @GetMapping("/assignments")
    ResponseEntity<List<Assignment>> mine(@AuthenticationPrincipal Jwt p, @RequestParam(defaultValue = "active") @Pattern(regexp = "active|history") String scope) {
        return ok(service.mine(identity.get(p).id(), scope));
    }

    @PostMapping("/assignments/{id}/step")
    ResponseEntity<Assignment> step(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @RequestBody StepBody body) {
        return ok(service.step(identity.get(p).id(), id, LeisureExecutorService.Step.valueOf(body.step() == null ? "ACCEPT" : body.step())));
    }
}
