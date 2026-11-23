package kz.kunde.rides;

import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.Comparator;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import kz.kunde.platform.geo.Geo;
import kz.kunde.platform.geo.Point;

public final class RideMatching {
    private RideMatching() {}

    public enum RideClass { ECONOMY, COMFORT, BUSINESS, MINIVAN }

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
                .map(candidate -> new RankedCandidate(candidate, Geo.distanceMeters(pickup, candidate.location())))
                .filter(candidate -> candidate.distanceMeters() <= maxDistanceMeters)
                .min(Comparator.comparingDouble(RankedCandidate::distanceMeters)
                        .thenComparing(candidate -> candidate.candidate().driverId()))
                .map(RankedCandidate::candidate);
    }
}
