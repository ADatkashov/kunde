package kz.kunde.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import java.net.URI;
import java.util.Arrays;
import java.util.List;

@Configuration
public class WebConfig implements WebMvcConfigurer {
    private final List<String> allowedOrigins;

    public WebConfig(@org.springframework.beans.factory.annotation.Value("${app.cors.allowed-origins:}") String origins) {
        this.allowedOrigins = origins == null || origins.isBlank() ? List.of() :
                Arrays.stream(origins.split(",")).map(String::trim).filter(origin -> !origin.isEmpty())
                        .peek(WebConfig::validateOrigin).toList();
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        // Register even an empty allowlist: preflight must fail closed explicitly.
        registry.addMapping("/api/**").allowedOrigins(allowedOrigins.toArray(String[]::new))
                    .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                    .allowedHeaders("Content-Type", "Authorization", "X-Correlation-ID");
    }

    private static void validateOrigin(String origin) {
        URI uri = URI.create(origin);
        String scheme = uri.getScheme();
        if (scheme == null || (!scheme.equalsIgnoreCase("http") && !scheme.equalsIgnoreCase("https")) ||
                uri.getHost() == null ||
                uri.getUserInfo() != null || (uri.getPath() != null && !uri.getPath().isEmpty()) ||
                uri.getQuery() != null || uri.getFragment() != null) {
            throw new IllegalArgumentException("CORS origins must be explicit HTTP(S) origins without path or credentials");
        }
    }
}
