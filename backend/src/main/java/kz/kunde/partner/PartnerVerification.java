package kz.kunde.partner;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * TASK-015 / PB-01, PB-02 (docs/business/24-operational-playbooks.md): partner verification state machine.
 * Contract only: nothing here is persisted, exposed over HTTP or wired to the catalog. An APPROVED
 * verification does not enable offerings or marketplace flags (ADR-014 gates stay closed). Statuses,
 * decisions and reason rules mirror the draft playbooks and are not an approved product contract.
 */
public final class PartnerVerification {
    public enum Status { PENDING_REVIEW, INFO_REQUESTED, APPROVED, LIMITED, SUSPENDED, REJECTED }

    public enum Decision { REQUEST_INFO, RESUBMIT, APPROVE, REJECT, LIMIT, SUSPEND, RESTORE }

    /** Immutable audit entry: previous/new state, actor, reason (PB-01/PB-02 audit requirement). */
    public record Entry(Status from, Status to, Decision decision, String actor, String reason, Instant at) { }

    public static final class IllegalTransitionException extends RuntimeException {
        IllegalTransitionException(String message) { super(message); }
    }

    private static final Map<Status, Set<Decision>> ALLOWED = Map.of(
            Status.PENDING_REVIEW, Set.of(Decision.REQUEST_INFO, Decision.APPROVE, Decision.REJECT),
            Status.INFO_REQUESTED, Set.of(Decision.RESUBMIT, Decision.REJECT),
            Status.APPROVED, Set.of(Decision.LIMIT, Decision.SUSPEND),
            Status.LIMITED, Set.of(Decision.RESTORE, Decision.SUSPEND),
            Status.SUSPENDED, Set.of(Decision.RESTORE),
            Status.REJECTED, Set.of());

    /** Decisions that restrict or deny a partner must carry a human-readable reason. */
    private static final Set<Decision> REASON_REQUIRED =
            Set.of(Decision.REQUEST_INFO, Decision.REJECT, Decision.LIMIT, Decision.SUSPEND);

    /** Decisions taken by a reviewer; they must not be the partner's own submitter. */
    private static final Set<Decision> REVIEWER_ONLY = Set.of(Decision.REQUEST_INFO, Decision.APPROVE,
            Decision.REJECT, Decision.LIMIT, Decision.SUSPEND, Decision.RESTORE);

    private final String submitter;
    private Status status = Status.PENDING_REVIEW;
    private final List<Entry> history = new ArrayList<>();

    public PartnerVerification(String submitter) {
        this.submitter = requireText(submitter, "submitter");
    }

    public Status status() { return status; }

    public List<Entry> history() { return List.copyOf(history); }

    /** Applies a decision, or throws without changing state (fail closed). */
    public Entry apply(Decision decision, String actor, String reason, Instant at) {
        Objects.requireNonNull(decision, "decision");
        Objects.requireNonNull(at, "at");
        requireText(actor, "actor");
        if (!ALLOWED.get(status).contains(decision)) {
            throw new IllegalTransitionException(decision + " not allowed from " + status);
        }
        if (decision == Decision.RESUBMIT ? !actor.equals(submitter) : REVIEWER_ONLY.contains(decision)
                && actor.equals(submitter)) {
            throw new IllegalTransitionException(decision + " not allowed for actor " + (decision == Decision.RESUBMIT
                    ? "other than the submitter" : "who submitted the application"));
        }
        if (REASON_REQUIRED.contains(decision)) { requireText(reason, "reason"); }
        var next = switch (decision) {
            case REQUEST_INFO -> Status.INFO_REQUESTED;
            case RESUBMIT -> Status.PENDING_REVIEW;
            case APPROVE, RESTORE -> Status.APPROVED;
            case REJECT -> Status.REJECTED;
            case LIMIT -> Status.LIMITED;
            case SUSPEND -> Status.SUSPENDED;
        };
        var entry = new Entry(status, next, decision, actor, reason, at);
        history.add(entry);
        status = next;
        return entry;
    }

    /** Only APPROVED may be treated as eligible for later catalog gates; it enables nothing by itself. */
    public boolean eligibleForCatalogGate() { return status == Status.APPROVED; }

    private static String requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }
}
