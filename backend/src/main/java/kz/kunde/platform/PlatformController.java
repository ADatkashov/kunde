package kz.kunde.platform;

import kz.kunde.delivery.DeliveryProperties;
import kz.kunde.rides.RidesFlags;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class PlatformController {
    private final boolean oidcConfigured;
    private final boolean foodEnabled;
    private final boolean bookingEnabled;
    private final RidesFlags rides;
    private final DeliveryProperties delivery;

    public PlatformController(@Value("${app.security.oidc.issuer-uri:}") String issuerUri,
            @Value("${app.security.oidc.audience:}") String audience,
            @Value("${app.food.enabled:false}") boolean foodEnabled,
            @Value("${app.booking.enabled:false}") boolean bookingEnabled, RidesFlags rides, DeliveryProperties delivery) {
        this.oidcConfigured = !issuerUri.isBlank() && !audience.isBlank();
        this.foodEnabled = foodEnabled;
        this.bookingEnabled = bookingEnabled;
        this.rides = rides;
        this.delivery = delivery;
    }


    @GetMapping("/capabilities")
    public PlatformCapabilities capabilities() {
        return new PlatformCapabilities("FOUNDATION", foodEnabled, oidcConfigured, false, bookingEnabled, rides.consumerAvailable(),
                rides.partnerAvailable(), delivery.consumerAvailable());
    }

    public record PlatformCapabilities(
            String releaseStage,
            boolean marketplaceEnabled,
            boolean oidcIssuerConfigured,
            boolean aiEnabled,
            boolean bookingEnabled,
            boolean ridesEnabled, boolean ridesFleetEnabled, boolean deliveryEnabled) {}
}
