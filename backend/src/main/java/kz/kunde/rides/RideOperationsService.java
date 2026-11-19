package kz.kunde.rides;

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
public class RideOperationsService {
    private static final String COMPLAINT = """
            select id, ride_id, message, status, created_at from support.cases where ride_id is not null
            """;
    private static final RowMapper<Complaint> COMPLAINT_ROW = (rs, row) -> new Complaint(
            rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getString(3), rs.getString(4),
            rs.getObject(5, OffsetDateTime.class));

    private final JdbcTemplate db;
    private final RidesFlags flags;

    public RideOperationsService(JdbcTemplate db, RidesFlags flags) {
        this.db = db;
        this.flags = flags;
    }

    public List<Trip> trips() {
        requireEnabled();
        return db.query("""
                select r.id, r.status, r.driver_id, r.fleet_partner_id, r.created_at, q.synthetic
                from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
                order by (r.status in ('REQUESTED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING',
                    'DRIVER_ARRIVED','IN_PROGRESS')) desc, r.created_at desc, r.id desc limit 100
                """, (rs, row) -> new Trip(rs.getObject(1, UUID.class), RideState.valueOf(rs.getString(2)),
                        rs.getObject(3, UUID.class), rs.getObject(4, UUID.class),
                        rs.getObject(5, OffsetDateTime.class), rs.getBoolean(6)));
    }

    public List<Complaint> complaints() {
        requireEnabled();
        return db.query(COMPLAINT + " order by (status <> 'RESOLVED') desc, created_at desc, id limit 100", COMPLAINT_ROW);
    }

    @Transactional
    public Complaint resolve(UUID actor, UUID id) {
        requireEnabled();
        var current = db.query(COMPLAINT + " and id = ? for update", COMPLAINT_ROW, id).stream()
                .findFirst().orElseThrow(RideOperationsService::missing);
        if (!"RESOLVED".equals(current.status())) {
            db.update("update support.cases set status = 'RESOLVED', updated_at = statement_timestamp() where id = ?", id);
            db.update("insert into support.case_events (case_id, event_type, actor_user_id) values (?, 'RESOLVED', ?)",
                    id, actor);
            return new Complaint(current.id(), current.rideId(), current.message(), "RESOLVED", current.createdAt());
        }
        return current;
    }

    public List<ComplaintEvent> complaintAudit(UUID id) {
        requireEnabled();
        if (db.query(COMPLAINT + " and id = ?", COMPLAINT_ROW, id).isEmpty()) {
            throw missing();
        }
        return db.query("""
                select event_type, actor_user_id, occurred_at from support.case_events
                where case_id = ? order by id limit 100
                """, (rs, row) -> new ComplaintEvent(rs.getString(1), rs.getObject(2, UUID.class),
                        rs.getObject(3, OffsetDateTime.class)), id);
    }

    private void requireEnabled() {
        if (!flags.enabled()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RIDES_UNAVAILABLE", "Rides operations are unavailable");
        }
    }

    private static ApiException missing() {
        return new ApiException(HttpStatus.NOT_FOUND, "RIDE_COMPLAINT_NOT_FOUND", "Ride complaint not found");
    }

    public record Trip(UUID id, RideState status, UUID driverId, UUID fleetId, OffsetDateTime createdAt, boolean synthetic) {}
    public record Complaint(UUID id, UUID rideId, String message, String status, OffsetDateTime createdAt) {}
    public record ComplaintEvent(String action, UUID actorId, OffsetDateTime occurredAt) {}
}
