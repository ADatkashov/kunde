package kz.kunde.platform.placement;

/**
 * Maps a placement key to the logical shard that stores it. Pure and side-effect free, so it is safe inside any
 * transaction, async task or scheduled job.
 *
 * <p>Contract for a future multi-shard implementation: resolve {@code GLOBAL} to the global database, {@code CITY} through the
 * shard_id column of the city registry, and <strong>throw</strong> for {@code UNPLACED} (fail closed)
 * instead of guessing a shard.
 */
public interface ShardResolver {
    ShardLocation resolve(ShardKey key);
}
