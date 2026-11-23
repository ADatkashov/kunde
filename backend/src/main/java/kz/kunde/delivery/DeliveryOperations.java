package kz.kunde.delivery;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.support.SupportCaseDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeliveryOperations {
    // Delivery currently persists organization and resource identity, but has no canonical region.
    private static final String DELIVERY_GRANTS = """
            from identity.effective_admin_permissions g
            where g.user_id = ? and g.permission = 'DELIVERY_OPERATIONS'
              and (g.product_code is null or g.product_code = 'DELIVERY')
              and g.region_code is null
            """;
    private static final String VISIBLE_DELIVERY = "exists (select 1 " + DELIVERY_GRANTS + """
              and (g.organization_id is null or g.organization_id = d.partner_id)
              and (g.resource_id is null or g.resource_id = d.id))
            """;
    private final JdbcTemplate db;
    private final SupportCaseDirectory support;

    public DeliveryOperations(JdbcTemplate db, SupportCaseDirectory support) {
        this.db = db;
        this.support = support;
    }

    public List<Shipment> shipments(UUID actor, DeliveryState status, OffsetDateTime from, OffsetDateTime to) {
        requireDeliveryAccess(actor);
        if (from != null && to != null && !from.isBefore(to)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_DELIVERY_PERIOD",
                    "Delivery reporting start must precede the end");
        }
        return db.query("""
                select d.id, d.status, d.courier_id, d.partner_id, d.created_at, q.synthetic_route
                from transactions.deliveries d join transactions.delivery_quotes q on q.id = d.quote_id
                where %s
                  and d.status = coalesce(cast(? as transactions.delivery_state), d.status)
                  and d.created_at >= coalesce(cast(? as timestamptz), '-infinity')
                  and d.created_at < coalesce(cast(? as timestamptz), 'infinity')
                order by (d.status in %s or d.status = 'SEARCHING_COURIER') desc, d.created_at desc, d.id desc limit 100
                """.formatted(VISIBLE_DELIVERY, DeliveryDispatch.ACTIVE_DELIVERY_STATES), (rs, row) -> new Shipment(
                rs.getObject("id", UUID.class), DeliveryState.valueOf(rs.getString("status")),
                rs.getObject("courier_id", UUID.class), rs.getObject("partner_id", UUID.class),
                rs.getObject("created_at", OffsetDateTime.class), rs.getBoolean("synthetic_route")),
                actor, status == null ? null : status.name(), from, to);
    }

    public ShipmentSummary summary(UUID actor, OffsetDateTime from, OffsetDateTime to) {
        requireDeliveryAccess(actor);
        if (!from.isBefore(to) || Duration.between(from, to).compareTo(Duration.ofDays(31)) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_DELIVERY_PERIOD",
                    "Delivery reporting period must be positive and at most 31 days");
        }
        var counts = db.query("""
                select d.status, count(*) as shipments
                from transactions.deliveries d
                where d.created_at >= ? and d.created_at < ? and %s
                group by d.status order by d.status
                """.formatted(VISIBLE_DELIVERY), (rs, row) -> new ShipmentCount(
                DeliveryState.valueOf(rs.getString("status")), rs.getLong("shipments")), from, to, actor);
        return new ShipmentSummary(from, to, counts.stream().mapToLong(ShipmentCount::shipments).sum(), counts);
    }

    public List<Event> audit(UUID actor, UUID delivery) {
        requireDeliveryAccess(actor);
        var events = db.query("""
                select e.status, e.actor_id, e.reason, e.occurred_at
                from transactions.deliveries d
                left join transactions.delivery_events e on e.delivery_id = d.id
                where d.id = ? and %s
                order by e.id
                """.formatted(VISIBLE_DELIVERY), (rs, row) -> {
                    String status = rs.getString("status");
                    return status == null ? null : new Event(DeliveryState.valueOf(status),
                            rs.getObject("actor_id", UUID.class), rs.getString("reason"),
                            rs.getObject("occurred_at", OffsetDateTime.class));
                }, delivery, actor);
        if (events.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_NOT_FOUND", "Delivery was not found");
        }
        return events.stream().filter(Objects::nonNull).toList();
    }

    public boolean canReadShipments(UUID actor) {
        return Boolean.TRUE.equals(db.queryForObject("select exists (select 1 " + DELIVERY_GRANTS + ")",
                Boolean.class, actor));
    }

    private void requireDeliveryAccess(UUID actor) {
        if (!canReadShipments(actor)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ADMIN_FORBIDDEN", "Administrator permission is required");
        }
    }

    public List<Complaint> complaints() {
        return support.list(SupportCaseDirectory.Subject.DELIVERY, 100).stream().map(DeliveryOperations::complaint).toList();
    }

    @Transactional
    public Complaint resolve(UUID reviewer, UUID id) {
        return support.resolve(SupportCaseDirectory.Subject.DELIVERY, id, reviewer).map(DeliveryOperations::complaint)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_COMPLAINT_NOT_FOUND",
                        "Delivery complaint was not found"));
    }

    private static Complaint complaint(SupportCaseDirectory.Case c) {
        return new Complaint(c.id(), c.subjectId(), c.category(), c.message(), c.status(), c.createdAt());
    }

    public record Shipment(UUID id, DeliveryState status, UUID courierId, UUID partnerId, OffsetDateTime createdAt,
            boolean syntheticRoute) {}
    public record ShipmentSummary(OffsetDateTime from, OffsetDateTime to, long total, List<ShipmentCount> byStatus) {}
    public record ShipmentCount(DeliveryState status, long shipments) {}
    public record Event(DeliveryState status, UUID actorId, String reason, OffsetDateTime occurredAt) {}
    public record Complaint(UUID id, UUID deliveryId, String category, String message, String status,
            OffsetDateTime createdAt) {}
}
