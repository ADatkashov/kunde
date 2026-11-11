package kz.kunde.identity;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.access.prepost.PreAuthorize;

@RestController
@RequestMapping("/api/v1/me")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerIdentityController {
    private final ConsumerIdentityService identity;

    public ConsumerIdentityController(ConsumerIdentityService identity) {
        this.identity = identity;
    }

    @GetMapping
    ResponseEntity<ConsumerProfile> me(@AuthenticationPrincipal Jwt principal) {
        return privateResponse(identity.get(principal));
    }

    @PatchMapping
    ResponseEntity<ConsumerProfile> update(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody ProfileUpdate request) {
        return privateResponse(identity.update(principal, request.displayName(), request.preferredLanguage(), request.version()));
    }

    @GetMapping("/sessions")
    void sessions() {
        throw sessionsUnavailable();
    }

    @DeleteMapping({"/sessions", "/sessions/{id}"})
    void terminateSessions() {
        throw sessionsUnavailable();
    }

    private static ApiException sessionsUnavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "SESSION_MANAGEMENT_UNAVAILABLE",
                "Account session management is unavailable");
    }

    private static ResponseEntity<ConsumerProfile> privateResponse(ConsumerProfile profile) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(profile);
    }

    public record ProfileUpdate(
            @NotBlank @Size(max = 80) @Pattern(regexp = "[^\\p{Cc}\\p{Cf}]+") String displayName,
            @NotNull @Pattern(regexp = "ru|kk|en") String preferredLanguage,
            @NotNull @PositiveOrZero Long version) {}
}
