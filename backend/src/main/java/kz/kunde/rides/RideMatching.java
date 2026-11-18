package kz.kunde.rides;

import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.Comparator;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

public final class RideMatching {
    private RideMatching() {}

    public enum RideClass { ECONOMY, COMFORT, BUSINESS }

    public record Point(double latitude, double longitude) {
        public Point {
            if (!Double.isFinite(latitude) || Math.abs(latitude) > 90
                    || !Double.isFinite(longitude) || Math.abs(longitude) > 180) {
                throw new IllegalArgumentException("Invalid coordinates");
            }
        }
    }

    public record Candidate(UUID driverId, RideClass rideClass, boolean online, boolean verified,
            boolean vehicleApproved, boolean hasActiveRide, Point location, Instant observedAt) {}

    private record RankedCandidate(Candidate candidate, double distanceMeters) {}

    public static Optional<Candidate> nearest(Point pickup, RideClass rideClass, Collection<Candidate> candidates,
            Set<UUID> excludedDrivers, Instant now, Duration locationMaxAge, double maxDistanceMeters) {
        if (locationMaxAge.isNegative() || locationMaxAge.isZero()
                || !Double.isFinite(maxDistanceMeters) || maxDistanceMeters <= 0) {
            throw new IllegalArgumentException("Invalid matching limits");
        }
        Instant oldest = now.minus(locationMaxAge);
        return candidates.stream()
                .filter(candidate -> candidate.online() && candidate.verified() && candidate.vehicleApproved()
                        && !candidate.hasActiveRide() && candidate.rideClass() == rideClass
                        && !excludedDrivers.contains(candidate.driverId())
                        && candidate.location() != null && candidate.observedAt() != null
                        && !candidate.observedAt().isBefore(oldest) && !candidate.observedAt().isAfter(now))
                .map(candidate -> new RankedCandidate(candidate, distanceMeters(pickup, candidate.location())))
                .filter(candidate -> candidate.distanceMeters() <= maxDistanceMeters)
                .min(Comparator.comparingDouble(RankedCandidate::distanceMeters)
                        .thenComparing(candidate -> candidate.candidate().driverId()))
                .map(RankedCandidate::candidate);
    }

    // Geographic proximity is used only to rank drivers. Road distance belongs to a routing provider.
    private static double distanceMeters(Point from, Point to) {
        double latitude = Math.toRadians(to.latitude() - from.latitude());
        double longitude = Math.toRadians(to.longitude() - from.longitude());
        double haversine = Math.pow(Math.sin(latitude / 2), 2)
                + Math.cos(Math.toRadians(from.latitude())) * Math.cos(Math.toRadians(to.latitude()))
                * Math.pow(Math.sin(longitude / 2), 2);
        return 2 * 6_371_000 * Math.asin(Math.sqrt(Math.min(1, haversine)));
    }
}
