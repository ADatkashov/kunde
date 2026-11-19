package kz.kunde.rides;

import java.util.List;
import java.time.OffsetDateTime;
import java.util.Locale;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideMatching.RideClass;
import kz.kunde.rides.RideRoutingController.Coordinates;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RideDriverService {
    private final JdbcTemplate db;
    private final RidesFlags flags;

    public RideDriverService(JdbcTemplate db, RidesFlags flags) {
        this.db = db;
        this.flags = flags;
    }

    public Driver profile(UUID driver) {
        requireExecutor();
        return db.query("""
                select d.user_id, d.display_name, d.status, d.online, v.id as vehicle_id, v.description,
                    v.plate, v.ride_class, v.status as vehicle_status
                from transactions.ride_drivers d left join transactions.ride_vehicles v on v.driver_id = d.user_id
                where d.user_id = ?
                """, (rs, row) -> {
                    UUID vehicleId = rs.getObject("vehicle_id", UUID.class);
                    Vehicle vehicle = vehicleId == null ? null : new Vehicle(vehicleId, rs.getString("description"),
                            rs.getString("plate"), RideClass.valueOf(rs.getString("ride_class")),
                            Status.valueOf(rs.getString("vehicle_status")));
                    return new Driver(driver, rs.getString("display_name"), Status.valueOf(rs.getString("status")),
                            rs.getBoolean("online"), vehicle);
                }, driver).stream().findFirst().orElseThrow(() -> notFound("DRIVER_NOT_FOUND", "Driver profile not found"));
    }

    @Transactional
    public Driver register(UUID driver, String name) {
        requireExecutor();
        db.update("""
                insert into transactions.ride_drivers (user_id, display_name) values (?, ?)
                on conflict (user_id) do nothing
                """, driver, name.strip());
        return profile(driver);
    }

    @Transactional
    public Driver registerVehicle(UUID driver, String description, String plate, RideClass rideClass) {
        lockDriver(driver);
        if (db.update("""
                insert into transactions.ride_vehicles (driver_id, description, plate, ride_class)
                values (?, ?, ?, ?) on conflict do nothing
                """, driver, description.strip(), plate.toUpperCase(Locale.ROOT), rideClass.name()) == 0) {
            throw conflict("RIDE_VEHICLE_CONFLICT", "Vehicle or registration plate is already registered");
        }
        return profile(driver);
    }

    @Transactional
    public Driver availability(UUID driver, boolean online) {
        lockDriver(driver);
        var current = profile(driver);
        if (online) {
            if (current.status() != Status.APPROVED || current.vehicle() == null
                    || current.vehicle().status() != Status.APPROVED) {
                throw conflict("RIDE_DRIVER_NOT_APPROVED", "Driver and vehicle approval are required");
            }
            db.update("update transactions.ride_drivers set online = true where user_id = ?", driver);
        } else {
            clearAvailability(driver);
        }
        return profile(driver);
    }

    @Transactional
    public void location(UUID driver, Coordinates coordinates) {
        lockDriver(driver);
        if (!profile(driver).online()) {
            throw conflict("RIDE_DRIVER_OFFLINE", "Driver must be online");
        }
        if (db.update("""
                update transactions.ride_drivers set latitude = ?, longitude = ?, observed_at = statement_timestamp()
                where user_id = ? and (observed_at is null or observed_at <= statement_timestamp() - interval '3 seconds')
                """, coordinates.latitude(), coordinates.longitude(), driver) == 0) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "RIDE_LOCATION_RATE_LIMIT", "Location updates are too frequent");
        }
    }

    public List<UUID> pendingDrivers() {
        requireExecutor();
        return db.queryForList("""
                select d.user_id from transactions.ride_drivers d
                where d.status = 'PENDING' or exists (
                    select 1 from transactions.ride_vehicles v where v.driver_id = d.user_id and v.status = 'PENDING')
                order by d.user_id limit 100
                """, UUID.class);
    }

    @Transactional
    public Driver review(UUID reviewer, UUID driver, UUID vehicle, Decision decision) {
        if (reviewer.equals(driver)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "RIDE_SELF_REVIEW", "Drivers cannot review themselves");
        }
        lockDriver(driver);
        var current = profile(driver);
        var status = Status.valueOf(decision.name());
        if (vehicle == null) {
            if (current.status() == status) {
                return current;
            }
            if (status == Status.BLOCKED) {
                clearAvailability(driver);
            }
            db.update("update transactions.ride_drivers set status = ? where user_id = ?", status.name(), driver);
        } else {
            if (current.vehicle() == null || !vehicle.equals(current.vehicle().id())) {
                throw notFound("RIDE_VEHICLE_NOT_FOUND", "Vehicle not found");
            }
            if (current.vehicle().status() == status) {
                return current;
            }
            if (status == Status.BLOCKED) {
                clearAvailability(driver);
            }
            db.update("update transactions.ride_vehicles set status = ? where id = ?", status.name(), vehicle);
        }
        db.update("""
                insert into transactions.ride_driver_review_events (driver_id, vehicle_id, reviewer_id, status)
                values (?, ?, ?, ?)
                """, driver, vehicle, reviewer, status.name());
        return profile(driver);
    }

    public List<ReviewEvent> audit(UUID driver) {
        profile(driver);
        return db.query("""
                select id, vehicle_id, reviewer_id, status, occurred_at
                from transactions.ride_driver_review_events where driver_id = ? order by id desc limit 100
                """, (rs, row) -> new ReviewEvent(rs.getLong(1), rs.getObject(2, UUID.class),
                        rs.getObject(3, UUID.class), Status.valueOf(rs.getString(4)),
                        rs.getObject(5, OffsetDateTime.class)), driver);
    }

    private void requireExecutor() {
        if (!flags.executorAvailable()) {
            throw notFound("RIDES_EXECUTOR_UNAVAILABLE", "Rides executor is unavailable");
        }
    }

    private void lockDriver(UUID driver) {
        requireExecutor();
        if (db.queryForList("select user_id from transactions.ride_drivers where user_id = ? for update",
                UUID.class, driver).isEmpty()) {
            throw notFound("DRIVER_NOT_FOUND", "Driver profile not found");
        }
    }

    private void clearAvailability(UUID driver) {
        db.update("""
                update transactions.ride_drivers set online = false, latitude = null, longitude = null, observed_at = null
                where user_id = ?
                """, driver);
    }

    private static ApiException notFound(String code, String message) {
        return new ApiException(HttpStatus.NOT_FOUND, code, message);
    }

    private static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    public enum Status { PENDING, APPROVED, BLOCKED }
    public enum Decision { APPROVED, BLOCKED }
    public record ReviewEvent(long id, UUID vehicleId, UUID reviewerId, Status status, OffsetDateTime occurredAt) {}
    public record Driver(UUID userId, String displayName, Status status, boolean online, Vehicle vehicle) {}
    public record Vehicle(UUID id, String description, String plate, RideClass rideClass, Status status) {}
}
