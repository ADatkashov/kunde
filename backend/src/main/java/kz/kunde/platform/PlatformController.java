package kz.kunde.platform;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class PlatformController {
    private final boolean oidcConfigured;
    private final boolean foodEnabled;

    public PlatformController(@Value("${app.security.oidc.issuer-uri:}") String issuerUri,
            @Value("${app.security.oidc.audience:}") String audience,
            @Value("${app.food.enabled:false}") boolean foodEnabled) {
        this.oidcConfigured = !issuerUri.isBlank() && !audience.isBlank();
        this.foodEnabled = foodEnabled;
    }


    @GetMapping("/capabilities")
    public PlatformCapabilities capabilities() {
        return new PlatformCapabilities("FOUNDATION", foodEnabled, oidcConfigured, false);
    }

    public record PlatformCapabilities(
            String releaseStage,
            boolean marketplaceEnabled,
            boolean oidcIssuerConfigured,
            boolean aiEnabled) {}
}
