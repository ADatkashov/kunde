package kz.kunde.platform.placement;

import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Logical placement key of operational data. It is deliberately <em>not</em> a tenant id and <em>not</em> an
 * authorization claim: it only answers "which database holds this aggregate".
 *
 * <ul>
 *   <li>{@link Scope#CITY}: the aggregate belongs to one city for its whole life ({@code city_id} of its root);</li>
 *   <li>{@link Scope#GLOBAL}: identity, partners, the city registry... always on the global database;</li>
 *   <li>{@link Scope#UNPLACED}: a city-scoped aggregate whose {@code city_id} is still NULL (created before V63 and not
 *       yet mapped by a reviewed backfill). A resolver for more than one shard must refuse such a key.</li>
 * </ul>
 * The key is passed explicitly. There is no thread-local "current city": it would leak across pooled threads,
 * {@code @Async} tasks and {@code @Scheduled} jobs, none of which has a request.
 */
public record ShardKey(String domain, Scope scope, UUID cityId) {
    public enum Scope { GLOBAL, CITY, UNPLACED }

    private static final Pattern DOMAIN = Pattern.compile("[a-z][a-z0-9_.-]{0,63}");

    public ShardKey {
        if (domain == null || !DOMAIN.matcher(domain).matches()) {
            throw new IllegalArgumentException("domain must match " + DOMAIN.pattern());
        }
        if (scope == null) {
            throw new IllegalArgumentException("scope is required");
        }
        if ((scope == Scope.CITY) != (cityId != null)) {
            throw new IllegalArgumentException("cityId is required for, and only for, scope CITY");
        }
    }

    public static ShardKey city(String domain, UUID cityId) {
        return new ShardKey(domain, Scope.CITY, cityId);
    }

    public static ShardKey global(String domain) {
        return new ShardKey(domain, Scope.GLOBAL, null);
    }

    public static ShardKey unplaced(String domain) {
        return new ShardKey(domain, Scope.UNPLACED, null);
    }
}
