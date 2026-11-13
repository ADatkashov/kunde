package kz.kunde.order;

import java.time.Duration;
import java.util.Objects;

/**
 * D-05 restaurant response policy. Values are configuration, not constants: each lifecycle records the
 * {@code version} it was submitted under, so later policy changes never alter an order in flight.
 */
public record ResponsePolicy(String version, Duration confirmationWindow, Duration reminderAfter) {
    public ResponsePolicy {
        if (version == null || version.isBlank()) {
            throw new IllegalArgumentException("version is required");
        }
        Objects.requireNonNull(confirmationWindow, "confirmationWindow");
        Objects.requireNonNull(reminderAfter, "reminderAfter");
        if (confirmationWindow.isZero() || confirmationWindow.isNegative()
                || reminderAfter.isZero() || reminderAfter.isNegative()
                || reminderAfter.compareTo(confirmationWindow) >= 0) {
            throw new IllegalArgumentException("0 < reminderAfter < confirmationWindow is required");
        }
    }

    /** Initial Food Ordering defaults approved in D-05 (2026-11-13): 5 minutes to respond, reminder after 2. */
    public static ResponsePolicy foodOrderingDefault() {
        return new ResponsePolicy("food-ordering-d05-v1", Duration.ofMinutes(5), Duration.ofMinutes(2));
    }
}
