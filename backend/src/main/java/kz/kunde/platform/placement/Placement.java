package kz.kunde.platform.placement;

import java.util.UUID;

/** Stored placement of one aggregate root; {@code cityId} is null while the record is still unplaced. */
public record Placement(UUID aggregateId, UUID cityId) {
    public Placement {
        if (aggregateId == null) {
            throw new IllegalArgumentException("aggregateId is required");
        }
    }

    public boolean placed() {
        return cityId != null;
    }
}
