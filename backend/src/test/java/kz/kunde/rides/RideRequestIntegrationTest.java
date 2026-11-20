package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.rides.enabled=true",
        "app.rides.consumer-enabled=true"
})
class RideRequestIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired RideRequestService rides;
    @Autowired PlatformTransactionManager transactions;

    @Test
    void concurrentRetriesCreateExactlyOneRideAndCancellationIsAuditedOnce() throws Exception {
        UUID customer = user();
        UUID quote = quote(customer, false);
        String key = "concurrent-key-0001";
        RideRequestService.Requested first;
        RideRequestService.Requested second;
        try (var workers = Executors.newFixedThreadPool(2)) {
            var one = workers.submit(() -> rides.create(customer, quote, key));
            var two = workers.submit(() -> rides.create(customer, quote, key));
            first = one.get(10, TimeUnit.SECONDS);
            second = two.get(10, TimeUnit.SECONDS);
        }
        assertThat(first.ride()).isEqualTo(second.ride());
        assertThat(first.created()).isNotEqualTo(second.created());
        UUID ride = first.ride().id();

        assertThatExceptionOfType(ApiException.class).isThrownBy(() -> rides.cancel(user(), ride))
                .satisfies(error -> assertThat(error.code()).isEqualTo("RIDE_NOT_FOUND"));
        assertThatExceptionOfType(ApiException.class).isThrownBy(() -> rides.create(customer, quote(customer, false), key))
                .satisfies(error -> assertThat(error.code()).isEqualTo("IDEMPOTENCY_KEY_REUSED"));

        assertThat(rides.cancel(customer, ride).status()).isEqualTo(RideState.CANCELLED_BY_CUSTOMER);
        assertThat(rides.cancel(customer, ride).status()).isEqualTo(RideState.CANCELLED_BY_CUSTOMER);
        assertThat(rides.list(customer, 30, 0)).hasSize(1);
        assertThat(db.queryForList("select status from transactions.ride_events where ride_id = ? order by id",
                String.class, ride)).containsExactly("REQUESTED", "CANCELLED_BY_CUSTOMER");
    }

    @Test
    void rejectsExpiredAndForeignQuotes() {
        UUID customer = user();
        for (UUID quote : new UUID[] { quote(customer, true), quote(user(), false) }) {
            assertThatExceptionOfType(ApiException.class).isThrownBy(() -> rides.create(customer, quote, "invalid-quote-0001"))
                    .satisfies(error -> assertThat(error.code()).isEqualTo("RIDE_QUOTE_UNAVAILABLE"));
        }
        assertThat(rides.list(customer, 30, 0)).isEmpty();
    }

    @Test
    void rejectsAQuoteThatExpiredAfterTheTransactionStarted() {
        UUID customer = user();
        assertThatExceptionOfType(ApiException.class).isThrownBy(() ->
                new TransactionTemplate(transactions).executeWithoutResult(status -> {
                    UUID quote = db.queryForObject("""
                            insert into transactions.ride_fare_quotes (user_id, ride_class, tariff_version, estimate_kzt,
                                distance_meters, duration_seconds, pickup_latitude, pickup_longitude,
                                destination_latitude, destination_longitude, expires_at)
                            values (?, 'ECONOMY', 'test', 800.00, 3000, 360, 43.24, 76.92, 43.25, 76.94,
                                now() + interval '20 milliseconds') returning id
                            """, UUID.class, customer);
                    db.execute("select pg_sleep(0.05)");
                    rides.create(customer, quote, "expired-in-tx-0001");
                })).satisfies(error -> assertThat(error.code()).isEqualTo("RIDE_QUOTE_UNAVAILABLE"));
    }

    @Test
    void disablingCreationPreservesRetryAndCancellation() {
        UUID customer = user();
        UUID quote = quote(customer, false);
        String key = "rides-off-test-01";
        UUID ride = rides.create(customer, quote, key).ride().id();

        var disabled = new RideRequestService(db, kz.kunde.platform.TestToggles.of(new RidesFlags(false, false, false, false, false, false)));
        new TransactionTemplate(transactions).executeWithoutResult(status -> {
            assertThat(disabled.create(customer, quote, key).ride().id()).isEqualTo(ride);
            assertThat(disabled.cancel(customer, ride).status()).isEqualTo(RideState.CANCELLED_BY_CUSTOMER);
            assertThatExceptionOfType(ApiException.class)
                    .isThrownBy(() -> disabled.create(customer, quote(customer, false), "rides-off-test-02"))
                    .satisfies(error -> assertThat(error.code()).isEqualTo("RIDES_UNAVAILABLE"));
        });
        assertThat(rides.list(customer, 30, 0)).hasSize(1);
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID quote(UUID customer, boolean expired) {
        return db.queryForObject("""
                insert into transactions.ride_fare_quotes (user_id, ride_class, tariff_version, estimate_kzt,
                    distance_meters, duration_seconds, pickup_latitude, pickup_longitude,
                    destination_latitude, destination_longitude, created_at, expires_at)
                values (?, 'ECONOMY', 'test', 800.00, 3000, 360, 43.24, 76.92, 43.25, 76.94,
                    now() - interval '2 minutes', now() + (? * interval '1 minute')) returning id
                """, UUID.class, customer, expired ? -1 : 1);
    }
}
