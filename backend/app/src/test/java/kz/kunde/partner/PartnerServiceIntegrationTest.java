package kz.kunde.partner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import kz.kunde.partner.PartnerService.PartnerView;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.partner.PartnerVerification.Decision;
import kz.kunde.partner.PartnerVerification.Status;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * TASK-015 / D-07 against the Flyway-migrated PostgreSQL schema. Synthetic users only; every test rolls back.
 * Verifies backend-enforced roles, partner isolation, revocation, auditability and the verification gate.
 */
@SpringBootTest
@Transactional
class PartnerServiceIntegrationTest {
    @Autowired PartnerService partners;
    @Autowired JdbcTemplate jdbc;

    private UUID user() {
        return jdbc.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private static void assertApi(Runnable call, HttpStatus status, String code) {
        assertThatThrownBy(call::run).isInstanceOfSatisfying(ApiException.class, e -> {
            assertThat(e.status()).isEqualTo(status);
            assertThat(e.code()).isEqualTo(code);
        });
    }

    @Test
    void applicationCreatesPendingPartnerWithItsApplicantAsAuditedOwner() {
        UUID owner = user();
        PartnerView p = partners.apply(owner, "  Synthetic Cafe  ");
        assertThat(p.displayName()).isEqualTo("Synthetic Cafe");
        assertThat(p.verificationStatus()).isEqualTo(Status.PENDING_REVIEW);
        assertThat(partners.activeRole(p.id(), owner)).contains(Role.OWNER);
        assertThat(partners.eligibleForCatalogGate(p.id())).isFalse();
        assertThat(jdbc.queryForObject("select count(*) from marketplace.partner_staff_events where partner_id = ?",
                Integer.class, p.id())).isEqualTo(1);
        assertThat(jdbc.queryForObject("select decision from marketplace.partner_verification_events where partner_id = ?",
                String.class, p.id())).isEqualTo("SUBMIT");
        assertApi(() -> partners.apply(owner, "   "), HttpStatus.BAD_REQUEST, "INVALID_PARTNER_NAME");
        assertApi(() -> partners.apply(owner, "x".repeat(121)), HttpStatus.BAD_REQUEST, "INVALID_PARTNER_NAME");
    }

    @Test
    void inactiveUsersCannotApplyOrBeGrantedAccess() {
        UUID owner = user();
        UUID restricted = user();
        jdbc.update("update identity.users set status = 'RESTRICTED' where id = ?", restricted);
        assertApi(() -> partners.apply(restricted, "Synthetic"), HttpStatus.FORBIDDEN, "USER_NOT_ACTIVE");
        UUID id = partners.apply(owner, "Synthetic").id();
        assertApi(() -> partners.grantStaff(owner, id, restricted, Role.OPERATOR), HttpStatus.FORBIDDEN, "USER_NOT_ACTIVE");
        assertApi(() -> partners.apply(UUID.randomUUID(), "Synthetic"), HttpStatus.FORBIDDEN, "USER_NOT_ACTIVE");
    }

    @Test
    void strangersAndOtherPartnersStaffSeeNothingNotEvenExistence() {
        UUID ownerA = user();
        UUID ownerB = user();
        UUID a = partners.apply(ownerA, "A").id();
        UUID b = partners.apply(ownerB, "B").id();
        assertApi(() -> partners.get(ownerB, a), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertApi(() -> partners.get(ownerB, UUID.randomUUID()), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertApi(() -> partners.listStaff(ownerB, a), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertApi(() -> partners.grantStaff(ownerB, a, ownerB, Role.OWNER), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertApi(() -> partners.revokeStaff(ownerB, a, ownerA), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertThat(partners.activeRole(a, ownerB)).isEmpty();
        assertThat(partners.get(ownerB, b).displayName()).isEqualTo("B");
        assertThat(partners.listStaff(ownerA, a)).hasSize(1);
    }

    @Test
    void managersAndOperatorsReadButNeverAdministerStaff() {
        UUID owner = user();
        UUID manager = user();
        UUID operator = user();
        UUID id = partners.apply(owner, "Synthetic").id();
        partners.grantStaff(owner, id, manager, Role.MANAGER);
        partners.grantStaff(owner, id, operator, Role.OPERATOR);
        assertThat(partners.get(manager, id).id()).isEqualTo(id);
        assertThat(partners.get(operator, id).id()).isEqualTo(id);
        for (UUID actor : new UUID[] {manager, operator}) {
            assertApi(() -> partners.listStaff(actor, id), HttpStatus.FORBIDDEN, "PARTNER_ROLE_FORBIDDEN");
            assertApi(() -> partners.grantStaff(actor, id, actor, Role.OWNER), HttpStatus.FORBIDDEN, "PARTNER_ROLE_FORBIDDEN");
            assertApi(() -> partners.revokeStaff(actor, id, owner), HttpStatus.FORBIDDEN, "PARTNER_ROLE_FORBIDDEN");
        }
        assertThat(partners.activeRole(id, manager)).contains(Role.MANAGER);
        assertThat(partners.activeRole(id, operator)).contains(Role.OPERATOR);
    }

    @Test
    void grantIsIdempotentRoleChangeAndRevokeAreAuditedAndAccessEndsImmediately() {
        UUID owner = user();
        UUID member = user();
        UUID id = partners.apply(owner, "Synthetic").id();
        partners.grantStaff(owner, id, member, Role.OPERATOR);
        partners.grantStaff(owner, id, member, Role.OPERATOR);
        assertThat(events(id)).isEqualTo(2);
        partners.grantStaff(owner, id, member, Role.MANAGER);
        assertThat(partners.activeRole(id, member)).contains(Role.MANAGER);
        assertThat(events(id)).isEqualTo(3);

        partners.revokeStaff(owner, id, member);
        partners.revokeStaff(owner, id, member);
        assertThat(events(id)).isEqualTo(4);
        assertThat(partners.activeRole(id, member)).isEmpty();
        assertApi(() -> partners.get(member, id), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertApi(() -> partners.revokeStaff(owner, id, user()), HttpStatus.NOT_FOUND, "STAFF_NOT_FOUND");

        partners.grantStaff(owner, id, member, Role.OPERATOR);
        assertThat(partners.activeRole(id, member)).contains(Role.OPERATOR);
        assertThat(jdbc.queryForObject("""
                select count(*) from marketplace.partner_staff where partner_id = ? and user_id = ? and revoked_at is null
                """, Integer.class, id, member)).isEqualTo(1);
    }

    @Test
    void aPartnerAlwaysKeepsAnActiveOwner() {
        UUID owner = user();
        UUID second = user();
        UUID id = partners.apply(owner, "Synthetic").id();
        assertApi(() -> partners.revokeStaff(owner, id, owner), HttpStatus.CONFLICT, "LAST_OWNER");
        assertApi(() -> partners.grantStaff(owner, id, owner, Role.MANAGER), HttpStatus.CONFLICT, "LAST_OWNER");
        partners.grantStaff(owner, id, second, Role.OWNER);
        partners.revokeStaff(owner, id, owner);
        assertThat(partners.activeRole(id, owner)).isEmpty();
        assertApi(() -> partners.revokeStaff(second, id, second), HttpStatus.CONFLICT, "LAST_OWNER");
    }

    @Test
    void verificationDecisionsAreAuditedVersionedAndGateOrderProcessing() {
        UUID owner = user();
        UUID operator = user();
        UUID reviewer = user();
        UUID id = partners.apply(owner, "Synthetic").id();
        partners.grantStaff(owner, id, operator, Role.OPERATOR);
        assertThat(partners.mayProcessOrders(operator, id)).isFalse();

        assertApi(() -> partners.reviewVerification(reviewer, id, Decision.APPROVE, null, 5),
                HttpStatus.CONFLICT, "VERSION_CONFLICT");
        assertApi(() -> partners.reviewVerification(reviewer, id, Decision.REJECT, " ", 0),
                HttpStatus.BAD_REQUEST, "INVALID_VERIFICATION_REQUEST");
        assertApi(() -> partners.reviewVerification(reviewer, id, Decision.SUSPEND, "x", 0),
                HttpStatus.CONFLICT, "INVALID_VERIFICATION_TRANSITION");
        assertApi(() -> partners.reviewVerification(owner, id, Decision.APPROVE, null, 0),
                HttpStatus.FORBIDDEN, "REVIEWER_FORBIDDEN");
        assertApi(() -> partners.reviewVerification(operator, id, Decision.APPROVE, null, 0),
                HttpStatus.FORBIDDEN, "REVIEWER_FORBIDDEN");
        assertApi(() -> partners.reviewVerification(reviewer, id, Decision.RESUBMIT, null, 0),
                HttpStatus.FORBIDDEN, "REVIEWER_FORBIDDEN");

        PartnerView approved = partners.reviewVerification(reviewer, id, Decision.APPROVE, null, 0);
        assertThat(approved.verificationStatus()).isEqualTo(Status.APPROVED);
        assertThat(approved.version()).isEqualTo(1);
        assertThat(partners.eligibleForCatalogGate(id)).isTrue();
        assertThat(partners.mayProcessOrders(operator, id)).isTrue();
        assertThat(partners.mayProcessOrders(reviewer, id)).isFalse();

        PartnerView suspended = partners.reviewVerification(reviewer, id, Decision.SUSPEND, "complaint", 1);
        assertThat(suspended.verificationStatus()).isEqualTo(Status.SUSPENDED);
        assertThat(partners.mayProcessOrders(operator, id)).isFalse();
        assertThat(jdbc.queryForList("""
                select decision from marketplace.partner_verification_events where partner_id = ? order by id""",
                String.class, id)).containsExactly("SUBMIT", "APPROVE", "SUSPEND");
    }

    @Test
    void infoRequestResubmitAndRejectFollowTheStateMachine() {
        UUID owner = user();
        UUID second = user();
        UUID reviewer = user();
        UUID id = partners.apply(owner, "Synthetic").id();
        partners.grantStaff(owner, id, second, Role.OWNER);

        assertThat(partners.reviewVerification(reviewer, id, Decision.REQUEST_INFO, "need address", 0).verificationStatus())
                .isEqualTo(Status.INFO_REQUESTED);
        // Only the applicant resubmits (PartnerVerification rule), even another owner may not.
        assertApi(() -> partners.resubmit(second, id, 1), HttpStatus.CONFLICT, "INVALID_VERIFICATION_TRANSITION");
        assertApi(() -> partners.resubmit(user(), id, 1), HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND");
        assertThat(partners.resubmit(owner, id, 1).verificationStatus()).isEqualTo(Status.PENDING_REVIEW);
        assertThat(partners.reviewVerification(reviewer, id, Decision.REJECT, "invalid", 2).verificationStatus())
                .isEqualTo(Status.REJECTED);
        assertApi(() -> partners.reviewVerification(reviewer, id, Decision.APPROVE, null, 3),
                HttpStatus.CONFLICT, "INVALID_VERIFICATION_TRANSITION");
        assertThat(partners.eligibleForCatalogGate(id)).isFalse();
    }

    @Test
    void databaseRejectsInvalidRowsAndKeepsAuditTablesAppendOnly() {
        UUID owner = user();
        UUID member = user();
        UUID id = partners.apply(owner, "Synthetic").id();
        rejected(() -> jdbc.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'ADMIN', ?)", id, member, owner));
        rejected(() -> jdbc.update("insert into marketplace.partner_staff (partner_id, user_id, role, status, granted_by_user_id) values (?, ?, 'OPERATOR', 'REVOKED', ?)", id, member, owner));
        rejected(() -> jdbc.update("update marketplace.partners set verification_status = 'LIVE' where id = ?", id));
        rejected(() -> jdbc.update("insert into marketplace.partners (display_name, created_by_user_id) values ('  ', ?)", owner));
        rejected(() -> jdbc.update("insert into marketplace.partner_verification_events (partner_id, decision, from_status, to_status, actor_user_id) values (?, 'REJECT', 'PENDING_REVIEW', 'REJECTED', ?)", id, owner));
        rejected(() -> jdbc.update("update marketplace.partner_verification_events set reason = 'tamper' where partner_id = ?", id));
        rejected(() -> jdbc.update("delete from marketplace.partner_verification_events where partner_id = ?", id));
        rejected(() -> jdbc.update("update marketplace.partner_staff_events set role = 'MANAGER' where partner_id = ?", id));
        rejected(() -> jdbc.update("delete from marketplace.partner_staff_events where partner_id = ?", id));
        rejected(() -> jdbc.update("delete from marketplace.partners where id = ?", id));
        // Valid control: the same staff shape with an allowed role is accepted.
        jdbc.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'OPERATOR', ?)", id, member, owner);
    }

    private int events(UUID partnerId) {
        return jdbc.queryForObject("select count(*) from marketplace.partner_staff_events where partner_id = ?",
                Integer.class, partnerId);
    }

    /** A rejected statement aborts the transaction in PostgreSQL, so isolate it with a savepoint. */
    private void rejected(Runnable statement) {
        jdbc.execute("savepoint s");
        assertThatThrownBy(statement::run).isInstanceOf(org.springframework.dao.DataAccessException.class);
        jdbc.execute("rollback to savepoint s");
    }
}
