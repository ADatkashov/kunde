package kz.kunde.booking;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingPartnerService.Action;
import kz.kunde.booking.BookingPartnerService.HoursView;
import kz.kunde.booking.BookingPartnerService.MasterView;
import kz.kunde.booking.BookingPartnerService.PartnerBooking;
import kz.kunde.booking.BookingPartnerService.ServiceView;
import kz.kunde.booking.BookingPartnerService.VenueView;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

/** Partner booking inbox and availability (ADR-018 partner scope + per-request membership check). */
@RestController
@Validated
@RequestMapping("/api/v1/partner/partners/{partnerId}/booking")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class BookingPartnerController {
    private final BookingPartnerService service;

    public BookingPartnerController(BookingPartnerService service) {
        this.service = service;
    }

    @GetMapping("/bookings")
    ResponseEntity<List<PartnerBooking>> bookings(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @RequestParam(defaultValue = "requests") @Pattern(regexp = "requests|upcoming|history") String scope,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(service.list(user(principal), partnerId, scope, limit, offset));
    }

    @GetMapping("/bookings/{bookingId}")
    ResponseEntity<PartnerBooking> booking(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID bookingId) {
        return ok(service.get(user(principal), partnerId, bookingId));
    }

    @PostMapping("/bookings/{bookingId}/action")
    ResponseEntity<PartnerBooking> action(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID bookingId, @Valid @RequestBody ActionRequest request) {
        return ok(service.act(user(principal), partnerId, bookingId, Action.valueOf(request.action()), request.reason()));
    }

    @GetMapping("/venues")
    ResponseEntity<List<VenueView>> venues(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        return ok(service.venues(user(principal), partnerId));
    }

    @PatchMapping("/venues/{venueId}")
    ResponseEntity<VenueView> venue(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID venueId, @Valid @RequestBody OpenRequest request) {
        return ok(service.setVenueOpen(user(principal), partnerId, venueId, request.open()));
    }

    @GetMapping("/venues/{venueId}/services")
    ResponseEntity<List<ServiceView>> services(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID venueId) {
        return ok(service.services(user(principal), partnerId, venueId));
    }

    @PatchMapping("/venues/{venueId}/services/{serviceId}")
    ResponseEntity<ServiceView> service(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID venueId, @PathVariable UUID serviceId, @Valid @RequestBody AvailableRequest request) {
        return ok(service.setServiceAvailable(user(principal), partnerId, venueId, serviceId, request.available()));
    }

    @GetMapping("/venues/{venueId}/masters")
    ResponseEntity<List<MasterView>> masters(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID venueId) {
        return ok(service.masters(user(principal), partnerId, venueId));
    }

    @PatchMapping("/venues/{venueId}/masters/{masterId}")
    ResponseEntity<MasterView> master(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID venueId, @PathVariable UUID masterId, @Valid @RequestBody ActiveRequest request) {
        return ok(service.setMasterActive(user(principal), partnerId, venueId, masterId, request.active()));
    }

    @PutMapping("/venues/{venueId}/masters/{masterId}/hours")
    ResponseEntity<MasterView> hours(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId,
            @PathVariable UUID venueId, @PathVariable UUID masterId, @Valid @RequestBody HoursRequest request) {
        return ok(service.setHours(user(principal), partnerId, venueId, masterId, request.hours()));
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }

    public record ActionRequest(@NotNull @Pattern(regexp = "CONFIRM|REJECT|CANCEL|COMPLETE") String action,
            @Size(max = 300) String reason) {}

    public record OpenRequest(@NotNull Boolean open) {}

    public record AvailableRequest(@NotNull Boolean available) {}

    public record ActiveRequest(@NotNull Boolean active) {}

    public record HoursRequest(@NotNull @Size(max = 7) List<@Valid @NotNull HoursView> hours) {}
}
