package kz.kunde.platform.geo;

/** Geographic helpers shared by products. Proximity ranking only; road distance belongs to a {@link RoutingProvider}. */
public final class Geo {
    private Geo() {}

    public static double distanceMeters(Point from, Point to) {
        double latitude = Math.toRadians(to.latitude() - from.latitude());
        double longitude = Math.toRadians(to.longitude() - from.longitude());
        double haversine = Math.pow(Math.sin(latitude / 2), 2)
                + Math.cos(Math.toRadians(from.latitude())) * Math.cos(Math.toRadians(to.latitude()))
                * Math.pow(Math.sin(longitude / 2), 2);
        return 2 * 6_371_000 * Math.asin(Math.sqrt(Math.min(1, haversine)));
    }
}
