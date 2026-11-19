package kz.kunde.rides;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.rides.RideDispatchService.DriverTrip;
import kz.kunde.rides.RideDispatchService.Offer;
import kz.kunde.rides.RideState.Action;
import kz.kunde.rides.RideDriverService.Driver;
import kz.kunde.rides.RideMatching.RideClass;
import kz.kunde.rides.RideRoutingController.Coordinates;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/executor/rides")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class RideDriverController {
    private final ConsumerIdentityService identity;
    private final RideDriverService drivers;

    private final RideDispatchService dispatch;

    public RideDriverController(ConsumerIdentityService identity, RideDriverService drivers, RideDispatchService dispatch) {
        this.identity = identity;
        this.drivers = drivers;
        this.dispatch = dispatch;
    }

    @GetMapping("/profile")
    ResponseEntity<Driver> profile(@AuthenticationPrincipal Jwt principal) {
        return ok(drivers.profile(identity.get(principal).id()));
    }

    @PostMapping("/profile")
    ResponseEntity<Driver> register(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody Registration request) {
        return ok(drivers.register(identity.get(principal).id(), request.displayName()));
    }

    @PostMapping("/vehicle")
    ResponseEntity<Driver> vehicle(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody VehicleRegistration request) {
        return ok(drivers.registerVehicle(identity.get(principal).id(), request.description(), request.plate(),
                request.rideClass()));
    }

    @PutMapping("/availability")
    ResponseEntity<Driver> availability(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody Availability request) {
        return ok(drivers.availability(identity.get(principal).id(), request.online()));
    }

    @PutMapping("/location")
    ResponseEntity<Void> location(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody Coordinates request) {
        drivers.location(identity.get(principal).id(), request);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/offers")
    ResponseEntity<List<Offer>> offers(@AuthenticationPrincipal Jwt principal) {
        return ok(dispatch.offers(identity.get(principal).id()));
    }

    @PostMapping("/offers/{offerId}/response")
    ResponseEntity<Void> respond(@AuthenticationPrincipal Jwt principal, @PathVariable UUID offerId,
            @Valid @RequestBody OfferResponse request) {
        dispatch.respond(identity.get(principal).id(), offerId, request.accept());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/trips/{rideId}/progress")
    ResponseEntity<Void> progress(@AuthenticationPrincipal Jwt principal, @PathVariable UUID rideId,
            @Valid @RequestBody Progress request) {
        dispatch.progress(identity.get(principal).id(), rideId, Action.valueOf(request.step().name()));
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/trips")
    ResponseEntity<List<DriverTrip>> history(@AuthenticationPrincipal Jwt principal) {
        return ok(dispatch.history(identity.get(principal).id()));
    }

    private static <T> ResponseEntity<T> ok(T driver) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(driver);
    }

    public record Registration(@NotBlank @Size(max = 80) String displayName) {}
    public record VehicleRegistration(@NotBlank @Size(max = 100) String description,
            @NotNull @Pattern(regexp = "[A-Za-z0-9]{3,16}") String plate, @NotNull RideClass rideClass) {}
    public enum TripStep { DEPART, ARRIVE, START, COMPLETE, CANCEL }
    public record Progress(@NotNull TripStep step) {}
    public record OfferResponse(@NotNull Boolean accept) {}
    public record Availability(@NotNull Boolean online) {}
}
