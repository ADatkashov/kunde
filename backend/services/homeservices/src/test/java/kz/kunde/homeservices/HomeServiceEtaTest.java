package kz.kunde.homeservices;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Locale;
import java.util.Optional;
import kz.kunde.platform.geo.Point;
import kz.kunde.platform.geo.RoutingProvider;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.support.StaticListableBeanFactory;

/** ETA from the Maps provider: measured by road, rounded up to whole minutes, and never a fixture or a guess. */
class HomeServiceEtaTest {
    private static final Point MASTER = new Point(43.2380, 76.9450);
    private static final Point CLIENT = new Point(43.2500, 76.9600);

    private static HomeServiceEta with(RoutingProvider provider) {
        var beans = new StaticListableBeanFactory();
        if (provider != null) {
            beans.addBean("routing", provider);
        }
        return new HomeServiceEta(beans.getBeanProvider(RoutingProvider.class));
    }

    private record Stub(List<RoutingProvider.Place> places, Optional<RoutingProvider.Route> route, boolean down)
            implements RoutingProvider {
        @Override public List<Place> geocode(String query, Locale locale) {
            if (down) { throw new Unavailable(new RuntimeException("down")); }
            return places;
        }
        @Override public Optional<Place> reverseGeocode(Point point, Locale locale) { return Optional.empty(); }
        @Override public Optional<Route> route(Point pickup, Point destination) { return route; }
    }

    private static RoutingProvider.Route route(int seconds, boolean synthetic) {
        return new RoutingProvider.Route(3000, seconds, List.of(MASTER, CLIENT), synthetic);
    }

    private static final List<RoutingProvider.Place> FOUND = List.of(new RoutingProvider.Place("Абая 150", CLIENT));

    @Test
    void roundsTheRoadDurationUpToWholeMinutes() {
        assertThat(with(new Stub(FOUND, Optional.of(route(601, false)), false)).minutes("Абая 150", MASTER)).hasValue(11);
        assertThat(with(new Stub(FOUND, Optional.of(route(30, false)), false)).minutes("Абая 150", MASTER)).hasValue(1);
    }

    @Test
    void givesNothingWithoutAProviderAnAddressAMatchOrARealRoute() {
        assertThat(with(null).minutes("Абая 150", MASTER)).isEmpty();
        var real = new Stub(FOUND, Optional.of(route(600, false)), false);
        assertThat(with(real).minutes(" ", MASTER)).isEmpty();
        assertThat(with(real).minutes(null, MASTER)).isEmpty();
        assertThat(with(new Stub(List.of(), Optional.of(route(600, false)), false)).minutes("Абая 150", MASTER)).isEmpty();
        assertThat(with(new Stub(FOUND, Optional.empty(), false)).minutes("Абая 150", MASTER)).isEmpty();
        assertThat(with(new Stub(FOUND, Optional.of(route(600, true)), false)).minutes("Абая 150", MASTER)).isEmpty();
    }

    @Test
    void aProviderOutageFallsBackToTheMastersOwnEta() {
        assertThat(with(new Stub(FOUND, Optional.of(route(600, false)), true)).minutes("Абая 150", MASTER)).isEmpty();
    }
}
