package kz.kunde.platform.dispatch;

/**
 * Shared kernel contract for "an executor is busy" across Rides and Delivery: a person may be both a driver and a
 * courier, so each product must exclude executors that are busy in the other one. The state sets live here, not in
 * either product, so neither imports the other. The SQL against the other product's table is still tracked in the
 * architecture baseline until an availability service replaces it.
 */
public final class ActiveWork {
    private ActiveWork() {}

    /** SQL {@code in (...)} list of delivery states in which a courier is occupied. */
    public static final String ACTIVE_DELIVERY_STATES = """
            ('COURIER_ASSIGNED','COURIER_ARRIVING','COURIER_ARRIVED','PICKED_UP','IN_TRANSIT',
             'DELIVERED','DELIVERY_FAILED','RETURN_REQUESTED','RETURNING')
            """;
}
