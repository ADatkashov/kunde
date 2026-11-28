package kz.kunde.homeservices;

import java.net.URI;
import java.time.Duration;
import java.util.Set;
import java.util.regex.Pattern;
import kz.kunde.platform.ApiBodyLimitFilter;
import org.springframework.http.HttpMethod;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.scheduling.annotation.EnableScheduling;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

@Configuration(proxyBeanMethods = false)
@EnableScheduling
@ConditionalOnProperty(name = {"app.home-services.enabled", "app.home-services.photos.enabled"}, havingValue = "true")
class HomeServicePhotoStorageConfiguration {
    private static final Pattern BOOKING_UPLOAD = Pattern.compile(
            "/api/v1/home-services/bookings/[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}/photos");

    @Bean
    @ConditionalOnProperty(name = {"app.booking.enabled", "app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
    ApiBodyLimitFilter.StreamingRoute homeServicePhotoUploadRoute() {
        return request -> HttpMethod.POST.matches(request.getMethod())
                && BOOKING_UPLOAD.matcher(request.getServletPath()).matches();
    }


    @Bean
    HomeServicePhotoStorage homeServicePhotoStorage(Environment environment) {
        boolean internal = Set.of("local", "dev", "test").contains(environment.getProperty("app.environment", "production"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
        if (!internal) {
            throw new IllegalStateException("Home Services photo storage requires a dev/local/test environment");
        }
        URI endpoint = URI.create(environment.getRequiredProperty("app.home-services.photos.endpoint"));
        validateEndpoint(endpoint);
        Region region = Region.of(environment.getProperty("app.home-services.photos.region", "auto"));
        String bucket = environment.getRequiredProperty("app.home-services.photos.bucket");
        if (!bucket.matches("[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]")) {
            throw new IllegalStateException("Invalid Home Services photo bucket");
        }
        var config = S3Configuration.builder().pathStyleAccessEnabled(true).build();
        var presigner = S3Presigner.builder().region(region).endpointOverride(endpoint).serviceConfiguration(config).build();
        try {
            var client = S3Client.builder().region(region).endpointOverride(endpoint).serviceConfiguration(config)
                    .overrideConfiguration(options -> options.apiCallTimeout(Duration.ofSeconds(10))
                            .apiCallAttemptTimeout(Duration.ofSeconds(5))).build();
            return new HomeServicePhotoStorage(client, presigner, bucket);
        } catch (RuntimeException e) {
            presigner.close();
            throw e;
        }
    }

    static void validateEndpoint(URI endpoint) {
        String host = endpoint.getHost();
        boolean https = "https".equalsIgnoreCase(endpoint.getScheme());
        boolean localHttp = "http".equalsIgnoreCase(endpoint.getScheme())
                && ("localhost".equalsIgnoreCase(host) || "127.0.0.1".equals(host));
        if (host == null || !(https || localHttp) || endpoint.getUserInfo() != null
                || endpoint.getQuery() != null || endpoint.getFragment() != null
                || !(endpoint.getPath().isEmpty() || "/".equals(endpoint.getPath()))) {
            throw new IllegalStateException("Invalid Home Services photo storage endpoint");
        }
    }
}
