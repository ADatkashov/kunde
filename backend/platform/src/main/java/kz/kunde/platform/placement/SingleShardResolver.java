package kz.kunde.platform.placement;

import org.springframework.stereotype.Component;

/**
 * Today every key lives in the one existing PostgreSQL, so the answer is always {@code default}. This is not working
 * sharding: it is the seam where routing will be added without touching business code.
 */
@Component
public class SingleShardResolver implements ShardResolver {
    @Override
    public ShardLocation resolve(ShardKey key) {
        if (key == null) {
            throw new IllegalArgumentException("key is required");
        }
        return ShardLocation.DEFAULT;
    }
}
