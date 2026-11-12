package kz.kunde.identity;

import java.util.List;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/me/consents")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerConsentController {
    private final ConsumerConsentService consents;

    public ConsumerConsentController(ConsumerConsentService consents) {
        this.consents = consents;
    }

    @GetMapping
    ResponseEntity<List<ConsumerConsentService.ConsentStatus>> list(@AuthenticationPrincipal Jwt principal) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(consents.list(principal));
    }

    @PutMapping("/{policyId}")
    ResponseEntity<ConsumerConsentService.ConsentStatus> grant(
            @AuthenticationPrincipal Jwt principal, @PathVariable UUID policyId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(consents.change(principal, policyId, true));
    }

    @DeleteMapping("/{policyId}")
    ResponseEntity<ConsumerConsentService.ConsentStatus> withdraw(
            @AuthenticationPrincipal Jwt principal, @PathVariable UUID policyId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(consents.change(principal, policyId, false));
    }
}
