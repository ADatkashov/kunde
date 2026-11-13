package kz.kunde.partner;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import kz.kunde.partner.PartnerVerification.Decision;
import kz.kunde.partner.PartnerVerification.IllegalTransitionException;
import kz.kunde.partner.PartnerVerification.Status;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * TASK-015 / D-07: persisted partner, staff roles and verification. Authorization is enforced here, in the
 * backend, from database state; callers pass the internal canonical user id (never a UI-supplied role).
 * Partner isolation: a user who is not active staff of a partner gets the same 404 as for a missing partner.
 *
 * <p>Not exposed over HTTP yet: there is no partner-app client/audience or KUNDE Administrator identity
 * (D-14 separation of duties is open). {@link #reviewVerification} therefore assumes the caller already
 * proved the reviewer is an authorized KUNDE Administrator; it only refuses reviewers who are staff of the
 * partner under review. Nothing here enables catalog, offerings or orders (ADR-014 gates stay closed).
 */
@Service
public class PartnerService {
    public enum Role { OWNER, MANAGER, OPERATOR }

    public record PartnerView(UUID id, String displayName, Status verificationStatus, long version) { }

    public record StaffView(UUID userId, Role role, String status) { }

    private static final RowMapper<PartnerView> PARTNER = (rs, i) -> new PartnerView(
            rs.getObject("id", UUID.class), rs.getString("display_name"),
            Status.valueOf(rs.getString("verification_status")), rs.getLong("version"));

    private final JdbcTemplate db;

    public PartnerService(JdbcTemplate db) {
        this.db = db;
    }

    /** The applicant becomes the first OWNER; verification starts as PENDING_REVIEW. */
    @Transactional
    public PartnerView apply(UUID applicantUserId, String displayName) {
        requireActiveUser(applicantUserId);
        String name = displayName == null ? "" : displayName.strip();
        if (name.isEmpty() || name.length() > 120) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PARTNER_NAME", "Name must be 1-120 characters");
        }
        UUID id = db.queryForObject("""
                INSERT INTO marketplace.partners (display_name, created_by_user_id) VALUES (?, ?) RETURNING id
                """, UUID.class, name, applicantUserId);
        db.update("""
                INSERT INTO marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id)
                VALUES (?, ?, 'OWNER', ?)""", id, applicantUserId, applicantUserId);
        staffEvent(id, applicantUserId, applicantUserId, "GRANTED", Role.OWNER);
        db.update("""
                INSERT INTO marketplace.partner_verification_events (partner_id, decision, to_status, actor_user_id)
                VALUES (?, 'SUBMIT', 'PENDING_REVIEW', ?)""", id, applicantUserId);
        return load(id);
    }

    /** Any active staff member may read the partner they belong to. */
    @Transactional(readOnly = true)
    public PartnerView get(UUID actorUserId, UUID partnerId) {
        requireRole(partnerId, actorUserId, Role.OWNER, Role.MANAGER, Role.OPERATOR);
        return load(partnerId);
    }

    /** Staff administration is an Owner capability (D-07); Managers and Operators cannot see or change it. */
    @Transactional(readOnly = true)
    public List<StaffView> listStaff(UUID actorUserId, UUID partnerId) {
        requireRole(partnerId, actorUserId, Role.OWNER);
        return db.query("""
                SELECT user_id, role, status FROM marketplace.partner_staff WHERE partner_id = ?
                ORDER BY granted_at, user_id""",
                (rs, i) -> new StaffView(rs.getObject(1, UUID.class), Role.valueOf(rs.getString(2)), rs.getString(3)),
                partnerId);
    }

    /**
     * Owner grants or changes a role for an individual user. Re-granting the same active role is a no-op;
     * a revoked member is reactivated. Serialized per partner so the last-owner rule cannot be raced.
     */
    @Transactional
    public void grantStaff(UUID actorUserId, UUID partnerId, UUID targetUserId, Role role) {
        requireRole(partnerId, actorUserId, Role.OWNER);
        lockPartner(partnerId);
        requireActiveUser(targetUserId);
        var current = db.query("SELECT role, status FROM marketplace.partner_staff WHERE partner_id = ? AND user_id = ?",
                (rs, i) -> new String[] {rs.getString(1), rs.getString(2)}, partnerId, targetUserId);
        if (current.isEmpty()) {
            db.update("""
                    INSERT INTO marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id)
                    VALUES (?, ?, ?, ?)""", partnerId, targetUserId, role.name(), actorUserId);
        } else if (current.get(0)[0].equals(role.name()) && current.get(0)[1].equals("ACTIVE")) {
            return;
        } else {
            if (current.get(0)[0].equals(Role.OWNER.name()) && current.get(0)[1].equals("ACTIVE")
                    && role != Role.OWNER && activeOwners(partnerId) <= 1) {
                throw new ApiException(HttpStatus.CONFLICT, "LAST_OWNER", "A partner must keep at least one active owner");
            }
            db.update("""
                    UPDATE marketplace.partner_staff SET role = ?, status = 'ACTIVE', granted_by_user_id = ?,
                        granted_at = now(), revoked_by_user_id = NULL, revoked_at = NULL
                    WHERE partner_id = ? AND user_id = ?""", role.name(), actorUserId, partnerId, targetUserId);
        }
        staffEvent(partnerId, targetUserId, actorUserId, "GRANTED", role);
    }

    /** Owner revokes access immediately; the row is kept for audit. Revoking twice is a no-op. */
    @Transactional
    public void revokeStaff(UUID actorUserId, UUID partnerId, UUID targetUserId) {
        requireRole(partnerId, actorUserId, Role.OWNER);
        lockPartner(partnerId);
        var current = db.query("SELECT role, status FROM marketplace.partner_staff WHERE partner_id = ? AND user_id = ?",
                (rs, i) -> new String[] {rs.getString(1), rs.getString(2)}, partnerId, targetUserId);
        if (current.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "STAFF_NOT_FOUND", "Staff member not found");
        }
        if (current.get(0)[1].equals("REVOKED")) {
            return;
        }
        if (current.get(0)[0].equals(Role.OWNER.name()) && activeOwners(partnerId) <= 1) {
            throw new ApiException(HttpStatus.CONFLICT, "LAST_OWNER", "A partner must keep at least one active owner");
        }
        db.update("""
                UPDATE marketplace.partner_staff SET status = 'REVOKED', revoked_by_user_id = ?, revoked_at = now()
                WHERE partner_id = ? AND user_id = ?""", actorUserId, partnerId, targetUserId);
        staffEvent(partnerId, targetUserId, actorUserId, "REVOKED", Role.valueOf(current.get(0)[0]));
    }

    /** The applicant answers a request for more information. */
    @Transactional
    public PartnerView resubmit(UUID applicantUserId, UUID partnerId, long expectedVersion) {
        requireRole(partnerId, applicantUserId, Role.OWNER);
        return decide(applicantUserId, partnerId, Decision.RESUBMIT, null, expectedVersion);
    }

    /**
     * Manual verification decision by a KUNDE reviewer (see class note on the missing administrator identity).
     * Reviewers who are staff of the partner are refused; unauthorized or cross-partner access gets no data.
     */
    @Transactional
    public PartnerView reviewVerification(UUID reviewerUserId, UUID partnerId, Decision decision, String reason,
                                          long expectedVersion) {
        if (decision == Decision.RESUBMIT) {
            throw new ApiException(HttpStatus.FORBIDDEN, "REVIEWER_FORBIDDEN", "Resubmission is an applicant action");
        }
        requireActiveUser(reviewerUserId);
        Integer staffRows = db.queryForObject(
                "SELECT count(*) FROM marketplace.partner_staff WHERE partner_id = ? AND user_id = ?",
                Integer.class, partnerId, reviewerUserId);
        if (staffRows != null && staffRows > 0) {
            throw new ApiException(HttpStatus.FORBIDDEN, "REVIEWER_FORBIDDEN", "Partner staff cannot review their own partner");
        }
        return decide(reviewerUserId, partnerId, decision, reason, expectedVersion);
    }

    /** Role of an active staff member, empty for strangers and revoked members. */
    @Transactional(readOnly = true)
    public Optional<Role> activeRole(UUID partnerId, UUID userId) {
        return db.query("""
                SELECT s.role FROM marketplace.partner_staff s JOIN identity.users u ON u.id = s.user_id
                WHERE s.partner_id = ? AND s.user_id = ? AND s.status = 'ACTIVE' AND u.status = 'ACTIVE'""",
                (rs, i) -> Role.valueOf(rs.getString(1)), partnerId, userId).stream().findFirst();
    }

    /** Fail-closed gate for processing orders later: active staff of a partner whose verification is APPROVED. */
    @Transactional(readOnly = true)
    public boolean mayProcessOrders(UUID userId, UUID partnerId) {
        return activeRole(partnerId, userId).isPresent() && eligibleForCatalogGate(partnerId);
    }

    /** Only APPROVED is eligible for later catalog gates; it enables nothing by itself. */
    @Transactional(readOnly = true)
    public boolean eligibleForCatalogGate(UUID partnerId) {
        return db.query("SELECT verification_status FROM marketplace.partners WHERE id = ?",
                (rs, i) -> rs.getString(1), partnerId).stream().anyMatch(Status.APPROVED.name()::equals);
    }

    private PartnerView decide(UUID actor, UUID partnerId, Decision decision, String reason, long expectedVersion) {
        var row = db.query("""
                SELECT created_by_user_id, version FROM marketplace.partners WHERE id = ? FOR UPDATE""",
                (rs, i) -> new Object[] {rs.getObject(1, UUID.class), rs.getLong(2)}, partnerId);
        if (row.isEmpty()) {
            throw notFound();
        }
        if ((long) row.get(0)[1] != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "Partner changed; refresh and retry");
        }
        var machine = new PartnerVerification(row.get(0)[0].toString());
        db.query("""
                SELECT decision, actor_user_id, reason, occurred_at FROM marketplace.partner_verification_events
                WHERE partner_id = ? AND decision <> 'SUBMIT' ORDER BY id""", rs -> {
            machine.apply(Decision.valueOf(rs.getString(1)), rs.getObject(2, UUID.class).toString(),
                    rs.getString(3), rs.getTimestamp(4).toInstant());
        }, partnerId);
        PartnerVerification.Entry entry;
        try {
            entry = machine.apply(decision, actor.toString(), reason, Instant.now());
        } catch (IllegalTransitionException e) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_VERIFICATION_TRANSITION", e.getMessage());
        } catch (IllegalArgumentException e) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_VERIFICATION_REQUEST", e.getMessage());
        }
        db.update("""
                INSERT INTO marketplace.partner_verification_events
                    (partner_id, decision, from_status, to_status, actor_user_id, reason)
                VALUES (?, ?, ?, ?, ?, ?)""", partnerId, decision.name(), entry.from().name(), entry.to().name(),
                actor, entry.reason() == null ? null : entry.reason().strip());
        db.update("""
                UPDATE marketplace.partners SET verification_status = ?, version = version + 1, updated_at = now()
                WHERE id = ?""", entry.to().name(), partnerId);
        return load(partnerId);
    }

    private PartnerView load(UUID partnerId) {
        return db.queryForObject(
                "SELECT id, display_name, verification_status, version FROM marketplace.partners WHERE id = ?",
                PARTNER, partnerId);
    }

    private void lockPartner(UUID partnerId) {
        db.queryForList("SELECT 1 FROM marketplace.partners WHERE id = ? FOR UPDATE", partnerId);
    }

    private int activeOwners(UUID partnerId) {
        Integer n = db.queryForObject("""
                SELECT count(*) FROM marketplace.partner_staff s JOIN identity.users u ON u.id = s.user_id
                WHERE s.partner_id = ? AND s.role = 'OWNER' AND s.status = 'ACTIVE' AND u.status = 'ACTIVE'""",
                Integer.class, partnerId);
        return n == null ? 0 : n;
    }

    private void staffEvent(UUID partnerId, UUID subject, UUID actor, String type, Role role) {
        db.update("""
                INSERT INTO marketplace.partner_staff_events (partner_id, subject_user_id, actor_user_id, event_type, role)
                VALUES (?, ?, ?, ?, ?)""", partnerId, subject, actor, type, role.name());
    }

    private void requireActiveUser(UUID userId) {
        boolean active = db.query("SELECT status FROM identity.users WHERE id = ?", (rs, i) -> rs.getString(1), userId)
                .stream().anyMatch("ACTIVE"::equals);
        if (!active) {
            throw new ApiException(HttpStatus.FORBIDDEN, "USER_NOT_ACTIVE", "User is not active");
        }
    }

    /** Stranger or revoked: 404 (partner existence is not revealed); wrong role: 403. */
    private void requireRole(UUID partnerId, UUID userId, Role... allowed) {
        Role role = activeRole(partnerId, userId).orElseThrow(PartnerService::notFound);
        if (!List.of(allowed).contains(role)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "PARTNER_ROLE_FORBIDDEN", "Role is not allowed to do this");
        }
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND", "Partner not found");
    }
}
