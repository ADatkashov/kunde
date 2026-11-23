package kz.kunde.platform.events;

import java.time.OffsetDateTime;
import java.util.UUID;

/** An outbox row as seen by a consumer. {@code payloadJson} is the JSON the producer wrote; parse it per {@code schemaVersion}. */
public record StoredEvent(UUID eventId, String type, int schemaVersion, String producer, String aggregateType,
        UUID aggregateId, Long aggregateVersion, String correlationId, UUID causationId, UUID cityId,
        String payloadJson, OffsetDateTime occurredAt) {}
