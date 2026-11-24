package kz.kunde.leisure;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Real concurrency (no wrapping test transaction, so every call commits on its own): many customers race for the last places and the same seat;
 * exactly the available number win, nobody is oversold, and a repeated payment request with the same key creates one order.
 */
@SpringBootTest(properties = {"app.environment=test", "app.identity.consumer-enabled=true"})
class LeisureConcurrencyIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired LeisureOrderService orders;

    private final List<UUID> users = new ArrayList<>();
    private UUID partner;
    private UUID venue;
    private UUID event;

    private UUID newUser() {
        UUID u = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        users.add(u);
        return u;
    }

    private UUID[] fixture(String type, String pricing, int capacity) {
        UUID owner = newUser();
        partner = db.queryForObject("insert into marketplace.partners (display_name, verification_status, created_by_user_id) values ('Concurrency test (синтетика)', 'APPROVED', ?) returning id", UUID.class, owner);
        venue = db.queryForObject("insert into marketplace.leisure_venues (partner_id, name, status, is_synthetic) values (?, 'Concurrency venue', 'APPROVED', true) returning id", UUID.class, partner);
        event = db.queryForObject("insert into marketplace.leisure_events (venue_id, category_code, booking_type, title, status, is_synthetic, max_guests) values (?, 'OTHER', ?, 'Concurrency event', 'PUBLISHED', true, 10) returning id",
                UUID.class, venue, type);
        UUID tt = db.queryForObject("insert into marketplace.leisure_ticket_types (event_id, name, price_minor, pricing) values (?, 'T', 100000, ?) returning id", UUID.class, event, pricing);
        UUID session = db.queryForObject("insert into marketplace.leisure_sessions (event_id, starts_at, ends_at, capacity) values (?, ?, ?, ?) returning id", UUID.class, event,
                OffsetDateTime.now().plusDays(2), OffsetDateTime.now().plusDays(2).plusHours(1), capacity);
        return new UUID[] {session, tt};
    }

    @AfterEach
    void cleanup() {
        if (event == null) { return; }
        // the order and payment journals are append-only by design (trigger); only this test's own fixture rows are removed, with the triggers off
        db.execute("alter table transactions.leisure_order_events disable trigger leisure_order_events_immutable");
        db.execute("alter table transactions.leisure_payment_events disable trigger leisure_payment_events_immutable");
        try {
            deleteFixture();
        } finally {
            db.execute("alter table transactions.leisure_order_events enable trigger leisure_order_events_immutable");
            db.execute("alter table transactions.leisure_payment_events enable trigger leisure_payment_events_immutable");
        }
        users.clear();
        event = null;
    }

    private void deleteFixture() {
        db.update("delete from transactions.leisure_payment_events where payment_id in (select p.id from transactions.leisure_payments p join transactions.leisure_orders o on o.id = p.order_id where o.event_id = ?)", event);
        db.update("delete from transactions.leisure_payments where order_id in (select id from transactions.leisure_orders where event_id = ?)", event);
        db.update("delete from transactions.leisure_order_events where order_id in (select id from transactions.leisure_orders where event_id = ?)", event);
        db.update("delete from transactions.leisure_tickets where order_id in (select id from transactions.leisure_orders where event_id = ?)", event);
        db.update("delete from transactions.leisure_orders where event_id = ?", event);
        db.update("delete from transactions.leisure_hold_lines where hold_id in (select id from transactions.leisure_holds where session_id in (select id from marketplace.leisure_sessions where event_id = ?))", event);
        db.update("delete from transactions.leisure_holds where session_id in (select id from marketplace.leisure_sessions where event_id = ?)", event);
        db.update("delete from marketplace.leisure_seats where session_id in (select id from marketplace.leisure_sessions where event_id = ?)", event);
        db.update("delete from marketplace.leisure_sessions where event_id = ?", event);
        db.update("delete from marketplace.leisure_ticket_types where event_id = ?", event);
        db.update("delete from marketplace.leisure_events where id = ?", event);
        db.update("delete from marketplace.leisure_venues where id = ?", venue);
        db.update("delete from marketplace.partners where id = ?", partner);
        for (UUID u : users) { db.update("delete from identity.users where id = ?", u); }
    }

    private <T> List<Object> race(int threads, List<Callable<T>> work) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<Object>> futures = new ArrayList<>();
        for (Callable<T> c : work) {
            futures.add(pool.submit(() -> {
                start.await();
                try { return c.call(); } catch (ApiException e) { return e.code(); }
            }));
        }
        start.countDown();
        List<Object> out = new ArrayList<>();
        for (Future<Object> f : futures) { out.add(f.get()); }
        pool.shutdown();
        return out;
    }

    @Test
    void capacityIsNeverOversold() throws Exception {
        UUID[] f = fixture("CAPACITY", "PER_TICKET", 3);
        List<Callable<Object>> work = new ArrayList<>();
        for (int i = 0; i < 12; i++) {
            UUID user = newUser();
            work.add(() -> orders.hold(user, f[0], new LeisureOrderService.HoldRequest(1, List.of(new LeisureOrderService.Line(f[1], 1, null)))));
        }
        List<Object> results = race(12, work);
        assertThat(results.stream().filter(r -> r instanceof LeisureOrderService.HoldView)).hasSize(3);
        assertThat(results.stream().filter("NOT_ENOUGH_PLACES"::equals)).hasSize(9);
        assertThat(db.queryForObject("select count(*) from transactions.leisure_holds where session_id = ? and status = 'ACTIVE'", Integer.class, f[0])).isEqualTo(3);
    }

    @Test
    void oneSeatCanBeHeldOnlyOnce() throws Exception {
        UUID[] f = fixture("SEAT_MAP", "PER_TICKET", 5);
        UUID seat = db.queryForObject("insert into marketplace.leisure_seats (session_id, row_label, seat_number) values (?, 'A', 1) returning id", UUID.class, f[0]);
        List<Callable<Object>> work = new ArrayList<>();
        for (int i = 0; i < 8; i++) {
            UUID user = newUser();
            work.add(() -> orders.hold(user, f[0], new LeisureOrderService.HoldRequest(1, List.of(new LeisureOrderService.Line(f[1], 1, List.of(seat))))));
        }
        List<Object> results = race(8, work);
        assertThat(results.stream().filter(r -> r instanceof LeisureOrderService.HoldView)).hasSize(1);
        assertThat(results.stream().filter("SEAT_TAKEN"::equals)).hasSize(7);
    }

    @Test
    void repeatedPaymentWithTheSameKeyCreatesOneOrder() throws Exception {
        UUID[] f = fixture("CAPACITY", "PER_TICKET", 5);
        UUID user = newUser();
        var hold = orders.hold(user, f[0], new LeisureOrderService.HoldRequest(1, List.of(new LeisureOrderService.Line(f[1], 2, null))));
        List<Callable<Object>> work = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            work.add(() -> orders.place(user, "same-key-for-all-0001", new LeisureOrderService.PlaceBody(UUID.fromString(hold.id()), "TEST_CARD", true)));
        }
        List<Object> results = race(6, work);
        assertThat(results).allMatch(r -> r instanceof LeisureOrderService.Placed);
        assertThat(results.stream().map(r -> ((LeisureOrderService.Placed) r).order().id()).distinct()).hasSize(1);
        assertThat(results.stream().filter(r -> ((LeisureOrderService.Placed) r).created())).hasSize(1);
        assertThat(db.queryForObject("select count(*) from transactions.leisure_orders where event_id = ?", Integer.class, event)).isEqualTo(1);
        assertThat(db.queryForObject("select count(*) from transactions.leisure_tickets where session_id = ?", Integer.class, f[0])).isEqualTo(2);
        assertThat(db.queryForObject("select count(*) from transactions.leisure_payment_events where kind = 'CAPTURE' and payment_id in (select id from transactions.leisure_payments where user_id = ?)", Integer.class, user)).isEqualTo(1);
    }
}
