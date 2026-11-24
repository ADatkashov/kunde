package kz.kunde.leisure;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import java.util.UUID;
import kz.kunde.leisure.LeisurePartnerService.*;
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

/** Partner Leisure API (ADR-018 partner scope + per-request membership and role check in the service). */
@RestController
@Validated
@RequestMapping("/api/v1/partner/partners/{partnerId}/leisure")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class LeisurePartnerController {
    private final LeisurePartnerService service;
    private final LeisureExecutorService executors;

    public LeisurePartnerController(LeisurePartnerService service, LeisureExecutorService executors) {
        this.service = service;
        this.executors = executors;
    }

    private static UUID user(Jwt principal) {
        return PartnerAccessPolicy.userId(principal).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
    }

    private static <T> ResponseEntity<T> ok(T body) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body); }

    private static <T> ResponseEntity<T> created(T body) { return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore()).body(body); }

    public record VersionedVenue(VenueInput venue, Long version) {}

    public record VersionedEvent(EventInput event, Long version) {}

    public record ReasonBody(String reason) {}

    public record ActionBody(@Pattern(regexp = "CONFIRM|REJECT|CANCEL") String action, String reason) {}

    public record CapacityBody(@Min(1) @Max(5000) Integer capacity) {}

    public record CheckinBody(String code, UUID sessionId) {}

    @GetMapping("/venues")
    ResponseEntity<List<VenueRow>> venues(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId) { return ok(service.venues(user(p), partnerId)); }

    @PostMapping("/venues")
    ResponseEntity<VenueRow> createVenue(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestBody VenueInput body) {
        return created(service.createVenue(user(p), partnerId, body));
    }

    @PutMapping("/venues/{venueId}")
    ResponseEntity<VenueRow> updateVenue(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID venueId, @RequestBody VersionedVenue body) {
        if (body.version() == null || body.venue() == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "venue and version are required"); }
        return ok(service.updateVenue(user(p), partnerId, venueId, body.venue(), body.version()));
    }

    @PostMapping("/venues/{venueId}/submit")
    ResponseEntity<VenueRow> submitVenue(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID venueId) {
        return ok(service.submitVenue(user(p), partnerId, venueId));
    }

    @GetMapping("/events")
    ResponseEntity<List<EventRow>> events(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestParam(required = false) UUID venueId,
            @RequestParam(required = false) String product) {
        return ok(service.events(user(p), partnerId, venueId, product));
    }

    @PostMapping("/venues/{venueId}/events")
    ResponseEntity<EventRow> createEvent(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID venueId, @RequestBody EventInput body) {
        return created(service.createEvent(user(p), partnerId, venueId, body));
    }

    @PutMapping("/events/{eventId}")
    ResponseEntity<EventRow> updateEvent(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId, @RequestBody VersionedEvent body) {
        if (body.version() == null || body.event() == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "event and version are required"); }
        return ok(service.updateEvent(user(p), partnerId, eventId, body.event(), body.version()));
    }

    @PostMapping("/events/{eventId}/submit")
    ResponseEntity<EventRow> submitEvent(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId) {
        return ok(service.submitEvent(user(p), partnerId, eventId));
    }

    @PostMapping("/events/{eventId}/archive")
    ResponseEntity<EventRow> archiveEvent(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId) {
        return ok(service.archiveEvent(user(p), partnerId, eventId));
    }

    @GetMapping("/events/{eventId}/ticket-types")
    ResponseEntity<List<TicketTypeRow>> ticketTypes(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId) {
        return ok(service.ticketTypes(user(p), partnerId, eventId));
    }

    @PostMapping("/events/{eventId}/ticket-types")
    ResponseEntity<TicketTypeRow> createTicketType(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId, @RequestBody TicketTypeInput body) {
        return created(service.saveTicketType(user(p), partnerId, eventId, null, body));
    }

    @PutMapping("/events/{eventId}/ticket-types/{typeId}")
    ResponseEntity<TicketTypeRow> updateTicketType(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId, @PathVariable UUID typeId,
            @RequestBody TicketTypeInput body) {
        return ok(service.saveTicketType(user(p), partnerId, eventId, typeId, body));
    }

    @GetMapping("/events/{eventId}/sessions")
    ResponseEntity<List<SessionRow>> sessions(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId, @RequestParam(defaultValue = "false") boolean past,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(service.sessions(user(p), partnerId, eventId, past, limit, offset));
    }

    @PostMapping("/events/{eventId}/sessions")
    ResponseEntity<List<SessionRow>> createSessions(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID eventId, @RequestBody SessionInput body) {
        return created(service.createSessions(user(p), partnerId, eventId, body));
    }

    @PatchMapping("/sessions/{sessionId}")
    ResponseEntity<SessionRow> capacity(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID sessionId, @RequestBody CapacityBody body) {
        if (body.capacity() == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "CAPACITY_INVALID", "capacity is required"); }
        return ok(service.setCapacity(user(p), partnerId, sessionId, body.capacity()));
    }

    @PostMapping("/sessions/{sessionId}/cancel")
    ResponseEntity<SessionRow> cancelSession(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID sessionId, @RequestBody ReasonBody body) {
        return ok(service.cancelSession(user(p), partnerId, sessionId, body.reason()));
    }

    @GetMapping("/orders")
    ResponseEntity<List<PartnerOrder>> orders(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestParam(defaultValue = "upcoming") @Pattern(regexp = "requests|upcoming|history") String scope,
            @RequestParam(required = false) UUID eventId, @RequestParam(required = false) UUID sessionId, @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset,
            @RequestParam(required = false) String product) {
        return ok(service.orders(user(p), partnerId, scope, eventId, sessionId, limit, offset, product));
    }

    @GetMapping("/orders/{orderId}")
    ResponseEntity<PartnerOrder> order(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID orderId) { return ok(service.order(user(p), partnerId, orderId)); }

    @PostMapping("/orders/{orderId}/action")
    ResponseEntity<PartnerOrder> action(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID orderId, @RequestBody ActionBody body) {
        if (body.action() == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "action is required"); }
        return ok(service.act(user(p), partnerId, orderId, Action.valueOf(body.action()), body.reason()));
    }

    @PostMapping("/checkins")
    ResponseEntity<CheckinResult> checkin(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestBody CheckinBody body) {
        return ok(service.checkin(user(p), partnerId, body.code(), body.sessionId()));
    }

    @GetMapping("/checkins")
    ResponseEntity<List<CheckinRow>> checkins(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestParam(required = false) UUID sessionId,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit, @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(service.checkins(user(p), partnerId, sessionId, limit, offset));
    }

    @GetMapping("/stats")
    ResponseEntity<Stats> stats(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestParam(defaultValue = "7") @Min(1) @Max(90) int days,
            @RequestParam(required = false) String product) {
        return ok(service.stats(user(p), partnerId, days, product));
    }

    @GetMapping("/reports/sales")
    ResponseEntity<List<LeisurePartnerService.SalesLine>> salesReport(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId,
            @RequestParam(defaultValue = "30") @Min(1) @Max(90) int days, @RequestParam(required = false) String product) {
        return ok(service.salesReport(user(p), partnerId, days, product));
    }

    @GetMapping("/history")
    ResponseEntity<List<AuditRow>> history(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return ok(service.history(user(p), partnerId, limit, offset));
    }

    public record AssignBody(String phone, String role, String note) {}

    @GetMapping("/sessions/{sessionId}/assignments")
    ResponseEntity<List<LeisureExecutorService.Assignment>> assignments(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID sessionId) {
        return ok(executors.forSession(user(p), partnerId, sessionId));
    }

    @PostMapping("/sessions/{sessionId}/assignments")
    ResponseEntity<LeisureExecutorService.Assignment> assign(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID sessionId, @RequestBody AssignBody body) {
        return created(executors.assign(user(p), partnerId, sessionId, body.phone(), body.role(), body.note()));
    }

    @PostMapping("/assignments/{id}/cancel")
    ResponseEntity<LeisureExecutorService.Assignment> cancelAssignment(@AuthenticationPrincipal Jwt p, @PathVariable UUID partnerId, @PathVariable UUID id) {
        return ok(executors.partnerCancel(user(p), partnerId, id));
    }
}
