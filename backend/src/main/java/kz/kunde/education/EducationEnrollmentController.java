package kz.kunde.education;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import java.util.UUID;
import kz.kunde.education.EducationEnrollmentService.Enrollment;
import kz.kunde.education.EducationEnrollmentService.Learning;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

@RestController
@Validated
@RequestMapping("/api/v1/education/enrollments")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class EducationEnrollmentController {
    private final EducationEnrollmentService service;
    private final ConsumerIdentityService identity;

    public EducationEnrollmentController(EducationEnrollmentService service, ConsumerIdentityService identity) {
        this.service = service;
        this.identity = identity;
    }

    @PostMapping
    ResponseEntity<Enrollment> enroll(@AuthenticationPrincipal Jwt user,
            @RequestHeader("Idempotency-Key") @Pattern(regexp = "[a-zA-Z0-9_-]{16,80}") String key,
            @Valid @RequestBody Request request) {
        var result = service.enroll(identity.get(user).id(), request.cohortId(), request.expectedPriceMinor(), key);
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .cacheControl(CacheControl.noStore()).body(result.enrollment());
    }

    @GetMapping
    ResponseEntity<List<Enrollment>> history(@AuthenticationPrincipal Jwt user,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(service.history(identity.get(user).id(), limit, offset));
    }

    @GetMapping("/{id}/learning")
    ResponseEntity<Learning> learning(@AuthenticationPrincipal Jwt user, @PathVariable UUID id) {
        return ok(service.learning(identity.get(user).id(), id));
    }

    @PutMapping("/{id}/lessons/{module}/{lesson}/completion")
    ResponseEntity<Learning> complete(@AuthenticationPrincipal Jwt user, @PathVariable UUID id,
            @PathVariable @Min(1) int module, @PathVariable @Min(1) int lesson) {
        return ok(service.completeLesson(identity.get(user).id(), id, module, lesson));
    }

    private static <T> ResponseEntity<T> ok(T data) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(data);
    }

    public record Request(@NotNull UUID cohortId, @NotNull @Min(0) Long expectedPriceMinor,
            @NotNull @Pattern(regexp = "TEST_CARD") String paymentMethod) {}
}
