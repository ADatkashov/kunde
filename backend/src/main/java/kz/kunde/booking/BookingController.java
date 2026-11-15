package kz.kunde.booking;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.List;
import java.util.UUID;
import kz.kunde.booking.BookingService.BookRequest;
import kz.kunde.booking.BookingService.BookingView;
import kz.kunde.identity.ConsumerIdentityService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Authenticated bookings of the caller: create (idempotent), history, details, free cancellation before the start. */
@RestController
@Validated
@RequestMapping("/api/v1/booking/bookings")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BookingController {
    private final BookingService bookings;
    private final ConsumerIdentityService identity;

    public BookingController(BookingService bookings, ConsumerIdentityService identity) {
        this.bookings = bookings;
        this.identity = identity;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    @PostMapping
    public ResponseEntity<BookingView> book(@AuthenticationPrincipal Jwt principal,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody BookRequest request) {
        var booked = bookings.book(identity.get(principal).id(), request, idempotencyKey);
        return noStore(booked.created() ? HttpStatus.CREATED : HttpStatus.OK, booked.booking());
    }

    @GetMapping
    public ResponseEntity<List<BookingView>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, bookings.list(identity.get(principal).id(), limit, offset));
    }

    @GetMapping("/{id}")
    public ResponseEntity<BookingView> get(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return noStore(HttpStatus.OK, bookings.get(identity.get(principal).id(), id));
    }

    @PostMapping("/{id}/cancel")
    public ResponseEntity<BookingView> cancel(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id) {
        return noStore(HttpStatus.OK, bookings.cancel(identity.get(principal).id(), id));
    }
}
