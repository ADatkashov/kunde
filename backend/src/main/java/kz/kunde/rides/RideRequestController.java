package kz.kunde.rides;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.rides.RideDispatchService.DriverLocation;
import kz.kunde.rides.RideMatching.RideClass;
import kz.kunde.rides.RideQuoteService.Quote;
import kz.kunde.rides.RideRequestService.RideView;
import kz.kunde.rides.RideRoutingController.Coordinates;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/rides")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class RideRequestController {
    private final ConsumerIdentityService identity;
    private final RideRequestService rides;

    private final RideQuoteService quotes;

    private final RideDispatchService dispatch;

    public RideRequestController(ConsumerIdentityService identity, RideRequestService rides, RideQuoteService quotes,
            RideDispatchService dispatch) {
        this.identity = identity;
        this.rides = rides;
        this.quotes = quotes;
        this.dispatch = dispatch;
    }

    @PostMapping("/quotes")
    public ResponseEntity<Quote> quote(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody CreateQuote request) {
        return noStore(HttpStatus.CREATED, quotes.issue(identity.get(principal).id(), request.rideClass(),
                request.pickup(), request.destination()));
    }

    @PostMapping
    public ResponseEntity<RideView> create(@AuthenticationPrincipal Jwt principal,
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody CreateRide request) {
        var result = rides.create(identity.get(principal).id(), request.quoteId(), key);
        return noStore(result.created() ? HttpStatus.CREATED : HttpStatus.OK, result.ride());
    }

    @GetMapping
    public ResponseEntity<List<RideView>> history(@AuthenticationPrincipal Jwt principal,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        return noStore(HttpStatus.OK, rides.list(identity.get(principal).id(), limit, offset));
    }

    @GetMapping("/{rideId}")
    public ResponseEntity<RideView> detail(@AuthenticationPrincipal Jwt principal, @PathVariable UUID rideId) {
        return noStore(HttpStatus.OK, rides.get(identity.get(principal).id(), rideId));
    }

    @GetMapping("/{rideId}/location")
    public ResponseEntity<DriverLocation> location(@AuthenticationPrincipal Jwt principal, @PathVariable UUID rideId) {
        return dispatch.driverLocation(identity.get(principal).id(), rideId)
                .map(location -> noStore(HttpStatus.OK, location))
                .orElseGet(() -> ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build());
    }

    @PostMapping("/{rideId}/dispatch")
    public ResponseEntity<RideView> dispatch(@AuthenticationPrincipal Jwt principal, @PathVariable UUID rideId) {
        var customer = identity.get(principal).id();
        dispatch.search(customer, rideId);
        return noStore(HttpStatus.OK, rides.get(customer, rideId));
    }

    @PostMapping("/{rideId}/cancel")
    public ResponseEntity<RideView> cancel(@AuthenticationPrincipal Jwt principal, @PathVariable UUID rideId) {
        return noStore(HttpStatus.OK, rides.cancel(identity.get(principal).id(), rideId));
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    public record CreateQuote(@NotNull RideClass rideClass, @NotNull @Valid Coordinates pickup,
            @NotNull @Valid Coordinates destination) {}

    public record CreateRide(@NotNull UUID quoteId) {}
}
