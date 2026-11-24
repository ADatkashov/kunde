package kz.kunde.platform.support;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Contract through which a product (Rides, Delivery) works with the support cases that complain about its own
 * subjects. Support owns its case and case-event tables; products never touch them.
 * Today the only adapter is in-process (JDBC in the Support module); it can be replaced by a remote adapter when
 * Support is extracted. Authorization (who may read or resolve) stays in the calling product.
 */
public interface SupportCaseDirectory {
    enum Subject { RIDE, DELIVERY }

    record Case(UUID id, UUID subjectId, String category, String message, String status, OffsetDateTime createdAt) {}

    record CaseEvent(String eventType, UUID actorUserId, OffsetDateTime occurredAt) {}

    /** Open cases first, then newest first; at most {@code limit} rows. */
    List<Case> list(Subject subject, int limit);

    Optional<Case> find(Subject subject, UUID caseId);

    /**
     * Idempotently resolves the case and records a RESOLVED event for {@code reviewer}. The case row is locked for the
     * duration of the caller's transaction; an already resolved case is returned unchanged without a new event.
     * Must be called inside a transaction.
     */
    Optional<Case> resolve(Subject subject, UUID caseId, UUID reviewer);

    /** Audit trail of a case of the subject, oldest first; empty if the case does not exist for that subject. */
    List<CaseEvent> events(Subject subject, UUID caseId, int limit);
}
