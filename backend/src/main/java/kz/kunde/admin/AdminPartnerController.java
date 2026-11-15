package kz.kunde.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants.Permission;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.PartnerView;
import kz.kunde.partner.PartnerVerification.Decision;
import kz.kunde.partner.PartnerVerification.Status;
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
 * ADR-018 step 4: manual partner verification by a KUNDE administrator. The token scope is an entry gate; each
 * request re-checks the PARTNER_VERIFICATION grant. Reviewers see no applicant personal data, decisions need the
 * current version, are written to the append-only verification history, and an administrator who is staff of the
 * partner cannot decide on it (enforced in {@link PartnerService#reviewVerification}).
 */
@RestController
@RequestMapping("/api/v1/admin/partners")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminPartnerController {
    private final PartnerService partners;
    private final AdminGrants grants;

    public AdminPartnerController(PartnerService partners, AdminGrants grants) {
        this.partners = partners;
        this.grants = grants;
    }

    @GetMapping
    ResponseEntity<List<PartnerService.ReviewQueueItem>> queue(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) String status) {
        grants.require(user(principal), Permission.PARTNER_VERIFICATION);
        Status filter = null;
        if (status != null && !status.isBlank()) {
            try {
                filter = Status.valueOf(status);
            } catch (IllegalArgumentException e) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_STATUS", "Unknown verification status");
            }
        }
        return ok(partners.reviewQueue(filter));
    }

    @GetMapping("/{partnerId}")
    ResponseEntity<PartnerDetail> detail(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        grants.require(user(principal), Permission.PARTNER_VERIFICATION);
        return ok(new PartnerDetail(partners.view(partnerId), partners.verificationHistory(partnerId)));
    }

    @PostMapping("/{partnerId}/decision")
    ResponseEntity<PartnerView> decide(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @Valid @RequestBody DecisionRequest request) {
        UUID reviewer = user(principal);
        grants.require(reviewer, Permission.PARTNER_VERIFICATION);
        return ok(partners.reviewVerification(reviewer, partnerId, request.decision(), request.reason(), request.version()));
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record PartnerDetail(PartnerView partner, List<PartnerService.VerificationHistoryItem> history) {}

    public record DecisionRequest(@NotNull Decision decision, @Size(max = 2000) String reason, @NotNull @PositiveOrZero Long version) {}
}
