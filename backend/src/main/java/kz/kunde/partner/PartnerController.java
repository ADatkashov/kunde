package kz.kunde.partner;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * ADR-018 step 2: partner onboarding and profile for the own phone-OTP auth. Partner ids in paths are never
 * trusted: access is decided by the caller's active membership (404 for strangers, same as unknown ids).
 * A new applicant has to refresh the token to receive the {@code kunde.partner} scope.
 */
@RestController
@RequestMapping("/api/v1/partner")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class PartnerController {
    private final PartnerService partners;
    private final PartnerOfferingService offerings;

    public PartnerController(PartnerService partners, PartnerOfferingService offerings) {
        this.partners = partners;
        this.offerings = offerings;
    }

    /** Any consumer may apply; the applicant becomes the first OWNER and the partner starts as PENDING_REVIEW. */
    @PostMapping("/applications")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    ResponseEntity<PartnerService.PartnerView> apply(@AuthenticationPrincipal Jwt principal,
            @Valid @RequestBody ApplicationRequest request) {
        var view = partners.apply(user(principal), request.displayName());
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(view);
    }

    /** Categories an offering can be filed under (ADR-018 step 5 form); any partner-scoped caller may read them. */
    @GetMapping("/categories")
    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    ResponseEntity<List<PartnerOfferingService.CategoryOption>> categories() {
        return privateResponse(offerings.categories());
    }

    @GetMapping("/partners")
    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    ResponseEntity<List<PartnerService.MyPartnerView>> mine(@AuthenticationPrincipal Jwt principal) {
        return privateResponse(partners.listMine(user(principal)));
    }

    @GetMapping("/partners/{partnerId}")
    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    ResponseEntity<PartnerService.PartnerView> get(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return privateResponse(partners.get(user(principal), partnerId));
    }

    @PatchMapping("/partners/{partnerId}")
    @PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
    ResponseEntity<PartnerService.PartnerView> update(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @Valid @RequestBody ProfileUpdate request) {
        return privateResponse(partners.updateProfile(user(principal), partnerId, request.displayName(), request.version()));
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> privateResponse(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record ApplicationRequest(@NotBlank @Size(max = 120) String displayName) {}

    public record ProfileUpdate(@NotBlank @Size(max = 120) String displayName, @NotNull @PositiveOrZero Long version) {}
}
