package kz.kunde.maps;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Locale;
import kz.kunde.rides.RideMatching.Point;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

/**
 * Real network check against the deployed KUNDE Maps Platform. Nothing is mocked. Enable with
 * {@code KUNDE_MAPS_LIVE=true} (optionally {@code MAPS_ROUTING_URL}, {@code MAPS_SEARCH_URL}); the first request may wait for a free-tier
 * instance to wake up, which the adapter's single retry and 60 s timeout absorb.
 */
@EnabledIfEnvironmentVariable(named = "KUNDE_MAPS_LIVE", matches = "true")
class KundeMapsLiveTest {
    private static String env(String name, String fallback) {
        var value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    private final KundeMapsRideRouting routing = new KundeMapsRideRouting(new MapsProperties(true,
            env("MAPS_ROUTING_URL", "https://kunde-maps-routing-dev.onrender.com"),
            env("MAPS_SEARCH_URL", "https://kunde-maps-search-dev.onrender.com"), "", 60, 524_288), new ObjectMapper());

    @Test
    void searchThenRouteOnTheRealPlatform() {
        var places = routing.geocode("улица Абая 10", Locale.forLanguageTag("ru"));
        assertThat(places).isNotEmpty();

        var pickup = new Point(43.238194, 76.94498);
        var route = routing.route(pickup, new Point(43.25, 76.93)).orElseThrow();
        assertThat(route.distanceMeters()).isBetween(1_000, 10_000);
        assertThat(route.durationSeconds()).isPositive();
        assertThat(route.geometry().size()).isGreaterThan(2);
        assertThat(route.synthetic()).isFalse();
    }

    @Test
    void noMatchCasesAreEmptyOnTheRealPlatform() {
        assertThat(routing.route(new Point(55.75, 37.62), new Point(43.25, 76.93))).isEmpty();
        assertThat(routing.route(new Point(43.238194, 76.94498), new Point(43.238195, 76.94499))).isEmpty();
    }
}
