package kz.kunde.platform.geo;

/** WGS84 point shared by every geo-aware product (Rides, Delivery, Maps); validated on construction. */
public record Point(double latitude, double longitude) {
    public Point {
        if (!Double.isFinite(latitude) || Math.abs(latitude) > 90
                || !Double.isFinite(longitude) || Math.abs(longitude) > 180) {
            throw new IllegalArgumentException("Invalid coordinates");
        }
    }
}
