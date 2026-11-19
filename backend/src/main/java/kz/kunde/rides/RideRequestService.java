package kz.kunde.rides;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideMatching.RideClass;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RideRequestService {
    private static final Pattern REQUEST_KEY = Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final String VIEW = """
            select r.id, r.quote_id, r.status, q.ride_class, q.tariff_version, q.estimate_kzt,
                   q.distance_meters, q.duration_seconds, r.created_at, q.synthetic,
                   d.display_name as driver_name, v.description as vehicle_name, v.plate as vehicle_plate
            from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
            left join transactions.ride_drivers d on d.user_id = r.driver_id
                and r.status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')
            left join transactions.ride_vehicles v on v.driver_id = d.user_id
            where r.user_id = ?
            """;

    private final JdbcTemplate db;
    private final RidesFlags flags;

    public RideRequestService(JdbcTemplate db, RidesFlags flags) {
        this.db = db;
        this.flags = flags;
    }

    @Transactional
    public Requested create(UUID customer, UUID quoteId, String requestKey) {
        if (requestKey == null || !REQUEST_KEY.matcher(requestKey).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_INVALID",
                    "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }

        db.query("select pg_advisory_xact_lock(hashtext('rides'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, customer.toString());
        var previous = db.query(VIEW + " and r.request_key = ?", this::view, customer, requestKey).stream().findFirst();
        if (previous.isPresent()) {
            if (!previous.get().quoteId().equals(quoteId)) {
                throw conflict("IDEMPOTENCY_KEY_REUSED", "Idempotency-Key was already used with another quote");
            }
            return new Requested(previous.get(), false);
        }
        if (!flags.consumerAvailable()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RIDES_UNAVAILABLE", "New rides are currently unavailable");
        }
        if (Boolean.TRUE.equals(db.queryForObject("""
                select exists(select 1 from transactions.rides where user_id = ? and status in
                    ('REQUESTED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS'))
                """, Boolean.class, customer))) {
            throw conflict("RIDE_ALREADY_REQUESTED", "A ride is already pending");
        }
        UUID rideId = db.query("""
                insert into transactions.rides (user_id, quote_id, request_key, status)
                select user_id, id, ?, 'REQUESTED' from transactions.ride_fare_quotes
                where user_id = ? and id = ? and expires_at > statement_timestamp() and (not synthetic or ?)
                on conflict (quote_id) do nothing returning id
                """, (rs, row) -> rs.getObject("id", UUID.class), requestKey, customer, quoteId, flags.syntheticRoutingEnabled())
                .stream().findFirst().orElseThrow(() -> conflict("RIDE_QUOTE_UNAVAILABLE", "Ride quote is unavailable"));
        event(rideId, RideState.REQUESTED);
        return new Requested(get(customer, rideId), true);
    }

    public RideView get(UUID customer, UUID rideId) {
        return db.query(VIEW + " and r.id = ?", this::view, customer, rideId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RIDE_NOT_FOUND", "Ride was not found"));
    }

    public List<RideView> list(UUID customer, int limit, int offset) {
        return db.query(VIEW + " order by r.created_at desc, r.id desc limit ? offset ?",
                this::view, customer, limit, offset);
    }

    @Transactional
    public RideView cancel(UUID customer, UUID rideId) {
        var ride = db.query(VIEW + " and r.id = ? for update of r", this::view, customer, rideId)
                .stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RIDE_NOT_FOUND", "Ride was not found"));
        if (ride.status() == RideState.CANCELLED_BY_CUSTOMER) {
            return ride;
        }
        var next = ride.status().transition(RideState.Actor.CUSTOMER, RideState.Action.CANCEL)
                .orElseThrow(() -> conflict("RIDE_CANCELLATION_UNAVAILABLE", "Ride can no longer be cancelled"));
        db.update("update transactions.rides set status = ? where id = ?", next.name(), rideId);
        db.update("update transactions.ride_offers set state = 'EXPIRED' where ride_id = ? and state = 'PENDING'", rideId);
        event(rideId, next);
        return get(customer, rideId);
    }

    private void event(UUID ride, RideState state) {
        db.update("insert into transactions.ride_events (ride_id, status) values (?, ?)", ride, state.name());
    }

    private RideView view(ResultSet rs, int row) throws SQLException {
        String name = rs.getString("driver_name");
        AssignedDriver driver = name == null ? null :
                new AssignedDriver(name, rs.getString("vehicle_name"), rs.getString("vehicle_plate"));
        return new RideView(rs.getObject("id", UUID.class), rs.getObject("quote_id", UUID.class),
                RideState.valueOf(rs.getString("status")), RideClass.valueOf(rs.getString("ride_class")),
                rs.getString("tariff_version"), rs.getBigDecimal("estimate_kzt"), "KZT",
                rs.getInt("distance_meters"), rs.getInt("duration_seconds"),
                rs.getObject("created_at", OffsetDateTime.class), rs.getBoolean("synthetic"), driver);
    }

    private static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    public record RideView(UUID id, UUID quoteId, RideState status, RideClass rideClass, String tariffVersion,
            BigDecimal estimateKzt, String currency, int distanceMeters, int durationSeconds, OffsetDateTime createdAt, boolean synthetic, AssignedDriver driver) {}

    public record AssignedDriver(String name, String vehicle, String plate) {}

    public record Requested(RideView ride, boolean created) {}
}
