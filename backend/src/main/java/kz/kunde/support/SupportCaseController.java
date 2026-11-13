package kz.kunde.support;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/me/support/cases")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class SupportCaseController {
    private final SupportCaseService cases;

    public SupportCaseController(SupportCaseService cases) {
        this.cases = cases;
    }

    public record OpenCaseRequest(@NotNull SupportCaseService.Category category,
                                  @NotBlank @Size(max = 2000) String message) {}

    @PostMapping
    ResponseEntity<SupportCaseService.CaseView> open(
            @AuthenticationPrincipal Jwt principal,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody OpenCaseRequest request) {
        SupportCaseService.Created result =
                cases.open(principal, idempotencyKey, request.category(), request.message());
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .cacheControl(CacheControl.noStore()).body(result.view());
    }

    @GetMapping
    ResponseEntity<List<SupportCaseService.CaseView>> list(
            @AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "20") int limit, @RequestParam(defaultValue = "0") int offset) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(cases.list(principal, limit, offset));
    }

    @GetMapping("/{id}")
    ResponseEntity<SupportCaseService.CaseView> get(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(cases.get(principal, id));
    }

    @PostMapping("/{id}/escalation")
    ResponseEntity<SupportCaseService.CaseView> escalate(
            @AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(cases.requestEscalation(principal, id));
    }
}
