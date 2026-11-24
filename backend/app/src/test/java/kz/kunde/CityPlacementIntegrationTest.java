package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import kz.kunde.platform.placement.PlacementService;
import kz.kunde.platform.placement.ShardKey;
import kz.kunde.platform.placement.ShardLocation;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Database sharding readiness (docs/architecture/database-sharding-readiness.md): the city placement key behaves as
 * documented against the real Flyway-migrated PostgreSQL schema. Synthetic data only; every test writes inside a
 * rolled-back transaction except the concurrency test, which cleans up after itself.
 */
@SpringBootTest
class CityPlacementIntegrationTest {
    @Autowired
    JdbcTemplate jdbc;
    @Autowired
    PlatformTransactionManager transactionManager;
    @Autowired
    PlacementService placement;

    private void rolledBack(Runnable body) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            body.run();
        });
    }

    private UUID city(String code, String shard) {
        return jdbc.queryForObject("insert into serviceability.cities (code, name, shard_id) values (?, ?, ?) returning id",
                UUID.class, code + "-" + UUID.randomUUID().toString().substring(0, 8), code, shard);
    }

    private UUID restaurant(UUID cityId) {
        return jdbc.queryForObject("""
                insert into marketplace.food_restaurants (slug, name, cuisine, city_id)
                values (?, 'Synthetic', 'Synthetic', ?) returning id""", UUID.class,
                "r-" + UUID.randomUUID(), cityId);
    }

    private UUID user() {
        return jdbc.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID foodOrder(UUID user, UUID restaurant) {
        return jdbc.queryForObject("""
                insert into transactions.food_orders (user_id, restaurant_id, restaurant_name, payment_method, payment_status,
                    subtotal_minor, delivery_fee_minor, total_minor, address_label, address_text, idempotency_key)
                values (?, ?, 'Synthetic', 'CASH_ON_DELIVERY', 'PAY_ON_RECEIPT', 100, 0, 100, 'home', 'Synthetic address', ?)
                returning id""", UUID.class, user, restaurant, UUID.randomUUID().toString());
    }

    @Test
    void migrationStartsWithNoCitiesAndNoInventedPlacement() {
        assertThat(jdbc.queryForObject("select count(*) from serviceability.cities", Long.class)).isZero();
        assertThat(jdbc.queryForObject("""
                select (select count(*) from marketplace.food_restaurants where city_id is not null)
                     + (select count(*) from transactions.rides where city_id is not null)
                     + (select count(*) from transactions.deliveries where city_id is not null)""", Long.class)).isZero();
    }

    @Test
    void ordersOfDifferentCitiesStayInTheirCityAndOneUserCanOrderInBoth() {
        rolledBack(() -> {
            UUID almaty = city("almaty", "default");
            UUID astana = city("astana", "default");
            UUID user = user();
            UUID orderA = foodOrder(user, restaurant(almaty));
            UUID orderB = foodOrder(user, restaurant(astana));

            assertThat(placement.locate("food.order", orderA).orElseThrow().key()).isEqualTo(ShardKey.city("food", almaty));
            assertThat(placement.locate("food.order", orderB).orElseThrow().key()).isEqualTo(ShardKey.city("food", astana));
            assertThat(placement.locate("food.order", orderA).orElseThrow().location()).isEqualTo(ShardLocation.DEFAULT);

            List<UUID> inAlmaty = jdbc.queryForList("""
                    select o.id from transactions.food_orders o join marketplace.food_restaurants r on r.id = o.restaurant_id
                    where o.user_id = ? and r.city_id = ?""", UUID.class, user, almaty);
            assertThat(inAlmaty).containsExactly(orderA);
        });
    }

    @Test
    void changingTheUsersAddressOrCityDoesNotMoveAnExistingOrder() {
        rolledBack(() -> {
            UUID almaty = city("almaty", "default");
            UUID astana = city("astana", "default");
            UUID user = user();
            UUID order = foodOrder(user, restaurant(almaty));
            UUID address = jdbc.queryForObject("""
                    insert into profile.consumer_addresses (user_id, label, formatted_address, latitude, longitude)
                    values (?, 'home', 'Almaty, synthetic', 43.238949, 76.889709) returning id""", UUID.class, user);
            // The user "moves" to Astana: the saved address is edited.
            jdbc.update("update profile.consumer_addresses set formatted_address = 'Astana, synthetic', latitude = 51.169392,"
                    + " longitude = 71.449074, version = version + 1 where id = ?", address);

            assertThat(placement.locate("food.order", order).orElseThrow().key().cityId()).isEqualTo(almaty);
            assertThat(placement.belongsToCity("food.order", order, astana)).as("claimed city is never trusted").isFalse();
        });
    }

    @Test
    void partnerBranchesInSeveralCitiesAreAddressedIndependently() {
        rolledBack(() -> {
            UUID almaty = city("almaty", "default");
            UUID astana = city("astana", "default");
            UUID owner = user();
            UUID partner = jdbc.queryForObject(
                    "insert into marketplace.partners (display_name, created_by_user_id) values ('Synthetic chain', ?) returning id",
                    UUID.class, owner);
            UUID branchA = venue(partner, almaty);
            UUID branchB = venue(partner, astana);
            assertThat(placement.locate("booking.venue", branchA).orElseThrow().key().cityId()).isEqualTo(almaty);
            assertThat(placement.locate("booking.venue", branchB).orElseThrow().key().cityId()).isEqualTo(astana);
            assertThat(jdbc.queryForObject("select count(distinct city_id) from marketplace.booking_venues where partner_id = ?",
                    Long.class, partner)).isEqualTo(2L);
        });
    }

    private UUID venue(UUID partner, UUID cityId) {
        return jdbc.queryForObject("""
                insert into marketplace.booking_venues (slug, name, address_text, partner_id, city_id)
                values (?, 'Synthetic branch', 'Synthetic address', ?, ?) returning id""", UUID.class,
                "v-" + UUID.randomUUID(), partner, cityId);
    }

    @Test
    void unplacedRecordsAreReportedAsUnplacedNotGuessed() {
        rolledBack(() -> {
            UUID r = restaurant(null);
            var resolved = placement.locate("food.restaurant", r).orElseThrow();
            assertThat(resolved.key().scope()).isEqualTo(ShardKey.Scope.UNPLACED);
            assertThat(placement.belongsToCity("food.restaurant", r, UUID.randomUUID())).isFalse();
            assertThat(placement.locate("food.restaurant", UUID.randomUUID())).isEmpty();
        });
    }

    @Test
    void placementKeyIsImmutableOnceAssignedButCanBeAssignedOnce() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            UUID almaty = city("almaty", "default");
            UUID astana = city("astana", "default");
            UUID r = restaurant(null);
            jdbc.update("update marketplace.food_restaurants set city_id = ? where id = ?", almaty, r); // NULL -> city: allowed
            jdbc.update("update marketplace.food_restaurants set city_id = ?, name = 'Renamed' where id = ?", almaty, r); // same value
            rejectedInSavepoint(status, () -> jdbc.update("update marketplace.food_restaurants set city_id = ? where id = ?", astana, r));
            rejectedInSavepoint(status, () -> jdbc.update("update marketplace.food_restaurants set city_id = null where id = ?", r));
            assertThat(jdbc.queryForObject("select city_id from marketplace.food_restaurants where id = ?", UUID.class, r))
                    .isEqualTo(almaty);
        });
    }

    /** A failed statement aborts a PostgreSQL transaction; a savepoint keeps the rest of the test usable. */
    private static void rejectedInSavepoint(org.springframework.transaction.TransactionStatus status, Runnable statement) {
        Object savepoint = status.createSavepoint();
        assertThatThrownBy(statement::run).isInstanceOf(DataIntegrityViolationException.class);
        status.rollbackToSavepoint(savepoint);
    }

    @Test
    void educationFreeTextCityDoesNotChangeThePlacementKey() {
        rolledBack(() -> {
            UUID almaty = city("almaty", "default");
            UUID owner = user();
            UUID partner = jdbc.queryForObject(
                    "insert into marketplace.partners (display_name, created_by_user_id) values ('Synthetic school', ?) returning id",
                    UUID.class, owner);
            UUID course = UUID.randomUUID();
            jdbc.update("""
                    insert into marketplace.education_courses (id, partner_id, category, title, description, city, language, city_id)
                    values (?, ?, 'LANGUAGES', 'Synthetic', 'Synthetic', 'Алматы', 'ru', ?)""", course, partner, almaty);
            jdbc.update("update marketplace.education_courses set city = 'Астана' where id = ?", course);
            assertThat(placement.locate("education.course", course).orElseThrow().key().cityId()).isEqualTo(almaty);
        });
    }

    @Test
    void concurrentAssignmentOfTwoCitiesToOneRecordHasExactlyOneWinner() throws Exception {
        UUID almaty = city("almaty", "default");
        UUID astana = city("astana", "default");
        UUID r = restaurant(null);
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            CountDownLatch start = new CountDownLatch(1);
            List<Future<Boolean>> results = List.of(assign(pool, start, r, almaty), assign(pool, start, r, astana));
            start.countDown();
            int winners = 0;
            for (Future<Boolean> f : results) {
                winners += f.get() ? 1 : 0;
            }
            assertThat(winners).isEqualTo(1);
            UUID stored = jdbc.queryForObject("select city_id from marketplace.food_restaurants where id = ?", UUID.class, r);
            assertThat(stored).isIn(almaty, astana);
        } finally {
            pool.shutdownNow();
            jdbc.update("delete from marketplace.food_restaurants where id = ?", r);
            jdbc.update("delete from serviceability.cities where id in (?, ?)", almaty, astana);
        }
    }

    private Future<Boolean> assign(ExecutorService pool, CountDownLatch start, UUID restaurant, UUID cityId) {
        return pool.submit(() -> {
            start.await();
            try {
                new TransactionTemplate(transactionManager).executeWithoutResult(
                        s -> jdbc.update("update marketplace.food_restaurants set city_id = ? where id = ?", cityId, restaurant));
                return true;
            } catch (DataIntegrityViolationException expected) {
                return false;
            }
        });
    }

    @Test
    void cityRegistryRejectsMalformedCodesAndShards() {
        assertRejected(() -> jdbc.update("insert into serviceability.cities (code, name) values ('Bad Code', 'x')"));
        assertRejected(() -> jdbc.update("insert into serviceability.cities (code, name, shard_id) values ('ok-1', 'x', 'Bad Shard')"));
        assertRejected(() -> jdbc.update("insert into serviceability.cities (code, name, country_code) values ('ok-2', 'x', 'kz')"));
    }

    private void assertRejected(Runnable statement) {
        assertThatThrownBy(() -> rolledBackStatement(statement)).isInstanceOf(DataIntegrityViolationException.class);
    }

    /** A failed statement aborts the surrounding PostgreSQL transaction, so each rejected statement gets its own. */
    private void rolledBackStatement(Runnable statement) {
        new TransactionTemplate(transactionManager).executeWithoutResult(s -> {
            s.setRollbackOnly();
            statement.run();
        });
    }
}
