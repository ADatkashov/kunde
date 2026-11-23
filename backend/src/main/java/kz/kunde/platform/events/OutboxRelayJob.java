package kz.kunde.platform.events;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;

/** Off by default (ADR-022): nothing publishes events yet. Safe to enable on every instance; see {@link OutboxRelay}. */
@Configuration
@EnableScheduling
@ConditionalOnProperty(name = "app.outbox.relay-enabled", havingValue = "true")
class OutboxRelayJob {
    private final OutboxRelay relay;
    private final int batch;

    OutboxRelayJob(OutboxRelay relay, @Value("${app.outbox.batch-size:50}") int batch) {
        this.relay = relay;
        this.batch = batch;
    }

    @Scheduled(fixedDelayString = "${app.outbox.poll-millis:1000}")
    void drain() {
        relay.deliverBatch(batch);
    }
}
