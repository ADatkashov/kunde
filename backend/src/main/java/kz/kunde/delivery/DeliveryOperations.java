package kz.kunde.delivery;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeliveryOperations {
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

    public List<Shipment> shipments() {
        return db.query("""
                select d.id, d.status, d.courier_id, d.partner_id, d.created_at, q.synthetic_route
                from transactions.deliveries d join transactions.delivery_quotes q on q.id = d.quote_id
                order by (d.status in %s or d.status = 'SEARCHING_COURIER') desc, d.created_at desc, d.id desc limit 100
                """.formatted(DeliveryDispatch.ACTIVE_DELIVERY_STATES), (rs, row) -> new Shipment(
                rs.getObject("id", UUID.class), DeliveryState.valueOf(rs.getString("status")),
                rs.getObject("courier_id", UUID.class), rs.getObject("partner_id", UUID.class),
                rs.getObject("created_at", OffsetDateTime.class), rs.getBoolean("synthetic_route")));
    }

    public List<Event> audit(UUID delivery) {
        if (!Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from transactions.deliveries where id = ?)",
                Boolean.class, delivery))) {
            throw new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_NOT_FOUND", "Delivery was not found");
        }
        return db.query("""
                select status, actor_id, reason, occurred_at from transactions.delivery_events
                where delivery_id = ? order by id
                """, (rs, row) -> new Event(DeliveryState.valueOf(rs.getString("status")),
                rs.getObject("actor_id", UUID.class), rs.getString("reason"),
                rs.getObject("occurred_at", OffsetDateTime.class)), delivery);
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
