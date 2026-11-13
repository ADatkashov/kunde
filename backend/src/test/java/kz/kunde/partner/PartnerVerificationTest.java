package kz.kunde.partner;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import kz.kunde.partner.PartnerVerification.Decision;
import kz.kunde.partner.PartnerVerification.IllegalTransitionException;
import kz.kunde.partner.PartnerVerification.Status;
import org.junit.jupiter.api.Test;

class PartnerVerificationTest {
    private static final Instant T = Instant.parse("2026-11-13T00:00:00Z");

    private static PartnerVerification fresh() { return new PartnerVerification("partner-1"); }

    @Test
    void startsPendingAndIsNotEligible() {
        var v = fresh();
        assertEquals(Status.PENDING_REVIEW, v.status());
        assertFalse(v.eligibleForCatalogGate());
    }

    @Test
    void infoRequestResubmitApproveRecordsAudit() {
        var v = fresh();
        v.apply(Decision.REQUEST_INFO, "ops-1", "missing license", T);
        v.apply(Decision.RESUBMIT, "partner-1", null, T);
        v.apply(Decision.APPROVE, "ops-2", null, T);
        assertTrue(v.eligibleForCatalogGate());
        assertEquals(3, v.history().size());
        var last = v.history().get(2);
        assertEquals(Status.PENDING_REVIEW, last.from());
        assertEquals(Status.APPROVED, last.to());
        assertEquals("ops-2", last.actor());
    }

    @Test
    void submitterCannotReviewOwnApplication() {
        var v = fresh();
        assertThrows(IllegalTransitionException.class, () -> v.apply(Decision.APPROVE, "partner-1", null, T));
        assertEquals(Status.PENDING_REVIEW, v.status());
        assertTrue(v.history().isEmpty());
    }

    @Test
    void onlySubmitterMayResubmit() {
        var v = fresh();
        v.apply(Decision.REQUEST_INFO, "ops-1", "need docs", T);
        assertThrows(IllegalTransitionException.class, () -> v.apply(Decision.RESUBMIT, "ops-1", null, T));
        assertEquals(Status.INFO_REQUESTED, v.status());
    }

    @Test
    void restrictingDecisionsRequireReason() {
        var v = fresh();
        assertThrows(IllegalArgumentException.class, () -> v.apply(Decision.REJECT, "ops-1", " ", T));
        assertThrows(IllegalArgumentException.class, () -> v.apply(Decision.REQUEST_INFO, "ops-1", null, T));
        assertEquals(Status.PENDING_REVIEW, v.status());
    }

    @Test
    void rejectedIsTerminal() {
        var v = fresh();
        v.apply(Decision.REJECT, "ops-1", "prohibited category", T);
        for (var d : Decision.values()) {
            assertThrows(IllegalTransitionException.class, () -> v.apply(d, "ops-2", "x", T));
        }
        assertFalse(v.eligibleForCatalogGate());
    }

    @Test
    void approvedCanBeLimitedSuspendedAndRestored() {
        var v = fresh();
        v.apply(Decision.APPROVE, "ops-1", null, T);
        v.apply(Decision.LIMIT, "ops-1", "license expiring", T);
        assertFalse(v.eligibleForCatalogGate());
        v.apply(Decision.SUSPEND, "ops-2", "risk alert", T);
        assertThrows(IllegalTransitionException.class, () -> v.apply(Decision.APPROVE, "ops-2", null, T));
        v.apply(Decision.RESTORE, "ops-2", null, T);
        assertTrue(v.eligibleForCatalogGate());
    }

    @Test
    void historyIsImmutableCopy() {
        var v = fresh();
        v.apply(Decision.APPROVE, "ops-1", null, T);
        assertThrows(UnsupportedOperationException.class, () -> v.history().clear());
    }

    @Test
    void blankSubmitterRejected() {
        assertThrows(IllegalArgumentException.class, () -> new PartnerVerification(" "));
    }
}
