package kz.kunde.order;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * TASK-021 (D-05/D-06 approved 2026-11-13): Food Ordering order lifecycle, separate from payment and fulfillment.
 * Contract only: nothing is persisted, exposed over HTTP, scheduled or linked to payments. The server clock
 * ({@code at}) is authoritative: any command at or after the response deadline first times the order out
 * (late acceptance never revives it). No fee, refund or payment concept exists here; D-03/D-04 and legal terms
 * are not approved. Partner roles/tenant isolation (D-07) must be enforced by the caller before commands arrive.
 */
public final class OrderLifecycle {
    public enum Status {
        /** Awaiting the restaurant; deadline and reminder run from submission. */
        SUBMITTED,
        /** Restaurant proposed changed items/price; waiting for the customer's explicit decision. */
        CHANGE_PROPOSED,
        ACCEPTED,
        /** Cancellation after acceptance (or unfulfillable order) is resolved by authorized support only. */
        SUPPORT_REVIEW,
        REJECTED,
        EXPIRED,
        CANCELLED
    }

    public enum Command {
        ACCEPT, REJECT, PROPOSE_CHANGE, APPROVE_CHANGE, DECLINE_CHANGE, CANCEL,
        REQUEST_CANCELLATION, REPORT_UNFULFILLABLE, RESOLVE_CANCEL, RESOLVE_KEEP,
        TIMEOUT, REMIND
    }

    public enum Actor { CUSTOMER, RESTAURANT, SUPPORT, SYSTEM }

    /** Immutable audit entry; {@code from == to} for a reminder. {@code commandId} makes replays idempotent. */
    public record Entry(String commandId, Command command, Status from, Status to, Actor actor, String actorId,
                        String reason, long quoteVersion, Instant at) { }

    public static final class IllegalTransitionException extends RuntimeException {
        IllegalTransitionException(String message) { super(message); }
    }

    /** The response deadline had passed: the order was timed out and the late command was not applied. */
    public static final class DeadlinePassedException extends RuntimeException {
        DeadlinePassedException(String message) { super(message); }
    }

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
            Status.SUBMITTED, Map.of(Command.ACCEPT, Status.ACCEPTED, Command.REJECT, Status.REJECTED,
                    Command.PROPOSE_CHANGE, Status.CHANGE_PROPOSED, Command.CANCEL, Status.CANCELLED,
                    Command.TIMEOUT, Status.EXPIRED, Command.REMIND, Status.SUBMITTED),
            Status.CHANGE_PROPOSED, Map.of(Command.APPROVE_CHANGE, Status.ACCEPTED,
                    Command.DECLINE_CHANGE, Status.CANCELLED, Command.CANCEL, Status.CANCELLED),
            Status.ACCEPTED, Map.of(Command.REQUEST_CANCELLATION, Status.SUPPORT_REVIEW,
                    Command.REPORT_UNFULFILLABLE, Status.SUPPORT_REVIEW),
            Status.SUPPORT_REVIEW, Map.of(Command.RESOLVE_CANCEL, Status.CANCELLED,
                    Command.RESOLVE_KEEP, Status.ACCEPTED),
            Status.REJECTED, Map.of(), Status.EXPIRED, Map.of(), Status.CANCELLED, Map.of());

    private static final Map<Command, Set<Actor>> ALLOWED_ACTORS = Map.ofEntries(
            Map.entry(Command.ACCEPT, Set.of(Actor.RESTAURANT)),
            Map.entry(Command.REJECT, Set.of(Actor.RESTAURANT)),
            Map.entry(Command.PROPOSE_CHANGE, Set.of(Actor.RESTAURANT)),
            Map.entry(Command.APPROVE_CHANGE, Set.of(Actor.CUSTOMER)),
            Map.entry(Command.DECLINE_CHANGE, Set.of(Actor.CUSTOMER)),
            Map.entry(Command.CANCEL, Set.of(Actor.CUSTOMER)),
            Map.entry(Command.REQUEST_CANCELLATION, Set.of(Actor.CUSTOMER)),
            Map.entry(Command.REPORT_UNFULFILLABLE, Set.of(Actor.RESTAURANT)),
            Map.entry(Command.RESOLVE_CANCEL, Set.of(Actor.SUPPORT)),
            Map.entry(Command.RESOLVE_KEEP, Set.of(Actor.SUPPORT)),
            Map.entry(Command.TIMEOUT, Set.of(Actor.SYSTEM)),
            Map.entry(Command.REMIND, Set.of(Actor.SYSTEM)));

    private static final Set<Command> REASON_REQUIRED = Set.of(Command.REJECT, Command.REQUEST_CANCELLATION,
            Command.REPORT_UNFULFILLABLE, Command.RESOLVE_CANCEL, Command.RESOLVE_KEEP, Command.DECLINE_CHANGE);

    private final ResponsePolicy policy;
    private final Instant submittedAt;
    private final Instant deadline;
    private Status status = Status.SUBMITTED;
    private long version;
    private long quoteVersion = 1;
    private long pendingQuoteVersion;
    private int preparationMinutes;
    private boolean reminded;
    private final List<Entry> history = new ArrayList<>();
    private final Map<String, Entry> byCommandId = new HashMap<>();

    /**
     * @param restaurantAcceptingOrders false for an unavailable restaurant; it must not receive new orders (D-05 #7)
     * @throws IllegalTransitionException when the restaurant is unavailable (fail closed)
     */
    public OrderLifecycle(ResponsePolicy policy, Instant submittedAt, boolean restaurantAcceptingOrders) {
        this.policy = Objects.requireNonNull(policy, "policy");
        this.submittedAt = Objects.requireNonNull(submittedAt, "submittedAt");
        if (!restaurantAcceptingOrders) {
            throw new IllegalTransitionException("restaurant is not accepting orders");
        }
        this.deadline = submittedAt.plus(policy.confirmationWindow());
    }

    public Status status() { return status; }

    public long version() { return version; }

    /** Quote version the customer's consent applies to; bumped only when the customer approves a change. */
    public long quoteVersion() { return quoteVersion; }

    public String policyVersion() { return policy.version(); }

    public Instant responseDeadline() { return deadline; }

    public Instant reminderAt() { return submittedAt.plus(policy.reminderAfter()); }

    /** Restaurant-supplied estimate; 0 until accepted. Never a KUNDE guess. */
    public int preparationMinutes() { return preparationMinutes; }

    public List<Entry> history() { return List.copyOf(history); }

    /** True when a reminder should be generated now: still unanswered, reminder time reached, not yet reminded. */
    public boolean reminderDue(Instant now) {
        return status == Status.SUBMITTED && !reminded && !now.isBefore(reminderAt()) && now.isBefore(deadline);
    }

    /** True when the system should time the order out now. */
    public boolean timeoutDue(Instant now) {
        return status == Status.SUBMITTED && !now.isBefore(deadline);
    }

    /** Restaurant accepts with its own preparation estimate. */
    public Entry accept(String commandId, String actorId, int preparationMinutes, long expectedVersion, Instant at) {
        if (preparationMinutes <= 0) {
            throw new IllegalArgumentException("preparationMinutes must be positive");
        }
        var known = byCommandId.containsKey(commandId);
        var entry = apply(commandId, Command.ACCEPT, Actor.RESTAURANT, actorId, null, quoteVersion, expectedVersion, at);
        if (!known) { this.preparationMinutes = preparationMinutes; }
        return entry;
    }

    /** Restaurant proposes changed items/price; takes effect only if the customer approves this quote version. */
    public Entry proposeChange(String commandId, String actorId, long newQuoteVersion, long expectedVersion, Instant at) {
        if (newQuoteVersion <= quoteVersion) {
            throw new IllegalArgumentException("newQuoteVersion must exceed the current quote version");
        }
        var known = byCommandId.containsKey(commandId);
        var entry = apply(commandId, Command.PROPOSE_CHANGE, Actor.RESTAURANT, actorId, null, newQuoteVersion,
                expectedVersion, at);
        if (!known) { this.pendingQuoteVersion = newQuoteVersion; }
        return entry;
    }

    /** Customer consent must name the exact proposed quote version (no silent substitution). */
    public Entry approveChange(String commandId, String actorId, long approvedQuoteVersion, long expectedVersion,
                               Instant at) {
        var known = byCommandId.containsKey(commandId);
        if (!known && status == Status.CHANGE_PROPOSED && approvedQuoteVersion != pendingQuoteVersion) {
            throw new IllegalTransitionException(
                    "approval does not match proposed quote version " + pendingQuoteVersion);
        }
        var entry = apply(commandId, Command.APPROVE_CHANGE, Actor.CUSTOMER, actorId, null, approvedQuoteVersion,
                expectedVersion, at);
        if (!known) { this.quoteVersion = approvedQuoteVersion; }
        return entry;
    }

    /** Generic command entry point for commands without extra payload. */
    public Entry apply(String commandId, Command command, Actor actor, String actorId, String reason,
                       long expectedVersion, Instant at) {
        if (command == Command.ACCEPT || command == Command.PROPOSE_CHANGE || command == Command.APPROVE_CHANGE) {
            throw new IllegalArgumentException(command + " has a dedicated method");
        }
        return apply(commandId, command, actor, actorId, reason, quoteVersion, expectedVersion, at);
    }

    private Entry apply(String commandId, Command command, Actor actor, String actorId, String reason, long quote,
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
        if (expectedVersion != version) {
            throw new VersionConflictException(version, status);
        }
        if (!ALLOWED_ACTORS.get(command).contains(actor)) {
            throw new IllegalTransitionException(command + " not allowed for actor " + actor);
        }
        if (command != Command.TIMEOUT && command != Command.REMIND && timeoutDue(at)) {
            record("timeout-" + version, Command.TIMEOUT, Actor.SYSTEM, "system", "response deadline passed", at);
            throw new DeadlinePassedException("response deadline passed; order is " + status);
        }
        var next = NEXT.get(status).get(command);
        if (next == null) {
            throw new IllegalTransitionException(command + " not allowed from " + status);
        }
        if (command == Command.TIMEOUT && !timeoutDue(at)) {
            throw new IllegalTransitionException("response deadline not reached");
        }
        if (command == Command.REMIND && !reminderDue(at)) {
            throw new IllegalTransitionException("reminder not due");
        }
        if (REASON_REQUIRED.contains(command)) { requireText(reason, "reason"); }
        var entry = record(commandId, command, actor, actorId, reason, at, next, quote);
        if (command == Command.REMIND) { reminded = true; }
        return entry;
    }

    private Entry record(String commandId, Command command, Actor actor, String actorId, String reason, Instant at) {
        return record(commandId, command, actor, actorId, reason, at, Status.EXPIRED, quoteVersion);
    }

    private Entry record(String commandId, Command command, Actor actor, String actorId, String reason, Instant at,
                         Status next, long quote) {
        var entry = new Entry(commandId, command, status, next, actor, actorId, reason, quote, at);
        history.add(entry);
        byCommandId.put(commandId, entry);
        status = next;
        version++;
        return entry;
    }

    private static String requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }
}
