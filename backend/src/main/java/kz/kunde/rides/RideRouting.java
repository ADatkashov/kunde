package kz.kunde.rides;

import java.util.List;
import java.util.Locale;
import java.util.Optional;
import kz.kunde.platform.geo.Point;

/** Maps provider boundary. Coordinates are WGS 84 and duration and distance come from a road route.
 * Implementations report provider outages with {@link Unavailable}. Empty results denote no match.
 */
public interface RideRouting {
    List<Place> geocode(String query, Locale locale);

    Optional<Place> reverseGeocode(Point point, Locale locale);

    Optional<Route> route(Point pickup, Point destination);

    final class Unavailable extends RuntimeException {
        public Unavailable(Throwable cause) {
            super(cause);
        }
    }

    record Place(String address, Point point) {}

    record Route(int distanceMeters, int durationSeconds, List<Point> geometry, boolean synthetic) {
        public Route(int distanceMeters, int durationSeconds, List<Point> geometry) {
            this(distanceMeters, durationSeconds, geometry, false);
        }

        public Route {
            geometry = List.copyOf(geometry);
            if (distanceMeters <= 0 || durationSeconds <= 0 || geometry.size() < 2) {
                throw new IllegalArgumentException("Road route must have distance, duration and geometry");
            }
        }
    }
}
