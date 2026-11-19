package kz.kunde.delivery;

import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideRoutingController.Coordinates;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeliveryCouriers {
    private static final String PROFILES = """
            select user_id, display_name, vehicle, status, online, max_grams, max_side_cm
            from transactions.delivery_couriers
            """;
    private final JdbcTemplate db;
    private final DeliveryProperties flags;

    public DeliveryCouriers(JdbcTemplate db, DeliveryProperties flags) {
        this.db = db;
        this.flags = flags;
    }

    @Transactional
    public Profile register(UUID courier, String name, Vehicle vehicle) {
        requireEnrollment();
        db.update("""
                insert into transactions.delivery_couriers(user_id, display_name, vehicle)
                values (?, ?, ?) on conflict (user_id) do nothing
                """, courier, name, vehicle.name());
        var profile = profile(courier);
        if (!profile.name().equals(name) || profile.vehicle() != vehicle) {
            throw new ApiException(HttpStatus.CONFLICT, "DELIVERY_PROFILE_EXISTS", "Courier profile already exists");
        }
        return profile;
    }

    public Profile profile(UUID courier) {
        return db.query(PROFILES + " where user_id = ?", DeliveryCouriers::read, courier).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_COURIER_NOT_FOUND", "Courier not found"));
    }

    public List<Profile> forReview() {
        return db.query(PROFILES + " where status = 'PENDING' order by user_id limit 100", DeliveryCouriers::read);
    }

    @Transactional
    public Profile review(UUID admin, UUID courier, Decision decision, int maxGrams, int maxSideCm, String reason) {
        if (admin.equals(courier)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "DELIVERY_SELF_REVIEW", "Self review is forbidden");
        }
        int changed = db.update("""
                update transactions.delivery_couriers set status = ?, online = false, latitude = null, longitude = null,
                    observed_at = null, max_grams = ?, max_side_cm = ?
                where user_id = ? and (status, max_grams, max_side_cm) is distinct from (?, ?, ?)
                """, decision.name(), maxGrams, maxSideCm, courier, decision.name(), maxGrams, maxSideCm);
        if (changed != 0) {
            db.update("""
                    insert into transactions.delivery_courier_reviews(courier_id, reviewer_id, decision, reason)
                    values (?, ?, ?, ?)
                    """, courier, admin, decision.name(), reason);
        }
        return profile(courier);
    }

    @Transactional
    public Profile availability(UUID courier, boolean online) {
        if (online) {
            requireEnrollment();
        }
        int changed = db.update("""
                update transactions.delivery_couriers set online = ?, latitude = null, longitude = null, observed_at = null
                where user_id = ? and (not ? or status = 'APPROVED') and online <> ?
                """, online, courier, online, online);
        var profile = profile(courier);
        if (changed == 0 && online && !profile.online()) {
            throw new ApiException(HttpStatus.CONFLICT, "DELIVERY_COURIER_NOT_APPROVED", "Courier approval required");
        }
        return profile;
    }

    public void location(UUID courier, Coordinates point) {
        requireEnrollment();
        int changed = db.update("""
                update transactions.delivery_couriers set latitude = ?, longitude = ?, observed_at = statement_timestamp()
                where user_id = ? and online and status = 'APPROVED'
                    and (observed_at is null or observed_at <= statement_timestamp() - interval '5 seconds')
                """, point.latitude(), point.longitude(), courier);
        if (changed == 0 && !profile(courier).online()) {
            throw new ApiException(HttpStatus.CONFLICT, "DELIVERY_COURIER_OFFLINE", "Courier is offline");
        }
    }

    private static Profile read(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Profile(rs.getObject("user_id", UUID.class), rs.getString("display_name"),
                Vehicle.valueOf(rs.getString("vehicle")), rs.getString("status"), rs.getBoolean("online"),
                rs.getObject("max_grams", Integer.class), rs.getObject("max_side_cm", Integer.class));
    }

    private void requireEnrollment() {
        if (!flags.enabled() || !flags.executorEnabled()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_EXECUTOR_UNAVAILABLE", "Courier enrollment unavailable");
        }
    }

    public enum Vehicle { WALK, BICYCLE, MOTORCYCLE, CAR }
    public enum Decision { APPROVED, BLOCKED }
    public record Profile(UUID userId, String name, Vehicle vehicle, String status, boolean online,
            Integer maxGrams, Integer maxSideCm) {}
}
