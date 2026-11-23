package kz.kunde.platform.placement;

import java.util.Optional;
import java.util.UUID;

/**
 * Finds the placement of one aggregate by its public id, so an endpoint that receives only an id (no city) can
 * learn the owner of the record <em>from the stored data</em>, never from the caller's selected city or a header.
 * Each domain module implements it for its own aggregates over its own tables (see {@link SqlPlacementLocator}).
 * Children inherit the placement of their root, so a locator for a child joins to the root.
 */
public interface PlacementLocator {
    /** Stable aggregate name, e.g. {@code food.order}. */
    String aggregate();

    /** Owning domain, used as {@link ShardKey#domain()}. */
    String domain();

    /** Empty when no such record exists. */
    Optional<Placement> locate(UUID aggregateId);
}
