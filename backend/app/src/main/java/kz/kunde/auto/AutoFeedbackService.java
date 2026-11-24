package kz.kunde.auto;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Customer complaints and reviews. A complaint refers to the customer's own booking or on-site job; a review can only be left once
 * by the owner of a COMPLETED booking. Both stay available while Auto is switched off (they concern work already done).
 */
@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoFeedbackService {
    private static final Set<String> KINDS = Set.of("QUALITY", "PRICE", "BEHAVIOR", "NO_SHOW", "OTHER");

    public record ComplaintRequest(UUID bookingId, UUID jobId, String kind, String description) {}

    public record Complaint(String id, String bookingId, String jobId, String kind, String description, String status, String resolution,
            OffsetDateTime createdAt) {}

    public record ReviewRequest(Integer rating, String text) {}

    public record Review(String bookingId, int rating, String text, OffsetDateTime createdAt) {}

    private final JdbcTemplate db;

    public AutoFeedbackService(JdbcTemplate db) {
        this.db = db;
    }

    @Transactional
    public Complaint complain(UUID user, ComplaintRequest r) {
        if ((r.bookingId() == null) == (r.jobId() == null)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMPLAINT_SUBJECT_INVALID", "Provide exactly one of bookingId and jobId");
        }
        if (r.kind() == null || !KINDS.contains(r.kind())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMPLAINT_KIND_INVALID", "kind must be one of " + KINDS);
        }
        String text = r.description() == null ? "" : r.description().strip();
        if (text.length() < 5 || text.length() > 500) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMPLAINT_TEXT_INVALID", "Describe the problem in 5-500 characters");
        }
        // Ownership first: someone else's booking or job looks like it does not exist.
        Integer owned = r.bookingId() != null
                ? db.queryForObject("select count(*) from transactions.bookings where id = ? and user_id = ? and category = 'AUTO'", Integer.class, r.bookingId(), user)
                : db.queryForObject("select count(*) from transactions.auto_jobs where id = ? and user_id = ?", Integer.class, r.jobId(), user);
        if (owned == null || owned == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "COMPLAINT_SUBJECT_NOT_FOUND", "Booking or job not found");
        }
        db.query("select pg_advisory_xact_lock(hashtext('auto-complaint'), hashtext(?))", (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        Integer open = db.queryForObject("select count(*) from transactions.auto_complaints where user_id = ? and status = 'OPEN' and "
                + (r.bookingId() != null ? "booking_id = ?" : "job_id = ?"), Integer.class, user, r.bookingId() != null ? r.bookingId() : r.jobId());
        if (open != null && open > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "COMPLAINT_ALREADY_OPEN", "You already have an open complaint about this");
        }
        UUID id = db.queryForObject("insert into transactions.auto_complaints (user_id, booking_id, job_id, kind, description) values (?, ?, ?, ?, ?) returning id",
                UUID.class, user, r.bookingId(), r.jobId(), r.kind(), text);
        return complaint(id);
    }

    @Transactional(readOnly = true)
    public List<Complaint> mine(UUID user) {
        return db.queryForList("select id from transactions.auto_complaints where user_id = ? order by created_at desc limit 50", UUID.class, user)
                .stream().map(this::complaint).toList();
    }

    @Transactional(readOnly = true)
    public List<Complaint> queue(boolean includeResolved) {
        return db.queryForList("select id from transactions.auto_complaints where ? or status = 'OPEN' order by (status = 'OPEN') desc, created_at desc limit 100",
                UUID.class, includeResolved).stream().map(this::complaint).toList();
    }

    @Transactional
    public Complaint resolve(UUID admin, UUID id, String resolution) {
        String text = resolution == null ? "" : resolution.strip();
        if (text.isEmpty() || text.length() > 300) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "RESOLUTION_REQUIRED", "A resolution of 1-300 characters is required");
        }
        var row = db.query("select status, user_id from transactions.auto_complaints where id = ? for update", (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class)}, id)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "COMPLAINT_NOT_FOUND", "Complaint not found"));
        if (admin.equals(row[1])) {
            throw new ApiException(HttpStatus.FORBIDDEN, "SELF_REVIEW", "You cannot resolve your own complaint");
        }
        if (!"RESOLVED".equals(row[0])) {
            db.update("update transactions.auto_complaints set status = 'RESOLVED', resolution = ?, resolved_by = ?, resolved_at = now() where id = ?", text, admin, id);
            db.update("insert into marketplace.auto_admin_events (admin_user_id, action, target, detail) values (?, 'COMPLAINT_RESOLVED', ?, ?)", admin, id.toString(), text);
        }
        return complaint(id);
    }

    private Complaint complaint(UUID id) {
        return db.query("select id, booking_id, job_id, kind, description, status, resolution, created_at from transactions.auto_complaints where id = ?",
                (rs, n) -> new Complaint(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7),
                        rs.getObject(8, OffsetDateTime.class)), id).get(0);
    }

    @Transactional
    public Review review(UUID user, UUID bookingId, ReviewRequest r) {
        if (r.rating() == null || r.rating() < 1 || r.rating() > 5) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "RATING_INVALID", "rating must be 1-5");
        }
        String text = r.text() == null ? "" : r.text().strip();
        if (text.length() > 500) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REVIEW_TEXT_INVALID", "The review text is at most 500 characters");
        }
        var row = db.query("select status, venue_id from transactions.bookings where id = ? and user_id = ? and category = 'AUTO' for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class)}, bookingId, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        if (!"COMPLETED".equals(row[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "REVIEW_NOT_ALLOWED", "Only a completed booking can be reviewed");
        }
        if (db.update("insert into transactions.auto_reviews (booking_id, user_id, venue_id, rating, text) values (?, ?, ?, ?, ?) on conflict (booking_id) do nothing",
                bookingId, user, row[1], r.rating(), text) == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "REVIEW_EXISTS", "This booking was already reviewed");
        }
        return db.query("select booking_id, rating, text, created_at from transactions.auto_reviews where booking_id = ?",
                (rs, n) -> new Review(rs.getString(1), rs.getInt(2), rs.getString(3), rs.getObject(4, OffsetDateTime.class)), bookingId).get(0);
    }

    @Transactional(readOnly = true)
    public Review reviewOf(UUID user, UUID bookingId) {
        return db.query("select booking_id, rating, text, created_at from transactions.auto_reviews where booking_id = ? and user_id = ?",
                (rs, n) -> new Review(rs.getString(1), rs.getInt(2), rs.getString(3), rs.getObject(4, OffsetDateTime.class)), bookingId, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "No review yet"));
    }
}
