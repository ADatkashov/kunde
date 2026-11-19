package kz.kunde.auto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import kz.kunde.auto.AutoJobService.JobView;
import kz.kunde.auto.AutoJobService.SpecialistJob;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/** Customer on-site requests and the AUTO_SPECIALIST executor API. Both need an authenticated own-auth user. */
@RestController
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoJobController {
    private final AutoJobService jobs;
    private final ConsumerIdentityService identity;

    public AutoJobController(AutoJobService jobs, ConsumerIdentityService identity) {
        this.jobs = jobs;
        this.identity = identity;
    }

    private UUID user(Jwt p) { return identity.get(p).id(); }

    private static <T> ResponseEntity<T> ok(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    public record JobBody(@NotNull UUID vehicleId, @NotBlank String category, @Size(max = 300) String description,
            @NotBlank @Size(max = 300) String addressText, @NotNull BigDecimal latitude, @NotNull BigDecimal longitude) {}

    public record DecisionBody(@NotNull Boolean approve) {}

    public record EnrollBody(@NotBlank @Size(max = 80) String name) {}

    public record OnlineBody(@NotNull Boolean online) {}

    public record PointBody(@NotNull BigDecimal latitude, @NotNull BigDecimal longitude) {}

    public record ProgressBody(@NotNull AutoJobService.Action action, Long finalPriceMinor) {}

    // ---- customer ----
    @PostMapping("/api/v1/auto/jobs")
    public ResponseEntity<JobView> request(@AuthenticationPrincipal Jwt p, @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody JobBody b) {
        return ok(HttpStatus.CREATED, jobs.request(user(p), new AutoJobService.JobRequest(b.vehicleId(), b.category(), b.description(), b.addressText(),
                b.latitude(), b.longitude()), key));
    }

    @GetMapping("/api/v1/auto/jobs")
    public ResponseEntity<List<JobView>> list(@AuthenticationPrincipal Jwt p) {
        return ok(HttpStatus.OK, jobs.jobs(user(p)));
    }

    @GetMapping("/api/v1/auto/jobs/{id}")
    public ResponseEntity<JobView> get(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        return ok(HttpStatus.OK, jobs.job(user(p), id));
    }

    @PostMapping("/api/v1/auto/jobs/{id}/cancel")
    public ResponseEntity<JobView> cancel(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        return ok(HttpStatus.OK, jobs.cancel(user(p), id));
    }

    @PostMapping("/api/v1/auto/jobs/{id}/price-decision")
    public ResponseEntity<JobView> decide(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @Valid @RequestBody DecisionBody b) {
        return ok(HttpStatus.OK, jobs.decidePrice(user(p), id, b.approve()));
    }

    // ---- specialist (Executor, AUTO_SPECIALIST) ----
    @GetMapping("/api/v1/executor/auto/profile")
    public ResponseEntity<AutoJobService.Profile> profile(@AuthenticationPrincipal Jwt p) {
        return ok(HttpStatus.OK, jobs.profile(user(p)));
    }

    @PostMapping("/api/v1/executor/auto/profile")
    public ResponseEntity<AutoJobService.Profile> enroll(@AuthenticationPrincipal Jwt p, @Valid @RequestBody EnrollBody b) {
        return ok(HttpStatus.OK, jobs.register(user(p), b.name()));
    }

    @PutMapping("/api/v1/executor/auto/availability")
    public ResponseEntity<AutoJobService.Profile> availability(@AuthenticationPrincipal Jwt p, @Valid @RequestBody OnlineBody b) {
        return ok(HttpStatus.OK, jobs.availability(user(p), b.online()));
    }

    @PutMapping("/api/v1/executor/auto/location")
    public ResponseEntity<Void> location(@AuthenticationPrincipal Jwt p, @Valid @RequestBody PointBody b) {
        jobs.location(user(p), b.latitude(), b.longitude());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @GetMapping("/api/v1/executor/auto/jobs/available")
    public ResponseEntity<List<SpecialistJob>> available(@AuthenticationPrincipal Jwt p) {
        return ok(HttpStatus.OK, jobs.available(user(p)));
    }

    @GetMapping("/api/v1/executor/auto/jobs")
    public ResponseEntity<List<SpecialistJob>> mine(@AuthenticationPrincipal Jwt p) {
        return ok(HttpStatus.OK, jobs.mine(user(p)));
    }

    @PostMapping("/api/v1/executor/auto/jobs/{id}/accept")
    public ResponseEntity<SpecialistJob> accept(@AuthenticationPrincipal Jwt p, @PathVariable UUID id) {
        return ok(HttpStatus.OK, jobs.accept(user(p), id));
    }

    @PostMapping("/api/v1/executor/auto/jobs/{id}/progress")
    public ResponseEntity<SpecialistJob> progress(@AuthenticationPrincipal Jwt p, @PathVariable UUID id, @Valid @RequestBody ProgressBody b) {
        return ok(HttpStatus.OK, jobs.progress(user(p), id, b.action(), b.finalPriceMinor()));
    }
}
