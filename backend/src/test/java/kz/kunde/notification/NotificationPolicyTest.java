package kz.kunde.notification;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;
import kz.kunde.notification.NotificationPolicy.Channel;
import kz.kunde.notification.NotificationPolicy.Kind;
import kz.kunde.notification.NotificationPolicy.Preferences;
import org.junit.jupiter.api.Test;

class NotificationPolicyTest {
    private static final Instant T = Instant.parse("2026-11-13T00:00:00Z");
    private static final Preferences ALL = new Preferences(Set.of(Channel.PUSH, Channel.SMS), true, true);
    private static final Preferences NONE = new Preferences(Set.of(), false, false);

    @Test
    void inAppAlwaysPresentEvenWithNothingUsable() {
        for (var k : Kind.values()) {
            assertTrue(NotificationPolicy.eligibleChannels(k, NONE, false).contains(Channel.IN_APP));
        }
    }

    @Test
    void mandatoryKindsUseEveryUsableChannelRegardlessOfQuietHours() {
        var c = NotificationPolicy.eligibleChannels(Kind.SECURITY_MANDATORY, ALL, true);
        assertEquals(Set.of(Channel.IN_APP, Channel.PUSH, Channel.SMS), c);
    }

    @Test
    void marketingNeedsConsentAndNoQuietHours() {
        var noConsent = new Preferences(Set.of(Channel.PUSH), false, true);
        assertEquals(Set.of(Channel.IN_APP), NotificationPolicy.eligibleChannels(Kind.MARKETING_OPTIONAL, noConsent, false));
        assertEquals(Set.of(Channel.IN_APP), NotificationPolicy.eligibleChannels(Kind.MARKETING_OPTIONAL, ALL, true));
        assertTrue(NotificationPolicy.eligibleChannels(Kind.MARKETING_OPTIONAL, ALL, false).contains(Channel.SMS));
    }

    @Test
    void operationalPushOnlyWhenAllowedAndUsable() {
        assertEquals(Set.of(Channel.IN_APP, Channel.PUSH),
                NotificationPolicy.eligibleChannels(Kind.USER_REQUESTED_OPERATIONAL, ALL, false));
        var off = new Preferences(Set.of(Channel.PUSH), false, false);
        assertEquals(Set.of(Channel.IN_APP), NotificationPolicy.eligibleChannels(Kind.USER_REQUESTED_OPERATIONAL, off, false));
    }

    @Test
    void dedupKeyIsStableAndRejectsAmbiguousParts() {
        assertEquals("e1|u1|PUSH", NotificationPolicy.dedupKey("e1", "u1", Channel.PUSH));
        assertThrows(IllegalArgumentException.class, () -> NotificationPolicy.dedupKey("e|1", "u1", Channel.PUSH));
        assertThrows(IllegalArgumentException.class, () -> NotificationPolicy.dedupKey(" ", "u1", Channel.PUSH));
    }

    @Test
    void lockScreenTextRules() {
        assertTrue(NotificationPolicy.safeForLockScreen("Order status changed"));
        assertFalse(NotificationPolicy.safeForLockScreen("Card 4111111111111111"));
        assertFalse(NotificationPolicy.safeForLockScreen("a@b.kz"));
        assertFalse(NotificationPolicy.safeForLockScreen("see https://x.y"));
        assertFalse(NotificationPolicy.safeForLockScreen("x".repeat(121)));
        assertFalse(NotificationPolicy.safeForLockScreen(null));
    }

    @Test
    void deliveryHappyPathKeepsStatusesDistinct() {
        var d = new Delivery(3, T);
        d.sent(T);
        assertEquals(Delivery.Status.SENT, d.status());
        d.delivered();
        assertEquals(Delivery.Status.DELIVERED, d.status());
        assertThrows(IllegalStateException.class, d::failedPermanently);
    }

    @Test
    void deliveryBacksOffExponentiallyThenDeadLetters() {
        var d = new Delivery(3, T);
        d.sent(T);
        d.failed(T);
        assertEquals(T.plus(Duration.ofSeconds(30)), d.nextAttemptAt());
        assertThrows(IllegalStateException.class, () -> d.sent(T));
        var t2 = T.plusSeconds(30);
        d.sent(t2);
        d.failed(t2);
        assertEquals(t2.plus(Duration.ofSeconds(60)), d.nextAttemptAt());
        var t3 = t2.plusSeconds(60);
        d.sent(t3);
        d.failed(t3);
        assertEquals(Delivery.Status.DEAD_LETTER, d.status());
        assertNull(d.nextAttemptAt());
        assertEquals(3, d.attempts());
    }

    @Test
    void backoffIsCapped() {
        var d = new Delivery(100, T);
        var now = T;
        for (int i = 0; i < 40; i++) {
            d.sent(d.nextAttemptAt().isAfter(now) ? d.nextAttemptAt() : now);
            now = d.nextAttemptAt();
            d.failed(now);
        }
        assertEquals(now.plus(Duration.ofHours(1)), d.nextAttemptAt());
    }

    @Test
    void permanentFailureStopsRetries() {
        var d = new Delivery(3, T);
        d.failedPermanently();
        assertEquals(Delivery.Status.FAILED, d.status());
        assertThrows(IllegalStateException.class, () -> d.sent(T));
    }
}
