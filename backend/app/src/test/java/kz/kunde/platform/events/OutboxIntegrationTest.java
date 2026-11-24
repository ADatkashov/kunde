package kz.kunde.platform.events;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.IllegalTransactionStateException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** ADR-022 against PostgreSQL: atomic publication, ordering, retry/backoff, dead letter, inbox idempotency, multi-relay safety. */
@SpringBootTest
class OutboxIntegrationTest {
    private static final String TYPE = "kunde.outbox_test.happened";

    @Autowired JdbcTemplate db;
    @Autowired OutboxWriter writer;
    @Autowired PlatformTransactionManager transactions;

    private final List<UUID> aggregates = new ArrayList<>();

    @AfterEach
    void cleanup() {
        for (UUID aggregate : aggregates) {
            db.update("delete from platform.inbox_events where event_id in (select event_id from platform.outbox_events where aggregate_id = ?)", aggregate);
            db.update("delete from platform.outbox_events where aggregate_id = ?", aggregate);
        }
    }

    private UUID aggregate() {
        UUID id = UUID.randomUUID();
        aggregates.add(id);
        return id;
    }

    private UUID publish(UUID aggregate, int version, Object payload) {
        return new TransactionTemplate(transactions).execute(s -> writer.append(
                new DomainEvent(TYPE, version, "test", "OutboxTest", aggregate, null, null, null, null, payload)));
    }

    private OutboxRelay relay(int maxAttempts, EventConsumer... consumers) {
        return new OutboxRelay(db, transactions, List.of(consumers), new SimpleMeterRegistry(), maxAttempts);
    }

    private static final class Recording implements EventConsumer {
        final String name;
        final int max;
        final List<UUID> handled = Collections.synchronizedList(new ArrayList<>());
        volatile RuntimeException failure;

        Recording(String name, int max) { this.name = name; this.max = max; }

        public String name() { return name; }
        public boolean handles(String type) { return TYPE.equals(type); }
        public int maxSchemaVersion() { return max; }
        public void handle(StoredEvent event) {
            if (failure != null) { throw failure; }
            handled.add(event.eventId());
        }
    }

    private String status(UUID eventId) {
        return db.queryForObject("select status from platform.outbox_events where event_id = ?", String.class, eventId);
    }

    @Test
    void appendRequiresTheBusinessTransaction() {
        assertThatThrownBy(() -> writer.append(DomainEvent.of(TYPE, 1, "test", "OutboxTest", aggregate(), Map.of("a", 1))))
                .isInstanceOf(IllegalTransactionStateException.class);
    }

    @Test
    void aRolledBackBusinessTransactionPublishesNothing() {
        UUID aggregate = aggregate();
        new TransactionTemplate(transactions).executeWithoutResult(status -> {
            writer.append(DomainEvent.of(TYPE, 1, "test", "OutboxTest", aggregate, Map.of("a", 1)));
            status.setRollbackOnly();
        });
        assertThat(db.queryForObject("select count(*) from platform.outbox_events where aggregate_id = ?", Integer.class, aggregate)).isZero();
    }

    @Test
    void rejectsMalformedEvents() {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        assertThatThrownBy(() -> tx.executeWithoutResult(s -> writer.append(DomainEvent.of("OrderCreated", 1, "t", "A", aggregate(), "x"))))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> tx.executeWithoutResult(s -> writer.append(DomainEvent.of(TYPE, 0, "t", "A", aggregate(), "x"))))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void deliversInOrderPerAggregateAndMarksDelivered() {
        UUID a = aggregate();
        UUID first = publish(a, 1, Map.of("n", 1));
        UUID second = publish(a, 1, Map.of("n", 2));
        Recording consumer = new Recording("c1", 1);

        assertThat(relay(3, consumer).deliverBatch(10)).isEqualTo(2);

        assertThat(consumer.handled).containsExactly(first, second);
        assertThat(status(first)).isEqualTo("DELIVERED");
        assertThat(status(second)).isEqualTo("DELIVERED");
        assertThat(relay(3, consumer).deliverBatch(10)).isZero();
    }

    @Test
    void failureBacksOffAndBlocksLaterEventsOfTheSameAggregateOnly() {
        UUID a = aggregate();
        UUID other = aggregate();
        UUID first = publish(a, 1, Map.of("n", 1));
        UUID behind = publish(a, 1, Map.of("n", 2));
        UUID unrelated = publish(other, 1, Map.of("n", 1));
        Recording consumer = new Recording("c2", 1);
        consumer.failure = new IllegalStateException("downstream down");

        // first fails once and is delayed; its successor must not overtake it; another aggregate is unaffected
        consumer.failure = new IllegalStateException("down") { };
        relayHandlingOnly(a, consumer);
        assertThat(db.queryForObject("select attempts from platform.outbox_events where event_id = ?", Integer.class, first)).isEqualTo(1);
        assertThat(db.queryForObject("select next_attempt_at > now() from platform.outbox_events where event_id = ?", Boolean.class, first)).isTrue();
        assertThat(status(first)).isEqualTo("PENDING");

        consumer.failure = null;
        relay(3, consumer).deliverBatch(10);
        assertThat(consumer.handled).as("only the unrelated aggregate moved").contains(unrelated).doesNotContain(first, behind);
    }

    /** Runs the relay once restricted to one aggregate by delivering everything else first (other rows are not yet due or not present). */
    private void relayHandlingOnly(UUID aggregate, Recording consumer) {
        db.update("update platform.outbox_events set next_attempt_at = now() + interval '1 hour' where aggregate_id <> ? and status = 'PENDING' and aggregate_type = 'OutboxTest' and aggregate_id = any(?::uuid[])",
                aggregate, aggregates.stream().filter(x -> !x.equals(aggregate)).map(UUID::toString).toArray(String[]::new));
        relay(3, consumer).deliverBatch(10);
        db.update("update platform.outbox_events set next_attempt_at = now() where aggregate_type = 'OutboxTest' and aggregate_id <> ? and status = 'PENDING'", aggregate);
    }

    @Test
    void exhaustedRetriesDeadLetterTheEventAndKeepItsAggregateBlocked() {
        UUID a = aggregate();
        UUID first = publish(a, 1, Map.of("n", 1));
        UUID behind = publish(a, 1, Map.of("n", 2));
        Recording consumer = new Recording("c3", 1);
        consumer.failure = new IllegalStateException("always");
        OutboxRelay relay = relay(2, consumer);

        relay.deliverBatch(5);
        db.update("update platform.outbox_events set next_attempt_at = now() where event_id = ?", first);
        relay.deliverBatch(5);

        assertThat(status(first)).isEqualTo("DEAD");
        assertThat(db.queryForObject("select last_error from platform.outbox_events where event_id = ?", String.class, first))
                .as("only the exception class is stored, never its message or the payload").doesNotContain("always");
        consumer.failure = null;
        assertThat(relay(2, consumer).deliverBatch(5)).isZero();
        assertThat(status(behind)).isEqualTo("PENDING");
    }

    @Test
    void aSchemaVersionTheConsumerDoesNotKnowIsPermanentNotRetried() {
        UUID a = aggregate();
        UUID event = publish(a, 3, Map.of("n", 1));
        Recording consumer = new Recording("c4", 2);

        relay(5, consumer).deliverBatch(5);

        assertThat(status(event)).isEqualTo("DEAD");
        assertThat(consumer.handled).isEmpty();
    }

    @Test
    void aConsumerThatAlreadySucceededIsNotRunAgainWhenAnotherOneFailsAndTheEventIsRetried() {
        UUID a = aggregate();
        UUID event = publish(a, 1, Map.of("n", 1));
        Recording good = new Recording("c5-good", 1);
        Recording flaky = new Recording("c5-flaky", 1);
        flaky.failure = new IllegalStateException("x");
        OutboxRelay relay = relay(5, good, flaky);

        relay.deliverBatch(5);
        assertThat(status(event)).isEqualTo("PENDING");
        assertThat(good.handled).containsExactly(event);

        flaky.failure = null;
        db.update("update platform.outbox_events set next_attempt_at = now() where event_id = ?", event);
        relay.deliverBatch(5);

        assertThat(status(event)).isEqualTo("DELIVERED");
        assertThat(good.handled).as("inbox makes the retry idempotent per consumer").containsExactly(event);
        assertThat(flaky.handled).containsExactly(event);
    }

    @Test
    void manyRelaysRaceAndEveryEventIsHandledExactlyOnce() throws Exception {
        List<UUID> events = new ArrayList<>();
        for (int i = 0; i < 40; i++) {
            events.add(publish(aggregate(), 1, Map.of("n", i)));
        }
        Recording consumer = new Recording("c6", 1);
        ExecutorService pool = Executors.newFixedThreadPool(4);
        CountDownLatch go = new CountDownLatch(1);
        List<Future<Integer>> work = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            work.add(pool.submit(() -> {
                go.await();
                return relay(3, consumer).deliverBatch(100);
            }));
        }
        go.countDown();
        int total = 0;
        for (Future<Integer> f : work) { total += f.get(60, TimeUnit.SECONDS); }
        pool.shutdown();

        assertThat(total).isEqualTo(40);
        assertThat(consumer.handled).containsExactlyInAnyOrderElementsOf(events).doesNotHaveDuplicates();
    }
}
