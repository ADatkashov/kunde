package kz.kunde.notification;

import java.time.Duration;
import java.time.Instant;

/**
 * TASK-031: one delivery attempt chain. Statuses stay distinct (queued, sent, delivered, failed,
 * dead-letter); a provider receipt is the only way to reach DELIVERED and never means "read".
 * Contract only: nothing is persisted or sent.
 */
public final class Delivery {
    public enum Status { QUEUED, SENT, DELIVERED, FAILED, DEAD_LETTER }

    static final Duration BASE = Duration.ofSeconds(30);
    static final Duration CAP = Duration.ofHours(1);

    private final int maxAttempts;
    private Status status = Status.QUEUED;
    private int attempts;
    private Instant nextAttemptAt;

    public Delivery(int maxAttempts, Instant now) {
        if (maxAttempts < 1) { throw new IllegalArgumentException("maxAttempts"); }
        this.maxAttempts = maxAttempts;
        this.nextAttemptAt = now;
    }

    public Status status() { return status; }
    public int attempts() { return attempts; }
    public Instant nextAttemptAt() { return nextAttemptAt; }

    /** Provider accepted the message. Only a queued delivery that is due may be sent. */
    public void sent(Instant now) {
        expect(Status.QUEUED);
        if (now.isBefore(nextAttemptAt)) { throw new IllegalStateException("not due"); }
        attempts++;
        status = Status.SENT;
    }

    /** Provider verified receipt. Not proof the user read it. */
    public void delivered() {
        expect(Status.SENT);
        status = Status.DELIVERED;
    }

    /** Transient failure: back off exponentially, or dead-letter once attempts are exhausted. */
    public void failed(Instant now) {
        if (status != Status.QUEUED && status != Status.SENT) { throw new IllegalStateException("cannot fail from " + status); }
        if (status == Status.QUEUED) { attempts++; }
        if (attempts >= maxAttempts) {
            status = Status.DEAD_LETTER;
            nextAttemptAt = null;
            return;
        }
        status = Status.QUEUED;
        long factor = 1L << Math.min(attempts - 1, 20);
        var delay = BASE.multipliedBy(factor);
        nextAttemptAt = now.plus(delay.compareTo(CAP) > 0 ? CAP : delay);
    }

    /** Permanent failure (invalid contact, revoked token): no retry; caller marks the contact unusable. */
    public void failedPermanently() {
        if (status == Status.DELIVERED || status == Status.DEAD_LETTER) { throw new IllegalStateException(status.name()); }
        status = Status.FAILED;
        nextAttemptAt = null;
    }

    private void expect(Status s) {
        if (status != s) { throw new IllegalStateException("expected " + s + " but was " + status); }
    }
}
