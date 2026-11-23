package kz.kunde.platform.events;

import java.util.UUID;

/**
 * A past-tense business fact to publish through the transactional outbox (docs/architecture/14-event-driven-architecture.md).
 * {@code type} looks like {@code kunde.order.created}; {@code schemaVersion} starts at 1 and only grows: a consumer must
 * accept every version it declares, and an incompatible change is a new version, never an edit of an old one.
 */
public record DomainEvent(String type, int schemaVersion, String producer, String aggregateType, UUID aggregateId,
        Long aggregateVersion, String correlationId, UUID causationId, UUID cityId, Object payload) {

    public static DomainEvent of(String type, int schemaVersion, String producer, String aggregateType, UUID aggregateId,
            Object payload) {
        return new DomainEvent(type, schemaVersion, producer, aggregateType, aggregateId, null, null, null, null, payload);
    }
}
