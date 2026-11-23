package kz.kunde.platform.events;

/**
 * Handles outbox events in-process today; the same contract is what a remote subscriber implements after extraction.
 * Delivery is at-least-once, so {@link #handle} may be called again for the same event only if a previous call threw
 * <em>after</em> its effects were rolled back; the relay already records successful handling per consumer (inbox), but a
 * consumer that calls out to other systems must still be idempotent by {@link StoredEvent#eventId()}.
 */
public interface EventConsumer {
    /** Stable name; it is the inbox key, so renaming a consumer replays history for it. */
    String name();

    boolean handles(String eventType);

    /** Highest schema version this consumer understands. A higher version is a permanent failure (dead letter), not a retry. */
    int maxSchemaVersion();

    /**
     * Runs in its own transaction together with the inbox record: both commit or neither. Throw {@link PermanentFailure} for
     * an event that can never succeed; any other exception is retried with backoff.
     */
    void handle(StoredEvent event);

    final class PermanentFailure extends RuntimeException {
        public PermanentFailure(String message) {
            super(message);
        }
    }
}
