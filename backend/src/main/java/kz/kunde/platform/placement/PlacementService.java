package kz.kunde.platform.placement;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * Resolves "where does aggregate X live" from stored data. Read-only and stateless.
 *
 * <p>This is not authorization. Callers must still check that the principal may see the record; a placement answer
 * never grants access, and a city supplied by a client is only ever <em>compared</em> with the stored one
 * ({@link #belongsToCity}), never trusted as the owner.
 */
@Service
public class PlacementService {
    public record Resolved(ShardKey key, ShardLocation location) {}

    private final Map<String, PlacementLocator> locators = new HashMap<>();
    private final ShardResolver resolver;

    public PlacementService(List<PlacementLocator> locators, ShardResolver resolver) {
        for (PlacementLocator locator : locators) {
            if (this.locators.putIfAbsent(locator.aggregate(), locator) != null) {
                throw new IllegalStateException("Duplicate placement locator for aggregate " + locator.aggregate());
            }
        }
        this.resolver = resolver;
    }

    /** Empty when the record does not exist. An unknown aggregate name is a programming error and fails loudly. */
    public Optional<Resolved> locate(String aggregate, UUID id) {
        PlacementLocator locator = locators.get(aggregate);
        if (locator == null) {
            throw new IllegalArgumentException("No placement locator for aggregate " + aggregate);
        }
        return locator.locate(id).map(p -> {
            ShardKey key = p.placed() ? ShardKey.city(locator.domain(), p.cityId()) : ShardKey.unplaced(locator.domain());
            return new Resolved(key, resolver.resolve(key));
        });
    }

    /**
     * Fail-closed comparison of a client-claimed city with the stored one: false when the record is missing,
     * unplaced, or placed in another city.
     */
    public boolean belongsToCity(String aggregate, UUID id, UUID claimedCityId) {
        if (claimedCityId == null) {
            return false;
        }
        return locate(aggregate, id).map(r -> claimedCityId.equals(r.key().cityId())).orElse(false);
    }
}
