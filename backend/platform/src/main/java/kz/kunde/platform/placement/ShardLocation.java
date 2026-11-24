package kz.kunde.platform.placement;

import java.util.regex.Pattern;

/** A logical shard id (the shard_id column of the city registry); not a connection string. */
public record ShardLocation(String shardId) {
    private static final Pattern ID = Pattern.compile("[a-z0-9][a-z0-9_-]{0,31}");

    /** The single logical shard that holds all data today (the one existing PostgreSQL). */
    public static final ShardLocation DEFAULT = new ShardLocation("default");

    public ShardLocation {
        if (shardId == null || !ID.matcher(shardId).matches()) {
            throw new IllegalArgumentException("shardId must match " + ID.pattern());
        }
    }
}
