package kz.kunde.platform.events;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The only way to publish a domain event. It must run inside the business transaction ({@code MANDATORY}), so the fact and
 * the state change commit or roll back together; there is no dual write to a broker.
 */
@Service
public class OutboxWriter {
    private static final Pattern TYPE = Pattern.compile("^kunde\\.[a-z0-9_]+\\.[a-z0-9_]+$");

    private final JdbcTemplate db;
    private final ObjectMapper json;

    public OutboxWriter(JdbcTemplate db, ObjectMapper json) {
        this.db = db;
        this.json = json;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public UUID append(DomainEvent event) {
        if (event.type() == null || !TYPE.matcher(event.type()).matches()) {
            throw new IllegalArgumentException("Event type must look like kunde.<aggregate>.<fact>");
        }
        if (event.schemaVersion() < 1 || event.producer() == null || event.aggregateType() == null
                || event.aggregateId() == null || event.payload() == null) {
            throw new IllegalArgumentException("Event needs schemaVersion >= 1, producer, aggregateType, aggregateId and payload");
        }
        String payload;
        try {
            payload = json.writeValueAsString(event.payload());
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("Event payload is not serializable", e);
        }
        return db.queryForObject("""
                insert into platform.outbox_events (event_type, schema_version, producer, aggregate_type, aggregate_id,
                    aggregate_version, correlation_id, causation_id, city_id, payload)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb) returning event_id
                """, UUID.class, event.type(), event.schemaVersion(), event.producer(), event.aggregateType(),
                event.aggregateId(), event.aggregateVersion(), event.correlationId(), event.causationId(), event.cityId(), payload);
    }
}
