package kz.kunde.rides;

import java.time.OffsetDateTime;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** A customer rates the driver of a completed ride once; the rating is immutable. */
@Service
public class RideRatingService {
    private final JdbcTemplate db;

    public RideRatingService(JdbcTemplate db) {
        this.db = db;
    }

    @Transactional
    public Result rate(UUID customer, UUID rideId, int stars, String comment) {
        if (stars < 1 || stars > 5) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "RIDE_RATING_INVALID", "Rating must be 1 to 5 stars");
        }
        String note = comment == null || comment.isBlank() ? null : comment.strip();
        var ride = db.query("""
                select status, driver_id from transactions.rides where id = ? and user_id = ? for update
                """, (rs, row) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class)}, rideId, customer)
                .stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RIDE_NOT_FOUND", "Ride was not found"));
        if (!RideState.COMPLETED.name().equals(ride[0]) || ride[1] == null) {
            throw conflict("RIDE_NOT_RATEABLE", "Only a completed ride with a driver can be rated");
        }
        boolean inserted = db.update("""
                insert into transactions.ride_ratings (ride_id, user_id, driver_id, stars, comment)
                values (?, ?, ?, ?, ?) on conflict (ride_id) do nothing
                """, rideId, customer, ride[1], stars, note) == 1;
        var saved = db.queryForObject("""
                select ride_id, stars, comment, created_at from transactions.ride_ratings where ride_id = ?
                """, (rs, row) -> new RatingView(rs.getObject(1, UUID.class), rs.getInt(2), rs.getString(3),
                        rs.getObject(4, OffsetDateTime.class)), rideId);
        if (!inserted && (saved.stars() != stars || !java.util.Objects.equals(saved.comment(), note))) {
            throw conflict("RIDE_ALREADY_RATED", "This ride already has a different rating");
        }
        return new Result(saved, inserted);
    }

    private static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    public record RatingView(UUID rideId, int stars, String comment, OffsetDateTime createdAt) {}

    public record Result(RatingView rating, boolean created) {}
}
