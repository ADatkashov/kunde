package kz.kunde.delivery;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import kz.kunde.delivery.DeliveryController.CreateRequest;
import kz.kunde.delivery.DeliveryController.ParcelType;
import kz.kunde.delivery.DeliveryController.QuoteRequest;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.geo.Coordinates;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.delivery.enabled=true",
        "app.delivery.consumer-enabled=true",
        "app.delivery.synthetic-routing-enabled=true",
        "app.delivery.executor-enabled=true",
        "app.delivery.dispatch-enabled=true",
        "DELIVERY_HANDOFF_KEY=synthetic-handoff-fixture-only-000000000"
})
class DeliveryConcurrencyIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired DeliveryService deliveries;
    @Autowired DeliveryDispatch dispatch;

    @Test
    void simultaneousRetriesShareOneOrderAndAuditEvent() throws Exception {
        UUID sender = user();
        var request = newRequest(sender);
        String key = UUID.randomUUID().toString();
        var gate = new CountDownLatch(1);
        try (var workers = Executors.newFixedThreadPool(2)) {
            var first = workers.submit(() -> {
                gate.await();
                return deliveries.create(sender, null, key, request);
            });
            var second = workers.submit(() -> {
                gate.await();
                return deliveries.create(sender, null, key, request);
            });
            gate.countDown();
            var left = first.get(5, TimeUnit.SECONDS);
            var right = second.get(5, TimeUnit.SECONDS);
            assertThat(left.order().id()).isEqualTo(right.order().id());
            assertThat(left.created()).isNotEqualTo(right.created());
            assertThat(db.queryForObject("select count(*) from transactions.delivery_events where delivery_id = ?",
                    Integer.class, left.order().id())).isEqualTo(1);
        }
    }

    @Test
    void oneCourierCannotAcceptConflictingAssignmentsConcurrently() throws Exception {
        UUID courier = readyCourier(43.240);
        UUID left = offer(courier);
        UUID right = offer(courier);
        var gate = new CountDownLatch(1);
        try (var workers = Executors.newFixedThreadPool(2)) {
            var a = workers.submit(() -> {
                gate.await();
                return accept(courier, left);
            });
            var b = workers.submit(() -> {
                gate.await();
                return accept(courier, right);
            });
            gate.countDown();
            assertThat(a.get(5, TimeUnit.SECONDS)).isNotEqualTo(b.get(5, TimeUnit.SECONDS));
            assertThat(db.queryForObject("""
                    select count(*) from transactions.deliveries where courier_id = ? and status = 'COURIER_ASSIGNED'
                    """, Integer.class, courier)).isEqualTo(1);
        }
    }

    @Test
    @Transactional
    void refusalRematchesAndExpiredSearchDoesNotAssign() {
        UUID near = readyCourier(43.240);
        UUID far = readyCourier(43.250);
        UUID sender = user();
        UUID delivery = deliveries.create(sender, null, UUID.randomUUID().toString(), newRequest(sender)).order().id();
        dispatch.search(sender, null, delivery);
        UUID first = dispatch.offers(near).getFirst().id();
        assertThat(dispatch.offers(far)).isEmpty();
        dispatch.respond(near, first, false);
        UUID second = dispatch.offers(far).getFirst().id();

        db.update("update transactions.delivery_offers set expires_at = statement_timestamp() - interval '1 second' where id = ?",
                second);
        db.update("update transactions.deliveries set search_started_at = statement_timestamp() - interval '3 minutes' where id = ?",
                delivery);
        dispatch.search(sender, null, delivery);
        assertThat(dispatch.offers(far)).isEmpty();
        assertThat(deliveries.get(sender, null, delivery).status()).isEqualTo(DeliveryState.NO_COURIER_AVAILABLE);
    }

    @Test
    @Transactional
    void failedDeliveryCanReturnAndReleasesTheCourierSlot() {
        UUID courier = readyCourier(43.240);
        UUID sender = user();
        UUID operator = user();
        UUID delivery = deliveries.create(sender, null, UUID.randomUUID().toString(), newRequest(sender)).order().id();
        db.update("update transactions.deliveries set courier_id = ?, status = 'IN_TRANSIT' where id = ?",
                courier, delivery);
        assertThat(dispatch.progress(courier, delivery, DeliveryState.Action.FAIL_DELIVERY))
                .isEqualTo(DeliveryState.DELIVERY_FAILED);
        assertThat(dispatch.requestReturn(operator, delivery)).isEqualTo(DeliveryState.RETURN_REQUESTED);
        assertThat(dispatch.progress(courier, delivery, DeliveryState.Action.START_RETURN))
                .isEqualTo(DeliveryState.RETURNING);
        assertThat(dispatch.progress(courier, delivery, DeliveryState.Action.CONFIRM_RETURN))
                .isEqualTo(DeliveryState.RETURNED_TO_SENDER);
        assertThat(db.queryForList("""
                select status::text from transactions.delivery_events where delivery_id = ? order by id
                """, String.class, delivery))
                .containsExactly("CREATED", "DELIVERY_FAILED", "RETURN_REQUESTED", "RETURNING", "RETURNED_TO_SENDER");
    }

    private UUID readyCourier(double latitude) {
        UUID id = user();
        db.update("""
                insert into transactions.delivery_couriers
                   (user_id, display_name, vehicle, status, online, max_grams, max_side_cm, latitude, longitude, observed_at)
                values (?, 'Synthetic Courier', 'BICYCLE', 'APPROVED', true, 3000, 40, ?, 76.92, statement_timestamp())
                """, id, latitude);
        return id;
    }

    private boolean accept(UUID courier, UUID offer) {
        try {
            dispatch.respond(courier, offer, true);
            return true;
        } catch (ApiException conflict) {
            assertThat(conflict.code()).isEqualTo("DELIVERY_COURIER_UNAVAILABLE");
            return false;
        }
    }

    private UUID offer(UUID courier) {
        UUID sender = user();
        UUID id = deliveries.create(sender, null, UUID.randomUUID().toString(), newRequest(sender)).order().id();
        return db.queryForObject("""
                with searching as (
                    update transactions.deliveries set status = 'SEARCHING_COURIER',
                        search_started_at = statement_timestamp() where id = ? returning id
                )
                insert into transactions.delivery_offers (delivery_id, courier_id, expires_at)
                select id, ?, statement_timestamp() + interval '25 seconds' from searching returning id
                """, UUID.class, id, courier);
    }

    private CreateRequest newRequest(UUID sender) {
        var quote = deliveries.quote(sender, null, new QuoteRequest(ParcelType.DOCUMENTS, 500, 30, 20, 2,
                new Coordinates(new BigDecimal("43.24"), new BigDecimal("76.92")),
                new Coordinates(new BigDecimal("43.25"), new BigDecimal("76.94"))));
        return new CreateRequest(quote.id(), "[TEST] Pickup", "[TEST] Destination", "Test Recipient",
                "+77000000000", "Documents", null, true);
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }
}
