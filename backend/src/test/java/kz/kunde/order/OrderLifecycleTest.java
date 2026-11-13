package kz.kunde.order;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.Instant;
import kz.kunde.order.OrderLifecycle.Actor;
import kz.kunde.order.OrderLifecycle.Command;
import kz.kunde.order.OrderLifecycle.DeadlinePassedException;
import kz.kunde.order.OrderLifecycle.IllegalTransitionException;
import kz.kunde.order.OrderLifecycle.Status;
import kz.kunde.order.OrderLifecycle.VersionConflictException;
import org.junit.jupiter.api.Test;

class OrderLifecycleTest {
    private static final Instant T0 = Instant.parse("2026-11-13T10:00:00Z");

    private static Instant at(long seconds) { return T0.plusSeconds(seconds); }

    private static OrderLifecycle fresh() {
        return new OrderLifecycle(ResponsePolicy.foodOrderingDefault(), T0, true);
    }

    @Test
    void defaultsMatchD05AndAreVersionedConfiguration() {
        var o = fresh();
        assertEquals(at(300), o.responseDeadline());
        assertEquals(at(120), o.reminderAt());
        assertEquals("food-ordering-d05-v1", o.policyVersion());
        var custom = new ResponsePolicy("v2", Duration.ofMinutes(10), Duration.ofMinutes(4));
        assertEquals(T0.plusSeconds(600), new OrderLifecycle(custom, T0, true).responseDeadline());
        assertThrows(IllegalArgumentException.class,
                () -> new ResponsePolicy("v3", Duration.ofMinutes(2), Duration.ofMinutes(2)));
        assertThrows(IllegalArgumentException.class, () -> new ResponsePolicy(" ", Duration.ofMinutes(5), Duration.ofMinutes(1)));
    }

    @Test
    void unavailableRestaurantCannotReceiveOrders() {
        assertThrows(IllegalTransitionException.class,
                () -> new OrderLifecycle(ResponsePolicy.foodOrderingDefault(), T0, false));
    }

    @Test
    void restaurantAcceptsWithItsOwnEstimate() {
        var o = fresh();
        assertEquals(0, o.preparationMinutes());
        o.accept("c1", "r-1", 20, 0, at(60));
        assertEquals(Status.ACCEPTED, o.status());
        assertEquals(20, o.preparationMinutes());
        assertThrows(IllegalArgumentException.class, () -> fresh().accept("c1", "r-1", 0, 0, at(1)));
    }

    @Test
    void reminderIsDueOnceBetweenTwoAndFiveMinutes() {
        var o = fresh();
        assertFalse(o.reminderDue(at(119)));
        assertTrue(o.reminderDue(at(120)));
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("rm0", Command.REMIND, Actor.SYSTEM, "system", null, 0, at(119)));
        o.apply("rm1", Command.REMIND, Actor.SYSTEM, "system", null, 0, at(121));
        assertEquals(Status.SUBMITTED, o.status());
        assertFalse(o.reminderDue(at(130)));
        assertEquals(1, o.version());
        assertFalse(fresh().reminderDue(at(300)));
    }

    @Test
    void timeoutOnlyAtDeadlineAndIsTerminal() {
        var o = fresh();
        assertFalse(o.timeoutDue(at(299)));
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("t0", Command.TIMEOUT, Actor.SYSTEM, "system", null, 0, at(299)));
        assertTrue(o.timeoutDue(at(300)));
        o.apply("t1", Command.TIMEOUT, Actor.SYSTEM, "system", "no response", 0, at(300));
        assertEquals(Status.EXPIRED, o.status());
        assertThrows(IllegalTransitionException.class, () -> o.accept("c2", "r-1", 10, 1, at(301)));
    }

    @Test
    void lateAcceptanceTimesOutTheOrderAndNeverRevivesIt() {
        var o = fresh();
        assertThrows(DeadlinePassedException.class, () -> o.accept("c1", "r-1", 15, 0, at(300)));
        assertEquals(Status.EXPIRED, o.status());
        assertEquals(0, o.preparationMinutes());
        assertEquals(Command.TIMEOUT, o.history().get(0).command());
        assertEquals(Actor.SYSTEM, o.history().get(0).actor());
        assertThrows(IllegalTransitionException.class, () -> o.accept("c2", "r-1", 15, o.version(), at(301)));
        assertEquals(Status.EXPIRED, o.status());
    }

    @Test
    void customerCancelsBeforeAcceptanceWithoutPenalty() {
        var o = fresh();
        o.apply("x1", Command.CANCEL, Actor.CUSTOMER, "u-1", null, 0, at(30));
        assertEquals(Status.CANCELLED, o.status());
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("x2", Command.CANCEL, Actor.RESTAURANT, "r-1", null, 1, at(31)));
    }

    @Test
    void cancelAfterDeadlineIsAlreadyExpired() {
        var o = fresh();
        assertThrows(DeadlinePassedException.class,
                () -> o.apply("x1", Command.CANCEL, Actor.CUSTOMER, "u-1", null, 0, at(400)));
        assertEquals(Status.EXPIRED, o.status());
    }

    @Test
    void restaurantRejectNeedsReason() {
        var o = fresh();
        assertThrows(IllegalArgumentException.class,
                () -> o.apply("r1", Command.REJECT, Actor.RESTAURANT, "r-1", " ", 0, at(10)));
        assertEquals(Status.SUBMITTED, o.status());
        o.apply("r2", Command.REJECT, Actor.RESTAURANT, "r-1", "out of stock", 0, at(10));
        assertEquals(Status.REJECTED, o.status());
    }

    @Test
    void wrongActorsAreRejectedWithoutStateChange() {
        var o = fresh();
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("a2", Command.REJECT, Actor.CUSTOMER, "u-1", "x", 0, at(5)));
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("a3", Command.TIMEOUT, Actor.RESTAURANT, "r-1", null, 0, at(400)));
        assertEquals(Status.SUBMITTED, o.status());
        assertEquals(0, o.version());
    }

    @Test
    void replaysAreIdempotentAndStaleVersionsConflict() {
        var o = fresh();
        var first = o.accept("c1", "r-1", 20, 0, at(10));
        assertSame(first, o.accept("c1", "r-1", 45, 0, at(11)));
        assertEquals(20, o.preparationMinutes());
        assertEquals(1, o.version());
        assertEquals(1, o.history().size());
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("c1", Command.REJECT, Actor.RESTAURANT, "r-1", "x", 0, at(12)));
        var stale = assertThrows(VersionConflictException.class,
                () -> o.apply("c9", Command.REQUEST_CANCELLATION, Actor.CUSTOMER, "u-1", "changed mind", 0, at(13)));
        assertEquals(1, stale.currentVersion());
        assertEquals(Status.ACCEPTED, stale.currentStatus());
    }

    @Test
    void substitutionNeedsExplicitApprovalOfTheExactQuoteVersion() {
        var o = fresh();
        assertEquals(1, o.quoteVersion());
        assertThrows(IllegalArgumentException.class, () -> o.proposeChange("p0", "r-1", 1, 0, at(10)));
        o.proposeChange("p1", "r-1", 2, 0, at(10));
        assertEquals(Status.CHANGE_PROPOSED, o.status());
        assertEquals(1, o.quoteVersion());
        assertThrows(IllegalTransitionException.class, () -> o.approveChange("a1", "u-1", 3, 1, at(20)));
        assertThrows(IllegalTransitionException.class, () -> o.accept("a2", "r-1", 10, 1, at(20)));
        o.approveChange("a3", "u-1", 2, 1, at(30));
        assertEquals(Status.ACCEPTED, o.status());
        assertEquals(2, o.quoteVersion());
        assertEquals(2, o.history().get(1).quoteVersion());
    }

    @Test
    void customerMayDeclineProposedChangeWithoutPenalty() {
        var o = fresh();
        o.proposeChange("p1", "r-1", 2, 0, at(10));
        o.apply("d1", Command.DECLINE_CHANGE, Actor.CUSTOMER, "u-1", "do not want substitute", 1, at(500));
        assertEquals(Status.CANCELLED, o.status());
        assertEquals(1, o.quoteVersion());
    }

    @Test
    void cancellationAfterAcceptanceGoesToSupportNotAutoCancelled() {
        var o = fresh();
        o.accept("c1", "r-1", 20, 0, at(10));
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("x1", Command.CANCEL, Actor.CUSTOMER, "u-1", null, 1, at(20)));
        assertThrows(IllegalArgumentException.class,
                () -> o.apply("x2", Command.REQUEST_CANCELLATION, Actor.CUSTOMER, "u-1", null, 1, at(20)));
        o.apply("x3", Command.REQUEST_CANCELLATION, Actor.CUSTOMER, "u-1", "plans changed", 1, at(20));
        assertEquals(Status.SUPPORT_REVIEW, o.status());
        assertThrows(IllegalTransitionException.class,
                () -> o.apply("x4", Command.RESOLVE_CANCEL, Actor.CUSTOMER, "u-1", "self", 2, at(21)));
        o.apply("x5", Command.RESOLVE_CANCEL, Actor.SUPPORT, "s-1", "policy allows", 2, at(30));
        assertEquals(Status.CANCELLED, o.status());
    }

    @Test
    void unfulfillableAcceptedOrderHasDefinedSupportPathAndMayBeKept() {
        var o = fresh();
        o.accept("c1", "r-1", 20, 0, at(10));
        o.apply("f1", Command.REPORT_UNFULFILLABLE, Actor.RESTAURANT, "r-1", "oven broken", 1, at(60));
        assertEquals(Status.SUPPORT_REVIEW, o.status());
        o.apply("k1", Command.RESOLVE_KEEP, Actor.SUPPORT, "s-1", "restaurant fixed it", 2, at(90));
        assertEquals(Status.ACCEPTED, o.status());
    }

    @Test
    void auditTrailRecordsEveryTransitionWithActor() {
        var o = fresh();
        o.apply("rm", Command.REMIND, Actor.SYSTEM, "system", null, 0, at(130));
        o.accept("c1", "r-1", 15, 1, at(140));
        assertEquals(2, o.history().size());
        var last = o.history().get(1);
        assertEquals(Status.SUBMITTED, last.from());
        assertEquals(Status.ACCEPTED, last.to());
        assertEquals("r-1", last.actorId());
        assertThrows(UnsupportedOperationException.class, () -> o.history().clear());
    }
}
