package kz.kunde.rides;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest(properties = {
        "app.environment=test", "app.identity.consumer-enabled=true", "app.rides.enabled=true",
        "app.rides.consumer-enabled=true", "app.rides.executor-enabled=true", "app.rides.dispatch-enabled=true"
})
class RideDispatchConcurrencyIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired RideDispatchService dispatch;
    @Autowired RideRequestService requests;

    @Test
    void oneDriverCannotConcurrentlyAcceptTwoRides() throws Exception {
        UUID driver = user();
        UUID one = user();
        UUID two = user();
        db.update("""
                insert into transactions.ride_drivers (user_id, display_name, status, online, latitude, longitude, observed_at)
                values (?, 'Synthetic concurrency driver', 'APPROVED', true, 42.90, 77.20, statement_timestamp())
                """, driver);
        try {
            db.update("""
                    insert into transactions.ride_vehicles (driver_id, description, plate, ride_class, status)
                    values (?, 'Synthetic concurrency vehicle', ?, 'BUSINESS', 'APPROVED')
                    """, driver, UUID.randomUUID().toString().substring(0, 12));
            UUID firstRide = requested(one);
            UUID secondRide = requested(two);
            dispatch.search(one, firstRide);
            dispatch.search(two, secondRide);
            UUID firstOffer = offer(firstRide);
            UUID secondOffer = offer(secondRide);

            var ready = new CountDownLatch(1);
            try (var workers = Executors.newFixedThreadPool(2)) {
                var first = workers.submit(() -> acceptAfter(ready, driver, firstOffer));
                var second = workers.submit(() -> acceptAfter(ready, driver, secondOffer));
                ready.countDown();
                assertThat(java.util.List.of(first.get(10, TimeUnit.SECONDS), second.get(10, TimeUnit.SECONDS)))
                        .containsExactlyInAnyOrder("ACCEPTED", "RIDE_DRIVER_UNAVAILABLE");
            }
            assertThat(db.queryForObject("""
                    select count(*) from transactions.rides where driver_id = ? and status = 'DRIVER_ASSIGNED'
                    """, Long.class, driver)).isEqualTo(1L);
        } finally {
            db.update("""
                    update transactions.ride_drivers set online = false, latitude = null,
                        longitude = null, observed_at = null where user_id = ?
                    """, driver);
        }
    }

    private String acceptAfter(CountDownLatch ready, UUID driver, UUID offer) throws InterruptedException {
        if (!ready.await(5, TimeUnit.SECONDS)) {
            throw new AssertionError("Accept workers did not start");
        }
        try {
            dispatch.respond(driver, offer, true);
            return "ACCEPTED";
        } catch (ApiException error) {
            return error.code();
        }
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID requested(UUID user) {
        UUID quote = db.queryForObject("""
                insert into transactions.ride_fare_quotes (user_id, ride_class, tariff_version, estimate_kzt,
                    distance_meters, duration_seconds, pickup_latitude, pickup_longitude, destination_latitude,
                    destination_longitude, expires_at)
                values (?, 'BUSINESS', 'test', 800, 1000, 180, 42.90, 77.20, 42.91, 77.21,
                    now() + interval '1 minute') returning id
                """, UUID.class, user);
        return requests.create(user, quote, UUID.randomUUID().toString()).ride().id();
    }

    private UUID offer(UUID ride) {
        return db.queryForObject("select id from transactions.ride_offers where ride_id = ?", UUID.class, ride);
    }
}
