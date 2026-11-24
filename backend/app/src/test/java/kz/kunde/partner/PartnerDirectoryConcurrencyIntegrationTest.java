package kz.kunde.partner;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import kz.kunde.platform.partner.PartnerDirectory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * ADR-021: the locking check of {@link PartnerDirectory} keeps the FOR SHARE semantics products had when they joined the
 * partner tables themselves. A suspension takes FOR UPDATE on the partner row, so it must wait for a write that already
 * relied on the partner being APPROVED, and any check after it must see the suspension. Committed data, real threads.
 */
@SpringBootTest
class PartnerDirectoryConcurrencyIntegrationTest {
    @Autowired PartnerDirectory directory;
    @Autowired JdbcTemplate jdbc;
    @Autowired PlatformTransactionManager transactions;

    private final ExecutorService pool = Executors.newFixedThreadPool(2);
    private UUID owner;
    private UUID partner;

    private UUID user() {
        return jdbc.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    @BeforeEach
    void approvedPartner() {
        // Direct fixture rows: the partner audit tables are append-only, so going through PartnerService would leave
        // committed events behind that other suites would see. The property under test is the row-lock conflict between the
        // directory's FOR SHARE and the FOR UPDATE / UPDATE that PartnerService.decide performs on the same partner row.
        owner = user();
        partner = jdbc.queryForObject("""
                insert into marketplace.partners (display_name, verification_status, created_by_user_id)
                values ('Synthetic Directory Partner', 'APPROVED', ?) returning id
                """, UUID.class, owner);
        jdbc.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'OWNER', ?)",
                partner, owner, owner);
    }

    @AfterEach
    void stop() {
        pool.shutdownNow();
        // Committed fixture data must not leak into suites that assume an empty partner registry.
        jdbc.update("delete from marketplace.partner_staff where partner_id = ?", partner);
        jdbc.update("delete from marketplace.partners where id = ?", partner);
        jdbc.update("delete from identity.users where id = ?", owner);
    }

    private boolean locked(UUID user) {
        Boolean result = new TransactionTemplate(transactions).execute(status -> directory.lockActiveStaffOfApprovedPartner(user, partner));
        return Boolean.TRUE.equals(result);
    }

    @Test
    void approvedActiveStaffIsAcceptedByEveryCheckAndStrangersAreNot() {
        UUID stranger = user();
        assertThat(directory.isActiveStaffOfApprovedPartner(owner, partner)).isTrue();
        assertThat(directory.approvedPartnersOfStaff(owner)).containsExactly(partner);
        assertThat(locked(owner)).isTrue();
        assertThat(directory.isActiveStaffOfApprovedPartner(stranger, partner)).isFalse();
        assertThat(directory.approvedPartnersOfStaff(stranger)).isEmpty();
        assertThat(locked(stranger)).isFalse();
    }

    @Test
    void suspensionWaitsForAWriterThatRelied_OnApprovalAndIsVisibleAfterwards() throws Exception {
        CountDownLatch locked = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        Future<Boolean> writer = pool.submit(() -> new TransactionTemplate(transactions).execute(status -> {
            boolean allowed = directory.lockActiveStaffOfApprovedPartner(owner, partner);
            locked.countDown();
            try {
                assertThat(release.await(20, TimeUnit.SECONDS)).isTrue();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            return allowed;
        }));
        assertThat(locked.await(20, TimeUnit.SECONDS)).isTrue();

        Future<Integer> suspension = pool.submit(() -> jdbc.update("""
                update marketplace.partners set verification_status = 'SUSPENDED', version = version + 1 where id = ?
                """, partner));
        Thread.sleep(700);
        assertThat(suspension.isDone()).as("suspension must wait for the writer holding the shared lock").isFalse();

        release.countDown();
        assertThat(writer.get(20, TimeUnit.SECONDS)).isTrue();
        assertThat(suspension.get(20, TimeUnit.SECONDS)).isEqualTo(1);

        assertThat(directory.isActiveStaffOfApprovedPartner(owner, partner)).isFalse();
        assertThat(directory.approvedPartnersOfStaff(owner)).isEmpty();
        assertThat(locked(owner)).isFalse();
    }
}
