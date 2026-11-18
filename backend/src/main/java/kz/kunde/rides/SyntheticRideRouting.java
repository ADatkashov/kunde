package kz.kunde.rides;

import java.util.List;
import java.util.Locale;
import java.util.Optional;
import kz.kunde.rides.RideMatching.Point;

/** Deterministic route fixture for internal environments. */
final class SyntheticRideRouting implements RideRouting {
    private static final Point PICKUP = new Point(43.24, 76.92);
    private static final Point DESTINATION = new Point(43.25, 76.94);
    private static final Place START = new Place("[TEST] Synthetic pickup", PICKUP);
    private static final Place END = new Place("[TEST] Synthetic destination", DESTINATION);

    @Override
    public List<Place> geocode(String query, Locale locale) {
        return List.of(START, END).stream()
                .filter(place -> place.address().toLowerCase(Locale.ROOT).contains(query.toLowerCase(Locale.ROOT)))
                .toList();
    }

    @Override
    public Optional<Place> reverseGeocode(Point point, Locale locale) {
        return List.of(START, END).stream().filter(place -> place.point().equals(point)).findFirst();
    }

    @Override
    public Optional<Route> route(Point pickup, Point destination) {
        if (!PICKUP.equals(pickup) || !DESTINATION.equals(destination)) {
            return Optional.empty();
        }
        return Optional.of(new Route(3000, 360, List.of(PICKUP, new Point(43.245, 76.925), DESTINATION), true));
    }
}
