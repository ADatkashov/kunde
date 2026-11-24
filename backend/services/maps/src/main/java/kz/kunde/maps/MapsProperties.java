package kz.kunde.maps;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * KUNDE Maps Platform connection (separate services owned by the kunde-maps repository). Disabled by default, so Rides and Delivery keep
 * failing closed (503) until an operator enables a real provider. The API key is optional: the Maps services accept anonymous requests under
 * their public quotas, and a key only raises the server-to-server quota. It is never logged.
 */
@ConfigurationProperties("app.maps")
public record MapsProperties(boolean enabled, String routingUrl, String searchUrl, String apiKey,
        @Min(1) @Max(60) int timeoutSeconds, @Min(1024) @Max(4_194_304) int maxResponseBytes) {

    public MapsProperties {
        routingUrl = routingUrl == null ? "" : routingUrl.strip();
        searchUrl = searchUrl == null ? "" : searchUrl.strip();
        apiKey = apiKey == null ? "" : apiKey.strip();
        timeoutSeconds = timeoutSeconds == 0 ? 15 : timeoutSeconds;
        maxResponseBytes = maxResponseBytes == 0 ? 524_288 : maxResponseBytes;
    }
}
