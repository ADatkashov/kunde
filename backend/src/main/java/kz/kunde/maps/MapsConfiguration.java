package kz.kunde.maps;

import com.fasterxml.jackson.databind.ObjectMapper;
import kz.kunde.rides.RideRouting;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

/**
 * Wires the KUNDE Maps Platform as the {@link RideRouting} provider shared by Rides and Delivery. Off by default. It cannot be combined with
 * the synthetic fixtures: two providers would make the choice ambiguous, and a fixture must never stand in for a real route.
 */
@Configuration
@EnableConfigurationProperties(MapsProperties.class)
public class MapsConfiguration {

    public MapsConfiguration(MapsProperties maps, Environment environment) {
        if (!maps.enabled()) {
            return;
        }
        if (environment.getProperty("app.rides.synthetic-routing-enabled", Boolean.class, false)
                || environment.getProperty("app.delivery.synthetic-routing-enabled", Boolean.class, false)) {
            throw new IllegalStateException("KUNDE Maps cannot be enabled together with synthetic routing");
        }
        // Fails startup on a missing or insecure URL instead of failing every quote later.
        KundeMapsRideRouting.base(maps.routingUrl(), "app.maps.routing-url");
        KundeMapsRideRouting.base(maps.searchUrl(), "app.maps.search-url");
    }

    @Bean
    @ConditionalOnProperty(name = "app.maps.enabled", havingValue = "true")
    RideRouting kundeMapsRideRouting(MapsProperties maps, ObjectMapper json) {
        return new KundeMapsRideRouting(maps, json);
    }
}
