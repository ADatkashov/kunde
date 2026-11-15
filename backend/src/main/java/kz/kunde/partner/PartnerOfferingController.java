package kz.kunde.partner;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.partner.PartnerOfferingService.OfferingInput;
import kz.kunde.partner.PartnerOfferingService.OfferingView;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/** ADR-018 step 3: partner offering management; all access is decided by the caller's membership of the path partner. */
@RestController
@RequestMapping("/api/v1/partner/partners/{partnerId}/offerings")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class PartnerOfferingController {
    private final PartnerOfferingService offerings;

    public PartnerOfferingController(PartnerOfferingService offerings) {
        this.offerings = offerings;
    }

    @PostMapping
    ResponseEntity<OfferingView> create(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @Valid @RequestBody CreateRequest request) {
        var view = offerings.create(user(principal), partnerId, new OfferingInput(request.categoryId(), request.kind(),
                request.nameRu(), request.nameKk(), request.nameEn(), request.priceMinor(), request.availability()));
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(view);
    }

    @GetMapping
    ResponseEntity<List<OfferingView>> list(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return ok(offerings.list(user(principal), partnerId));
    }

    @GetMapping("/{offeringId}")
    ResponseEntity<OfferingView> get(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID offeringId) {
        return ok(offerings.get(user(principal), partnerId, offeringId));
    }

    @PatchMapping("/{offeringId}")
    ResponseEntity<OfferingView> update(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID offeringId, @Valid @RequestBody UpdateRequest request) {
        return ok(offerings.update(user(principal), partnerId, offeringId, new OfferingInput(null, null,
                request.nameRu(), request.nameKk(), request.nameEn(), request.priceMinor(), request.availability()),
                request.version()));
    }

    @PostMapping("/{offeringId}/publish")
    ResponseEntity<OfferingView> publish(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID offeringId, @Valid @RequestBody VersionRequest request) {
        return ok(offerings.publish(user(principal), partnerId, offeringId, request.version()));
    }

    @PostMapping("/{offeringId}/unpublish")
    ResponseEntity<OfferingView> unpublish(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID offeringId, @Valid @RequestBody VersionRequest request) {
        return ok(offerings.unpublish(user(principal), partnerId, offeringId, request.version()));
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record CreateRequest(@NotNull UUID categoryId, @NotBlank String kind, @NotBlank @Size(max = 200) String nameRu,
            @NotBlank @Size(max = 200) String nameKk, @Size(max = 200) String nameEn, Long priceMinor, String availability) {}

    public record UpdateRequest(@NotBlank @Size(max = 200) String nameRu, @NotBlank @Size(max = 200) String nameKk,
            @Size(max = 200) String nameEn, Long priceMinor, String availability, @NotNull @PositiveOrZero Long version) {}

    public record VersionRequest(@NotNull @PositiveOrZero Long version) {}
}
