package kz.kunde.fulfillment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.Set;
import kz.kunde.fulfillment.PickupFulfillment.Actor;
import kz.kunde.fulfillment.PickupFulfillment.Command;
import kz.kunde.fulfillment.PickupFulfillment.IllegalTransitionException;
import kz.kunde.fulfillment.PickupFulfillment.Status;
import kz.kunde.fulfillment.PickupFulfillment.VersionConflictException;
import org.junit.jupiter.api.Test;

class PickupFulfillmentTest {
    private static final Instant T = Instant.parse("2026-11-13T00:00:00Z");

    private static PickupFulfillment fresh() {
        return new PickupFulfillment(FulfillmentPolicy.of(Set.of(FulfillmentMethod.PICKUP)));
    }

    private static void merchant(PickupFulfillment f, String id, Command c) {
        f.apply(id, c, Actor.MERCHANT, "m-1", null, f.version(), T);
    }

    @Test
    void policyDefaultsToNothingEnabledAndRejectsUnsupportedMethods() {
        assertTrue(FulfillmentPolicy.disabled().enabledMethods().isEmpty());
        assertThrows(IllegalArgumentException.class,
                () -> FulfillmentPolicy.of(Set.of(FulfillmentMethod.MERCHANT_DELIVERY)));
        assertThrows(IllegalArgumentException.class,
                () -> FulfillmentPolicy.of(Set.of(FulfillmentMethod.PICKUP, FulfillmentMethod.THIRD_PARTY_DELIVERY)));
        assertTrue(FulfillmentPolicy.of(Set.of(FulfillmentMethod.PICKUP)).isEnabled(FulfillmentMethod.PICKUP));
        assertFalse(FulfillmentPolicy.of(Set.of(FulfillmentMethod.PICKUP)).isEnabled(FulfillmentMethod.MERCHANT_DELIVERY));
    }

    @Test
    void cannotBeCreatedWhenPickupIsDisabled() {
        assertThrows(IllegalTransitionException.class, () -> new PickupFulfillment(FulfillmentPolicy.disabled()));
    }

    @Test
    void merchantDrivesPickupToHandoverWithAudit() {
        var f = fresh();
        assertFalse(f.handedOver());
        merchant(f, "c1", Command.START_PREPARING);
        merchant(f, "c2", Command.MARK_READY);
        assertFalse(f.handedOver());
        merchant(f, "c3", Command.CONFIRM_HANDOVER);
        assertTrue(f.handedOver());
        assertEquals(Status.HANDED_OVER, f.status());
        assertEquals(3, f.version());
        assertEquals(3, f.history().size());
        assertEquals(Status.READY_FOR_PICKUP, f.history().get(2).from());
        assertEquals("m-1", f.history().get(2).actorId());
    }

    @Test
    void rejectsSkippedAndTerminalTransitions() {
        var f = fresh();
        assertThrows(IllegalTransitionException.class, () -> merchant(f, "x1", Command.MARK_READY));
        assertThrows(IllegalTransitionException.class, () -> merchant(f, "x2", Command.CONFIRM_HANDOVER));
        merchant(f, "c1", Command.START_PREPARING);
        merchant(f, "c2", Command.MARK_READY);
        merchant(f, "c3", Command.CONFIRM_HANDOVER);
        assertThrows(IllegalTransitionException.class, () -> merchant(f, "x3", Command.START_PREPARING));
        assertThrows(IllegalTransitionException.class,
                () -> f.apply("x4", Command.ABORT, Actor.PLATFORM, "p", "late", f.version(), T));
        assertEquals(3, f.history().size());
    }

    @Test
    void onlyTheMerchantAdvancesFulfillment() {
        var f = fresh();
        assertThrows(IllegalTransitionException.class,
                () -> f.apply("c1", Command.START_PREPARING, Actor.CONSUMER, "u", null, 0, T));
        assertThrows(IllegalTransitionException.class,
                () -> f.apply("c2", Command.START_PREPARING, Actor.PLATFORM, "p", null, 0, T));
        assertEquals(Status.PENDING, f.status());
        assertEquals(0, f.version());
    }

    @Test
    void abortNeedsReasonAndIsTerminal() {
        var f = fresh();
        assertThrows(IllegalArgumentException.class,
                () -> f.apply("a1", Command.ABORT, Actor.PLATFORM, "p", " ", 0, T));
        f.apply("a2", Command.ABORT, Actor.PLATFORM, "p", "order cancelled", 0, T);
        assertEquals(Status.CANCELLED, f.status());
        assertThrows(IllegalTransitionException.class, () -> merchant(f, "c1", Command.START_PREPARING));
    }

    @Test
    void replayedCommandIsIdempotentAndIdReuseIsRejected() {
        var f = fresh();
        var first = f.apply("c1", Command.START_PREPARING, Actor.MERCHANT, "m-1", null, 0, T);
        var replay = f.apply("c1", Command.START_PREPARING, Actor.MERCHANT, "m-1", null, 0, T);
        assertSame(first, replay);
        assertEquals(1, f.version());
        assertEquals(1, f.history().size());
        assertThrows(IllegalTransitionException.class,
                () -> f.apply("c1", Command.MARK_READY, Actor.MERCHANT, "m-1", null, 1, T));
        assertEquals(Status.PREPARING, f.status());
    }

    @Test
    void staleVersionReportsCurrentStateAndChangesNothing() {
        var f = fresh();
        merchant(f, "c1", Command.START_PREPARING);
        var conflict = assertThrows(VersionConflictException.class,
                () -> f.apply("c2", Command.MARK_READY, Actor.MERCHANT, "m-1", null, 0, T));
        assertEquals(1, conflict.currentVersion());
        assertEquals(Status.PREPARING, conflict.currentStatus());
        assertEquals(1, f.history().size());
    }

    @Test
    void requiresCommandIdAndActorId() {
        var f = fresh();
        assertThrows(IllegalArgumentException.class,
                () -> f.apply(" ", Command.START_PREPARING, Actor.MERCHANT, "m", null, 0, T));
        assertThrows(IllegalArgumentException.class,
                () -> f.apply("c", Command.START_PREPARING, Actor.MERCHANT, "", null, 0, T));
    }
}
