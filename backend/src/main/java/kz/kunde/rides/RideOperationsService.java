package kz.kunde.rides;

import kz.kunde.platform.FeatureToggles;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.support.SupportCaseDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RideOperationsService {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;
    private final SupportCaseDirectory support;

    public RideOperationsService(JdbcTemplate db, FeatureToggles toggles, SupportCaseDirectory support) {
        this.db = db;
        this.support = support;
        this.toggles = toggles;
    }

    public List<Trip> trips() {
        requireEnabled();
        return db.query("""
                select r.id, r.status, r.driver_id, r.fleet_partner_id, r.created_at, q.synthetic,
                    q.ride_class, q.estimate_kzt
                from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
                order by (r.status in ('REQUESTED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING',
                    'DRIVER_ARRIVED','IN_PROGRESS')) desc, r.created_at desc, r.id desc limit 100
                """, (rs, row) -> new Trip(rs.getObject(1, UUID.class), RideState.valueOf(rs.getString(2)),
                        rs.getObject(3, UUID.class), rs.getObject(4, UUID.class),
                        rs.getObject(5, OffsetDateTime.class), rs.getBoolean(6),
                        RideMatching.RideClass.valueOf(rs.getString(7)), rs.getBigDecimal(8)));
    }

    /**
     * Aggregates over all rides. Counts include synthetic rides; money figures use only completed,
     * non-synthetic rides and are the quoted tariff fares, because no payment is captured yet.
     */
    public Summary summary() {
        requireEnabled();
        var totals = db.queryForObject("""
                select count(*),
                    count(*) filter (where r.status in ('REQUESTED','SEARCHING_DRIVER','DRIVER_ASSIGNED',
                        'DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')),
                    count(*) filter (where r.status = 'COMPLETED'),
                    count(*) filter (where r.status like 'CANCELLED%'),
                    count(*) filter (where q.synthetic),
                    coalesce(sum(q.estimate_kzt) filter (where r.status = 'COMPLETED' and not q.synthetic), 0),
                    round(avg(q.estimate_kzt) filter (where r.status = 'COMPLETED' and not q.synthetic), 2)
                from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
                """, (rs, row) -> new Object[] {rs.getLong(1), rs.getLong(2), rs.getLong(3), rs.getLong(4),
                        rs.getLong(5), rs.getBigDecimal(6), rs.getBigDecimal(7)});
        var byClass = db.query("""
                select q.ride_class, count(*) from transactions.rides r
                join transactions.ride_fare_quotes q on q.id = r.quote_id
                group by q.ride_class order by count(*) desc, q.ride_class
                """, (rs, row) -> new ClassCount(RideMatching.RideClass.valueOf(rs.getString(1)), rs.getLong(2)));
        var perDay = db.query("""
                with today as (select (statement_timestamp() at time zone 'Asia/Almaty')::date d)
                select today.d - n as day, count(r.id)
                from today cross join generate_series(0, 6) n
                left join transactions.rides r on (r.created_at at time zone 'Asia/Almaty')::date = today.d - n
                group by 1 order by 1
                """, (rs, row) -> new DayCount(rs.getObject(1, java.time.LocalDate.class), rs.getLong(2)));
        return new Summary((long) totals[0], (long) totals[1], (long) totals[2], (long) totals[3], (long) totals[4],
                (java.math.BigDecimal) totals[5], (java.math.BigDecimal) totals[6], "KZT", byClass, perDay);
    }

    public List<Complaint> complaints() {
        requireEnabled();
        return support.list(SupportCaseDirectory.Subject.RIDE, 100).stream().map(RideOperationsService::complaint).toList();
    }

    @Transactional
    public Complaint resolve(UUID actor, UUID id) {
        requireEnabled();
        return support.resolve(SupportCaseDirectory.Subject.RIDE, id, actor).map(RideOperationsService::complaint)
                .orElseThrow(RideOperationsService::missing);
    }

    public List<ComplaintEvent> complaintAudit(UUID id) {
        requireEnabled();
        if (support.find(SupportCaseDirectory.Subject.RIDE, id).isEmpty()) {
            throw missing();
        }
        return support.events(SupportCaseDirectory.Subject.RIDE, id, 100).stream()
                .map(e -> new ComplaintEvent(e.eventType(), e.actorUserId(), e.occurredAt())).toList();
    }

    private static Complaint complaint(SupportCaseDirectory.Case c) {
        return new Complaint(c.id(), c.subjectId(), c.message(), c.status(), c.createdAt());
    }

    private void requireEnabled() {
        if (!toggles.rides().enabled()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RIDES_UNAVAILABLE", "Rides operations are unavailable");
        }
    }

    private static ApiException missing() {
        return new ApiException(HttpStatus.NOT_FOUND, "RIDE_COMPLAINT_NOT_FOUND", "Ride complaint not found");
    }

    public record Trip(UUID id, RideState status, UUID driverId, UUID fleetId, OffsetDateTime createdAt, boolean synthetic,
            RideMatching.RideClass rideClass, java.math.BigDecimal fareKzt) {}
    public record ClassCount(RideMatching.RideClass rideClass, long rides) {}
    public record DayCount(java.time.LocalDate day, long rides) {}
    /** averageFareKzt is null when there is no completed non-synthetic ride. */
    public record Summary(long total, long active, long completed, long cancelled, long synthetic,
            java.math.BigDecimal completedFareKzt, java.math.BigDecimal averageFareKzt, String currency,
            List<ClassCount> byClass, List<DayCount> perDay) {}
    public record Complaint(UUID id, UUID rideId, String message, String status, OffsetDateTime createdAt) {}
    public record ComplaintEvent(String action, UUID actorId, OffsetDateTime occurredAt) {}
}
