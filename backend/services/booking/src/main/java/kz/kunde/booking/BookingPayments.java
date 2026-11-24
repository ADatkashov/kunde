package kz.kunde.booking;

import java.util.UUID;

/**
 * What the booking engine needs from a payment ledger (DEV ledger only today, no real provider). The implementation lives with
 * the owner of the ledger tables (auto), so the engine does not depend on a product module.
 */
public interface BookingPayments {
    /** Validates the requested payment method (null means the default) and returns its code. */
    String method(String requested);

    /** The method of the booking's payment. */
    String methodOfBooking(UUID bookingId);

    void open(UUID user, UUID bookingId, UUID jobId, String method, long amountMinor);

    void capture(UUID bookingId, UUID jobId, long amountMinor, String actorType, UUID actor);

    void voidHold(UUID bookingId, UUID jobId, String actorType, UUID actor, String reason);
}
