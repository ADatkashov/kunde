package kz.kunde.fulfillment;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * D-02 phase A: pickup fulfillment lifecycle, separate from the order lifecycle (PRD 1.1 §9 allows pickup to skip
 * ASSIGNED/PICKED_UP/IN_TRANSIT). Contract only: nothing is persisted, exposed over HTTP or linked to an order.
 * Progress is made only by an explicit merchant command with evidence of who acted; payment or order acceptance
 * never advances it. Response deadlines (D-05), cancellation/refund rules (D-06) and partner identity (D-07) are
 * not approved, so the only cancellation here is a technical abort requested by the order layer.
 */
public final class PickupFulfillment {
    public enum Status { PENDING, PREPARING, READY_FOR_PICKUP, HANDED_OVER, CANCELLED }

    public enum Command { START_PREPARING, MARK_READY, CONFIRM_HANDOVER, ABORT }

    public enum Actor { MERCHANT, CONSUMER, PLATFORM }

    /** Immutable audit entry. {@code commandId} makes replays idempotent. */
    public record Entry(String commandId, Command command, Status from, Status to, Actor actor, String actorId,
                        String reason, Instant at) { }

    public static final class IllegalTransitionException extends RuntimeException {
        IllegalTransitionException(String message) { super(message); }
    }

    /** Carries the current state and version so a client can refresh (PRD 1.1 §9 invalid transitions). */
    public static final class VersionConflictException extends RuntimeException {
        private final long currentVersion;
        private final Status currentStatus;

        VersionConflictException(long currentVersion, Status currentStatus) {
            super("expected version does not match current version " + currentVersion + " (" + currentStatus + ")");
            this.currentVersion = currentVersion;
            this.currentStatus = currentStatus;
        }

        public long currentVersion() { return currentVersion; }

        public Status currentStatus() { return currentStatus; }
    }

    private static final Map<Status, Map<Command, Status>> NEXT = Map.of(
            Status.PENDING, Map.of(Command.START_PREPARING, Status.PREPARING, Command.ABORT, Status.CANCELLED),
            Status.PREPARING, Map.of(Command.MARK_READY, Status.READY_FOR_PICKUP, Command.ABORT, Status.CANCELLED),
            Status.READY_FOR_PICKUP, Map.of(Command.CONFIRM_HANDOVER, Status.HANDED_OVER,
                    Command.ABORT, Status.CANCELLED),
            Status.HANDED_OVER, Map.of(),
            Status.CANCELLED, Map.of());

    /** Who may issue each command. The merchant works the order; abort comes from the order layer or platform. */
    private static final Map<Command, Set<Actor>> ALLOWED_ACTORS = Map.of(
            Command.START_PREPARING, Set.of(Actor.MERCHANT),
            Command.MARK_READY, Set.of(Actor.MERCHANT),
            Command.CONFIRM_HANDOVER, Set.of(Actor.MERCHANT),
            Command.ABORT, Set.of(Actor.MERCHANT, Actor.CONSUMER, Actor.PLATFORM));

    private final FulfillmentPolicy policy;
    private Status status = Status.PENDING;
    private long version;
    private final List<Entry> history = new ArrayList<>();
    private final Map<String, Entry> byCommandId = new HashMap<>();

    /** @throws IllegalTransitionException when pickup is not enabled by the policy (fail closed) */
    public PickupFulfillment(FulfillmentPolicy policy) {
        Objects.requireNonNull(policy, "policy");
        if (!policy.isEnabled(FulfillmentMethod.PICKUP)) {
            throw new IllegalTransitionException("PICKUP fulfillment is not enabled");
        }
        this.policy = policy;
    }

    public FulfillmentMethod method() { return FulfillmentMethod.PICKUP; }

    public Status status() { return status; }

    public long version() { return version; }

    public List<Entry> history() { return List.copyOf(history); }

    /**
     * Applies a command, or throws without changing state. Replaying a known {@code commandId} with the same command
     * returns the original entry and changes nothing; reusing it for a different command is rejected.
     */
    public Entry apply(String commandId, Command command, Actor actor, String actorId, String reason,
                       long expectedVersion, Instant at) {
        requireText(commandId, "commandId");
        Objects.requireNonNull(command, "command");
        Objects.requireNonNull(actor, "actor");
        Objects.requireNonNull(at, "at");
        requireText(actorId, "actorId");
        var replay = byCommandId.get(commandId);
        if (replay != null) {
            if (replay.command() != command) {
                throw new IllegalTransitionException("commandId already used for " + replay.command());
            }
            return replay;
        }
        if (!policy.isEnabled(FulfillmentMethod.PICKUP)) {
            throw new IllegalTransitionException("PICKUP fulfillment is not enabled");
        }
        if (expectedVersion != version) {
            throw new VersionConflictException(version, status);
        }
        var next = NEXT.get(status).get(command);
        if (next == null) {
            throw new IllegalTransitionException(command + " not allowed from " + status);
        }
        if (!ALLOWED_ACTORS.get(command).contains(actor)) {
            throw new IllegalTransitionException(command + " not allowed for actor " + actor);
        }
        if (command == Command.ABORT) { requireText(reason, "reason"); }
        var entry = new Entry(commandId, command, status, next, actor, actorId, reason, at);
        history.add(entry);
        byCommandId.put(commandId, entry);
        status = next;
        version++;
        return entry;
    }

    /** True only after the merchant confirmed handover; nothing else (payment, acceptance) implies it. */
    public boolean handedOver() { return status == Status.HANDED_OVER; }

    private static String requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }
}
