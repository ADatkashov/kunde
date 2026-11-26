package kz.kunde.homeservices;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import kz.kunde.homeservices.HomeServiceOffers.Action;
import kz.kunde.homeservices.HomeServiceOffers.Actor;
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
 * Concurrent writers of one offer, with committed fixtures and real threads. A transition takes the offer row FOR UPDATE and
 * re-checks the version under that lock, so a second writer waits instead of overwriting; the partner capability check takes
 * shared locks, so a suspension of the partner waits for a writer that already relied on the partner being approved.
 * The writers roll back on purpose: the audit table is append-only and committed events would stay behind for other suites.
 */
@SpringBootTest
class HomeServicesOffersConcurrencyIntegrationTest {
    @Autowired HomeServiceOffers offers;
    @Autowired PartnerDirectory directory;
    @Autowired JdbcTemplate jdbc;
    @Autowired PlatformTransactionManager transactions;

    private final ExecutorService pool = Executors.newFixedThreadPool(2);
    private UUID owner;
    private UUID operator;
    private UUID partner;
    private UUID venue;
    private UUID service;
    private UUID offer;

    private UUID user() {
        return jdbc.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    @BeforeEach
    void fixtures() {
        owner = user();
        operator = user();
        partner = jdbc.queryForObject("""
                insert into marketplace.partners (display_name, verification_status, created_by_user_id)
                values ('Synthetic Offers Partner', 'APPROVED', ?) returning id
                """, UUID.class, owner);
        jdbc.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'OWNER', ?)", partner, owner, owner);
        jdbc.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'OPERATOR', ?)", partner, operator, owner);
        venue = jdbc.queryForObject("""
                insert into marketplace.booking_venues (slug, category, name, address_text, partner_id)
                values (?, 'CLEANING', 'Synthetic Offers Venue', 'Synthetic address', ?) returning id
                """, UUID.class, "synthetic-offers-" + UUID.randomUUID(), partner);
        service = jdbc.queryForObject("""
                insert into marketplace.booking_services (venue_id, name, duration_minutes, price_minor)
                values (?, 'Synthetic cleaning', 60, 1000000) returning id
                """, UUID.class, venue);
        // Inserted directly: creating through the service would append an audit event that can never be deleted.
        offer = jdbc.queryForObject("""
                insert into marketplace.home_service_offers (service_id, definition_code, pricing_model)
                values (?, (select code from marketplace.home_service_definitions where active order by code limit 1), 'FIXED')
                returning id
                """, UUID.class, service);
    }

    @AfterEach
    void cleanup() {
        pool.shutdownNow();
        jdbc.update("delete from marketplace.home_service_offers where id = ?", offer);
        jdbc.update("delete from marketplace.booking_services where id = ?", service);
        jdbc.update("delete from marketplace.booking_venues where id = ?", venue);
        jdbc.update("delete from marketplace.partner_staff where partner_id = ?", partner);
        jdbc.update("delete from marketplace.partners where id = ?", partner);
        jdbc.update("delete from identity.users where id in (?, ?)", owner, operator);
    }

    private <T> Future<T> inRolledBackTransaction(CountDownLatch entered, CountDownLatch release, java.util.function.Supplier<T> work) {
        return pool.submit(() -> new TransactionTemplate(transactions).execute(status -> {
            T result = work.get();
            entered.countDown();
            try {
                assertThat(release.await(20, TimeUnit.SECONDS)).isTrue();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            status.setRollbackOnly();
            return result;
        }));
    }

    @Test
    void capabilityIsGrantedByPartnerRolesOnly() {
        assertThat(directory.isCatalogManager(owner, partner)).isTrue();
        assertThat(directory.isActiveStaffOfApprovedPartner(operator, partner)).isTrue();
        assertThat(directory.isCatalogManager(operator, partner)).isFalse();
        assertThat(directory.isCatalogManager(UUID.randomUUID(), partner)).isFalse();
        assertThat(directory.isCatalogManager(owner, UUID.randomUUID())).isFalse();
    }

    @Test
    void secondWriterOfTheSameOfferWaitsForTheFirstAndNeverOverwritesIt() throws Exception {
        CountDownLatch firstHolds = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        Future<String> first = inRolledBackTransaction(firstHolds, release,
                () -> offers.transition(owner, Actor.PARTNER, partner, offer, Action.SUBMIT, 1, null).status().name());
        assertThat(firstHolds.await(20, TimeUnit.SECONDS)).isTrue();

        CountDownLatch secondDone = new CountDownLatch(1);
        CountDownLatch secondRelease = new CountDownLatch(1);
        secondRelease.countDown();
        Future<String> second = inRolledBackTransaction(secondDone, secondRelease,
                () -> offers.transition(owner, Actor.PARTNER, partner, offer, Action.SUBMIT, 1, null).status().name());
        Thread.sleep(700);
        assertThat(second.isDone()).as("the second writer must wait for the row lock").isFalse();

        release.countDown();
        assertThat(first.get(20, TimeUnit.SECONDS)).isEqualTo("PENDING");
        // The first writer rolled back, so the second one sees version 1 again and may proceed; nothing stays committed.
        assertThat(second.get(20, TimeUnit.SECONDS)).isEqualTo("PENDING");
        assertThat(jdbc.queryForObject("select version from marketplace.home_service_offers where id = ?", Long.class, offer)).isEqualTo(1L);
    }
}
