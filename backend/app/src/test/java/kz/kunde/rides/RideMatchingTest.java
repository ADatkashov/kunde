package kz.kunde.rides;

import static kz.kunde.rides.RideMatching.RideClass.ECONOMY;
import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import kz.kunde.rides.RideMatching.Candidate;
import kz.kunde.platform.geo.Point;
import org.junit.jupiter.api.Test;

class RideMatchingTest {
    private static final Point PICKUP = new Point(43.24, 76.92);
    private static final Instant NOW = Instant.parse("2026-11-18T10:00:00Z");

    @Test
    void choosesNearestEligibleDriverWithDeterministicTieBreak() {
        var second = candidate(2, true, false, PICKUP, NOW);
        var first = candidate(1, true, false, PICKUP, NOW);
        var farther = candidate(3, true, false, new Point(43.25, 76.92), NOW);
        assertThat(nearest(List.of(second, farther, first), Set.of())).contains(first);
        assertThat(nearest(List.of(second, farther, first), Set.of(first.driverId(), second.driverId())))
                .contains(farther);
    }

    @Test
    void excludesBusyUnverifiedStaleFutureAndDistantDrivers() {
        var candidates = List.of(
                candidate(1, true, true, PICKUP, NOW),
                candidate(2, false, false, PICKUP, NOW),
                candidate(3, true, false, PICKUP, NOW.minusSeconds(61)),
                candidate(4, true, false, PICKUP, NOW.plusSeconds(1)),
                candidate(5, true, false, new Point(43.50, 76.92), NOW));
        assertThat(nearest(candidates, Set.of())).isEmpty();
    }

    private static Candidate candidate(long id, boolean verified, boolean busy, Point point, Instant observedAt) {
        return new Candidate(new UUID(0, id), ECONOMY, true, verified, true, busy, point, observedAt);
    }

    private static java.util.Optional<Candidate> nearest(List<Candidate> candidates, Set<UUID> excluded) {
        return RideMatching.nearest(PICKUP, ECONOMY, candidates, excluded, NOW, Duration.ofMinutes(1), 2000);
    }
}
