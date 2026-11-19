package kz.kunde.delivery;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import kz.kunde.platform.ApiException;
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
    private static final String COMPLAINTS = """
            select id, delivery_id, category, message, status, created_at
            from support.cases where delivery_id is not null
            """;
    private static final RowMapper<Complaint> COMPLAINT = (rs, row) -> new Complaint(
            rs.getObject("id", UUID.class), rs.getObject("delivery_id", UUID.class), rs.getString("category"),
            rs.getString("message"), rs.getString("status"), rs.getObject("created_at", OffsetDateTime.class));

    private final JdbcTemplate db;

    public DeliveryOperations(JdbcTemplate db) {
        this.db = db;
    }

    public List<Shipment> shipments(UUID actor) {
        requireDeliveryAccess(actor);
        return db.query("""
                select d.id, d.status, d.courier_id, d.partner_id, d.created_at, q.synthetic_route
                from transactions.deliveries d join transactions.delivery_quotes q on q.id = d.quote_id
                where %s
                order by (d.status in %s or d.status = 'SEARCHING_COURIER') desc, d.created_at desc, d.id desc limit 100
                """.formatted(VISIBLE_DELIVERY, DeliveryDispatch.ACTIVE_DELIVERY_STATES), (rs, row) -> new Shipment(
                rs.getObject("id", UUID.class), DeliveryState.valueOf(rs.getString("status")),
                rs.getObject("courier_id", UUID.class), rs.getObject("partner_id", UUID.class),
                rs.getObject("created_at", OffsetDateTime.class), rs.getBoolean("synthetic_route")), actor);
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
        return db.query(COMPLAINTS + " order by (status <> 'RESOLVED') desc, created_at desc, id limit 100", COMPLAINT);
    }

    @Transactional
    public Complaint resolve(UUID reviewer, UUID id) {
        var current = db.query(COMPLAINTS + " and id = ? for update", COMPLAINT, id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_COMPLAINT_NOT_FOUND",
                        "Delivery complaint was not found"));
        if ("RESOLVED".equals(current.status())) {
            return current;
        }
        db.update("update support.cases set status = 'RESOLVED', updated_at = statement_timestamp() where id = ?", id);
        db.update("""
                insert into support.case_events(case_id, event_type, actor_user_id) values (?, 'RESOLVED', ?)
                """, id, reviewer);
        return new Complaint(current.id(), current.deliveryId(), current.category(), current.message(),
                "RESOLVED", current.createdAt());
    }

    public record Shipment(UUID id, DeliveryState status, UUID courierId, UUID partnerId, OffsetDateTime createdAt,
            boolean syntheticRoute) {}
    public record Event(DeliveryState status, UUID actorId, String reason, OffsetDateTime occurredAt) {}
    public record Complaint(UUID id, UUID deliveryId, String category, String message, String status,
            OffsetDateTime createdAt) {}
}
