package kz.kunde.platform.partner;

import java.util.Set;
import java.util.UUID;

/**
 * What other products may ask about partner organizations without reading Partner's tables (ADR-021).
 *
 * <p>Two kinds of questions with different guarantees:
 * <ul>
 *   <li><b>Plain reads</b> ({@link #isActiveStaffOfApprovedPartner}, {@link #approvedPartnersOfStaff}) are a snapshot at
 *       the moment of the call. Use them for listing and display, where a status change a moment later is harmless.</li>
 *   <li><b>Locking checks</b> ({@link #lockActiveStaffOfApprovedPartner}) must run inside the caller's transaction. While that
 *       transaction is open a concurrent suspension of the partner or revocation of the staff member waits, so the
 *       caller's write cannot commit after the partner was already taken out of service. Only an in-process adapter can
 *       offer this; a remote adapter must replace the check by re-validation or a compensating step (ADR-021).</li>
 * </ul>
 * Role-based authorization (owner, manager) stays in Partner's own service; this contract answers only "approved and
 * active".
 */
public interface PartnerDirectory {
    boolean isActiveStaffOfApprovedPartner(UUID userId, UUID partnerId);

    /** Partners that are APPROVED and where the user is ACTIVE staff (any role). Empty if none. */
    Set<UUID> approvedPartnersOfStaff(UUID userId);

    /**
     * Same answer as {@link #isActiveStaffOfApprovedPartner} but takes a shared row lock on the partner and the staff
     * membership until the surrounding transaction ends. Must be called inside a transaction.
     */
    boolean lockActiveStaffOfApprovedPartner(UUID userId, UUID partnerId);
}
