package kz.kunde.rides;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.util.List;
import java.util.Locale;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideMatching.Point;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
@RequestMapping("/api/v1/rides")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
public class RideRoutingController {
    private final RidesFlags flags;
    private final ObjectProvider<RideRouting> routing;

    public RideRoutingController(RidesFlags flags, ObjectProvider<RideRouting> routing) {
        this.flags = flags;
        this.routing = routing;
    }

    @PostMapping("/route-preview")
    public ResponseEntity<RideRouting.Route> preview(@Valid @RequestBody RouteRequest request) {
        var route = availableRouting().route(request.pickup().point(), request.destination().point())
                .orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "RIDE_ROUTE_NOT_FOUND",
                        "No road route was found for these points"));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(route);
    }

    @PostMapping("/address-search")
    public ResponseEntity<List<RideRouting.Place>> search(@Valid @RequestBody SearchRequest request) {
        var places = availableRouting().geocode(request.query().strip(), request.language().locale());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(places);
    }

    @PostMapping("/reverse-geocode")
    public ResponseEntity<RideRouting.Place> reverse(@Valid @RequestBody ReverseRequest request) {
        var place = availableRouting().reverseGeocode(request.coordinates().point(), request.language().locale())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RIDE_ADDRESS_NOT_FOUND",
                        "No address was found for this point"));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(place);
    }

    private RideRouting availableRouting() {
        if (!flags.consumerAvailable()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RIDES_UNAVAILABLE", "Rides is currently unavailable");
        }
        var provider = routing.getIfAvailable();
        if (provider == null) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "RIDES_ROUTING_UNAVAILABLE",
                    "Road routing is currently unavailable");
        }
        return provider;
    }

    public enum Language {
        ru, kk, en;

        Locale locale() {
            return Locale.forLanguageTag(name());
        }
    }

    public record SearchRequest(@NotBlank @Size(min = 2, max = 160) String query, @NotNull Language language) {}

    public record ReverseRequest(@NotNull @Valid Coordinates coordinates, @NotNull Language language) {}

    public record RouteRequest(@NotNull @Valid Coordinates pickup, @NotNull @Valid Coordinates destination) {}

    public record Coordinates(
            @NotNull @DecimalMin("-90") @DecimalMax("90") BigDecimal latitude,
            @NotNull @DecimalMin("-180") @DecimalMax("180") BigDecimal longitude) {
        Point point() {
            return new Point(latitude.doubleValue(), longitude.doubleValue());
        }
    }
}
