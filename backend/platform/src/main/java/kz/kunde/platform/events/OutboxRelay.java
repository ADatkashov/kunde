package kz.kunde.platform.events;

import io.micrometer.core.instrument.MeterRegistry;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Delivers outbox events to in-process {@link EventConsumer}s (ADR-022). Safe with any number of instances:
 * <ul>
 *   <li>one event is claimed with {@code FOR UPDATE SKIP LOCKED}; a second relay skips it instead of waiting;</li>
 *   <li>an event is not claimed while an earlier event of the same aggregate is still PENDING or DEAD, so per-aggregate order
 *       holds and a dead letter blocks its aggregate until an operator replays or resolves it;</li>
 *   <li>each consumer runs in a savepoint with its inbox record, so a consumer that succeeded is not run again when another
 *       consumer of the same event failed and the event is retried.</li>
 * </ul>
 * Failures back off exponentially with jitter; after {@code maxAttempts} the event is DEAD. Only the exception class name is stored.
 */
@Service
public class OutboxRelay {
    private static final Logger LOG = LoggerFactory.getLogger(OutboxRelay.class);
    private static final String CLAIM = """
            select e.seq, e.event_id, e.event_type, e.schema_version, e.producer, e.aggregate_type, e.aggregate_id,
                   e.aggregate_version, e.correlation_id, e.causation_id, e.city_id, e.payload::text, e.occurred_at, e.attempts
            from platform.outbox_events e
            where e.status = 'PENDING' and e.next_attempt_at <= statement_timestamp()
              and not exists (select 1 from platform.outbox_events p
                              where p.aggregate_type = e.aggregate_type and p.aggregate_id = e.aggregate_id
                                and p.seq < e.seq and p.status <> 'DELIVERED')
            order by e.seq limit 1 for update of e skip locked
            """;

    private final JdbcTemplate db;
    private final TransactionTemplate outer;
    private final TransactionTemplate nested;
    private final List<EventConsumer> consumers;
    private final MeterRegistry metrics;
    private final int maxAttempts;

    @Autowired
    public OutboxRelay(JdbcTemplate db, PlatformTransactionManager transactions, ObjectProvider<EventConsumer> consumers,
            MeterRegistry metrics, @Value("${app.outbox.max-attempts:8}") int maxAttempts) {
        this(db, transactions, consumers.orderedStream().toList(), metrics, maxAttempts);
    }

    public OutboxRelay(JdbcTemplate db, PlatformTransactionManager transactions, List<EventConsumer> consumers,
            MeterRegistry metrics, int maxAttempts) {
        if (maxAttempts < 1) {
            throw new IllegalArgumentException("app.outbox.max-attempts must be at least 1");
        }
        this.db = db;
        this.outer = new TransactionTemplate(transactions);
        this.nested = new TransactionTemplate(transactions);
        this.nested.setPropagationBehavior(TransactionDefinition.PROPAGATION_NESTED);
        this.consumers = List.copyOf(consumers);
        this.metrics = metrics;
        this.maxAttempts = maxAttempts;
    }

    /** Delivers up to {@code limit} due events; returns how many were claimed. */
    public int deliverBatch(int limit) {
        int done = 0;
        while (done < limit && Boolean.TRUE.equals(outer.execute(status -> deliverNext()))) {
            done++;
        }
        return done;
    }

    private boolean deliverNext() {
        var claimed = db.query(CLAIM, (rs, row) -> new Claimed(rs.getLong(1), new StoredEvent(rs.getObject(2, UUID.class),
                rs.getString(3), rs.getInt(4), rs.getString(5), rs.getString(6), rs.getObject(7, UUID.class),
                (Long) rs.getObject(8), rs.getString(9), rs.getObject(10, UUID.class), rs.getObject(11, UUID.class),
                rs.getString(12), rs.getObject(13, OffsetDateTime.class)), rs.getInt(14))).stream().findFirst();
        if (claimed.isEmpty()) {
            return false;
        }
        Claimed c = claimed.get();
        try {
            for (EventConsumer consumer : consumers) {
                if (consumer.handles(c.event().type())) {
                    nested.executeWithoutResult(status -> handle(consumer, c.event()));
                }
            }
            db.update("update platform.outbox_events set status = 'DELIVERED', delivered_at = statement_timestamp(), last_error = null where seq = ?", c.seq());
            metrics.counter("kunde.outbox.delivered").increment();
        } catch (EventConsumer.PermanentFailure failure) {
            dead(c, failure.getMessage());
        } catch (RuntimeException failure) {
            LOG.warn("Outbox event {} failed on attempt {}: {}", c.event().eventId(), c.attempts() + 1, failure.getClass().getSimpleName());
            retryOrDead(c, failure.getClass().getSimpleName());
        }
        return true;
    }

    private void handle(EventConsumer consumer, StoredEvent event) {
        if (db.update("insert into platform.inbox_events (consumer, event_id) values (?, ?) on conflict do nothing",
                consumer.name(), event.eventId()) == 0) {
            return; // already handled by this consumer
        }
        if (event.schemaVersion() > consumer.maxSchemaVersion()) {
            throw new EventConsumer.PermanentFailure("Consumer " + consumer.name() + " does not understand schema version " + event.schemaVersion());
        }
        consumer.handle(event);
    }

    private void retryOrDead(Claimed c, String error) {
        int attempts = c.attempts() + 1;
        if (attempts >= maxAttempts) {
            dead(c, error);
            return;
        }
        double seconds = Math.min(900, 5 * Math.pow(2, attempts - 1)) * (0.8 + 0.4 * ThreadLocalRandom.current().nextDouble());
        db.update("""
                update platform.outbox_events set attempts = ?, last_error = ?,
                    next_attempt_at = statement_timestamp() + make_interval(secs => ?) where seq = ?
                """, attempts, error, seconds, c.seq());
        metrics.counter("kunde.outbox.retried").increment();
    }

    private void dead(Claimed c, String error) {
        db.update("update platform.outbox_events set status = 'DEAD', attempts = attempts + 1, last_error = ? where seq = ?",
                error == null ? "PermanentFailure" : error.substring(0, Math.min(error.length(), 500)), c.seq());
        metrics.counter("kunde.outbox.dead").increment();
        LOG.error("Outbox event {} is dead-lettered; its aggregate is blocked until it is replayed or resolved", c.event().eventId());
    }

    private record Claimed(long seq, StoredEvent event, int attempts) {}
}
