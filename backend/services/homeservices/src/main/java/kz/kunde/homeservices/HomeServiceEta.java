package kz.kunde.homeservices;

import java.util.Locale;
import java.util.OptionalInt;
import kz.kunde.platform.geo.Point;
import kz.kunde.platform.geo.RoutingProvider;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;

/**
 * Arrival time of a master from the Maps provider: the booking address is geocoded and the road route from the master's
 * position is measured. A provider that is missing, down, finds no match or answers with a synthetic fixture yields no value,
 * so the caller falls back to the ETA the master typed; a fixture is never shown to a customer as a real route.
 */
@Component
public class HomeServiceEta {
    private final ObjectProvider<RoutingProvider> routing;

    public HomeServiceEta(ObjectProvider<RoutingProvider> routing) {
        this.routing = routing;
    }

    public OptionalInt minutes(String address, Point from) {
        RoutingProvider provider = routing.getIfAvailable();
        if (provider == null || address == null || address.isBlank()) {
            return OptionalInt.empty();
        }
        try {
            var places = provider.geocode(address.trim(), Locale.forLanguageTag("ru"));
            if (places.isEmpty()) {
                return OptionalInt.empty();
            }
            var route = provider.route(from, places.getFirst().point());
            if (route.isEmpty() || route.get().synthetic()) {
                return OptionalInt.empty();
            }
            return OptionalInt.of(Math.max(1, (int) Math.ceil(route.get().durationSeconds() / 60.0)));
        } catch (RoutingProvider.Unavailable unavailable) {
            return OptionalInt.empty();
        }
    }
}
