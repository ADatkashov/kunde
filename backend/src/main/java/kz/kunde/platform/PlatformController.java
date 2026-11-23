package kz.kunde.platform;

import org.springframework.beans.factory.annotation.Autowired;
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
    private final FeatureToggles toggles;
    private final boolean autoCeiling;
    private final boolean mapsEnabled;

    public PlatformController(String issuerUri, String audience, boolean foodEnabled, boolean bookingEnabled, FeatureToggles toggles) {
        this(issuerUri, audience, foodEnabled, bookingEnabled, toggles, false);
    }

    @Autowired
    public PlatformController(@Value("${app.security.oidc.issuer-uri:}") String issuerUri,
            @Value("${app.security.oidc.audience:}") String audience,
            @Value("${app.food.enabled:false}") boolean foodEnabled,
            @Value("${app.booking.enabled:false}") boolean bookingEnabled, FeatureToggles toggles,
            @Value("${app.maps.enabled:false}") boolean mapsEnabled) {
        this.mapsEnabled = mapsEnabled;
        this.oidcConfigured = !issuerUri.isBlank() && !audience.isBlank();
        this.foodEnabled = foodEnabled;
        this.bookingEnabled = bookingEnabled;
        this.toggles = toggles;
        this.autoCeiling = bookingEnabled;
    }


    @GetMapping("/capabilities")
    public PlatformCapabilities capabilities() {
        var rides = toggles.rides();
        var delivery = toggles.delivery();
        return new PlatformCapabilities("FOUNDATION", foodEnabled, oidcConfigured, false, bookingEnabled, rides.consumerAvailable(),
                rides.partnerAvailable(), delivery.consumerAvailable(),
                delivery.enabled() && delivery.partnerEnabled(),
                delivery.enabled() && delivery.syntheticRoutingEnabled(),
                delivery.enabled() && delivery.executorEnabled(), autoCeiling && toggles.enabled(FeatureToggles.Feature.AUTO), toggles.enabled(FeatureToggles.Feature.LEISURE),
                toggles.enabled(FeatureToggles.Feature.HEALTH), toggles.enabled(FeatureToggles.Feature.EDUCATION),
                toggles.enabled(FeatureToggles.Feature.GROCERIES), toggles.enabled(FeatureToggles.Feature.EVENTS),
                bookingEnabled && toggles.enabled(FeatureToggles.Feature.HOME_SERVICES), mapsEnabled,
                bookingEnabled && toggles.enabled(FeatureToggles.Feature.BEAUTY));
    }

    public record PlatformCapabilities(
            String releaseStage,
            boolean marketplaceEnabled,
            boolean oidcIssuerConfigured,
            boolean aiEnabled,
            boolean bookingEnabled,
            boolean ridesEnabled, boolean ridesFleetEnabled, boolean deliveryEnabled, boolean deliveryPartnerEnabled,
            boolean deliverySyntheticRouting, boolean deliveryExecutorEnabled, boolean autoEnabled, boolean leisureEnabled, boolean healthEnabled, boolean educationEnabled,
            boolean groceriesEnabled, boolean eventsEnabled, boolean homeServicesEnabled,
            /** The KUNDE Maps Platform is the configured routing provider; clients show map UI only together with the product flag. */
            boolean mapsEnabled,
            /** Effective switch for Beauty &amp; Care (BEAUTY_ENABLED); off by default. */
            boolean beautyEnabled) {}
}
