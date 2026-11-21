package kz.kunde.education;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.education.EducationOperationsService.*;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class EducationOperationsController {
    private static final String PARTNER = "/partner/partners/{partner}/education";
    private static final String ADMIN = "/admin/education";
    private static final String EXECUTOR = "/executor/education";
    private final EducationOperationsService operations;
    private final ConsumerIdentityService identity;

    public EducationOperationsController(EducationOperationsService operations, ConsumerIdentityService identity) {
        this.operations = operations;
        this.identity = identity;
    }

    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    @GetMapping(PARTNER + "/courses")
    public ResponseEntity<List<Course>> list(@AuthenticationPrincipal Jwt actor, @PathVariable UUID partner) {
        return ok(operations.partnerCourses(user(actor), partner));
    }

    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    @GetMapping(PARTNER + "/instructors")
    public ResponseEntity<List<Instructor>> instructors(@AuthenticationPrincipal Jwt actor, @PathVariable UUID partner) {
        return ok(operations.instructors(user(actor), partner));
    }

    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    @PostMapping(PARTNER + "/courses")
    public ResponseEntity<Course> create(@AuthenticationPrincipal Jwt actor, @PathVariable UUID partner, @Valid @RequestBody Draft draft) {
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(operations.create(user(actor), partner, draft));
    }

    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    @PostMapping(PARTNER + "/courses/{id}/submit")
    public ResponseEntity<Course> submit(@AuthenticationPrincipal Jwt actor, @PathVariable UUID partner, @PathVariable UUID id) {
        return ok(operations.submit(user(actor), partner, id));
    }

    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    @PostMapping(PARTNER + "/courses/{id}/cohorts")
    public ResponseEntity<Session> createSession(@AuthenticationPrincipal Jwt actor, @PathVariable UUID partner,
            @PathVariable UUID id, @Valid @RequestBody CohortInput input) {
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(operations.createSession(user(actor), partner, id, input));
    }

    @PreAuthorize("@adminAccessPolicy.allowed(authentication)")
    @GetMapping(ADMIN + "/courses")
    public ResponseEntity<List<Course>> moderation(@AuthenticationPrincipal Jwt actor) {
        return ok(operations.moderation(user(actor)));
    }

    @PreAuthorize("@adminAccessPolicy.allowed(authentication)")
    @PostMapping(ADMIN + "/courses/{id}/decision")
    public ResponseEntity<Course> decision(@AuthenticationPrincipal Jwt actor, @PathVariable UUID id, @Valid @RequestBody Moderation input) {
        return ok(operations.moderate(user(actor), id, input.decision(), input.reason()));
    }

    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @GetMapping(EXECUTOR + "/sessions")
    public ResponseEntity<List<Session>> sessions(@AuthenticationPrincipal Jwt actor) {
        return ok(operations.instructorSessions(identity.get(actor).id()));
    }

    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @GetMapping(EXECUTOR + "/sessions/{session}/roster")
    public ResponseEntity<List<Learner>> roster(@AuthenticationPrincipal Jwt actor, @PathVariable UUID session) {
        return ok(operations.roster(identity.get(actor).id(), session));
    }

    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @PutMapping(EXECUTOR + "/sessions/{session}/roster/{enrollment}")
    public ResponseEntity<Learner> attendance(@AuthenticationPrincipal Jwt actor, @PathVariable UUID session,
            @PathVariable UUID enrollment, @Valid @RequestBody AttendanceInput input) {
        return ok(operations.attendance(identity.get(actor).id(), session, enrollment, input.status()));
    }

    private static UUID user(Jwt actor) {
        return PartnerAccessPolicy.userId(actor).orElseThrow(
                () -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T data) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(data);
    }

    public record Moderation(@NotNull Decision decision, @NotBlank @Size(max=200) String reason) {}
    public record AttendanceInput(@NotNull Attendance status) {}
}
