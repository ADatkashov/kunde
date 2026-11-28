package kz.kunde.homeservices;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Verified reviews of Home Services (H6). Only the owner of a COMPLETED order can review it, once (the order id is unique); the
 * review is published at once and staff can hide it. Ratings are always computed here from PUBLISHED reviews, never stored; with no
 * review the rating is {@code null}, not zero. Every change is written to the append-only {@code home_service_review_events}.
 */
@Service
public class HomeServiceReviews {
    private static final String CATEGORY = "CLEANING";

    public record Rating(Double rating, long count, Double qualityRating, Double punctualityRating) {}

    public record Review(String id, int rating, Integer qualityRating, Integer punctualityRating, String comment, String authorName,
            String masterName, String serviceName, OffsetDateTime createdAt) {}

    public record ReviewPage(Rating summary, List<Review> items, long total, int limit, int offset) {}

    /** The author's own view of their review (includes the moderation state). */
    public record MyReview(String id, String bookingId, int rating, Integer qualityRating, Integer punctualityRating, String comment,
            String status, OffsetDateTime createdAt) {}

    public record MasterRating(String masterId, String masterName, Double rating, long count) {}

    public record PartnerSummary(Rating organization, List<MasterRating> masters) {}

    public record StaffReview(String id, String bookingNumber, String serviceName, String masterName, String venueName, int rating,
            Integer qualityRating, Integer punctualityRating, String comment, String status, String moderationNote, long version,
            long openComplaints, OffsetDateTime createdAt) {}

    public record Complaint(String id, String reviewId, String reason, String status, String resolution, OffsetDateTime createdAt,
            String reviewComment, int reviewRating, String reviewStatus, long reviewVersion) {}

    private final JdbcTemplate db;
    private final PartnerDirectory partners;

    public HomeServiceReviews(JdbcTemplate db, PartnerDirectory partners) {
        this.db = db;
        this.partners = partners;
    }

    // ---- customer

    /**
     * Creates the review of the caller's completed order. Repeating the same request returns the same review ({@code created = false});
     * a different review of an already reviewed order is refused.
     */
    @Transactional
    public Created create(UUID user, UUID booking, int rating, Integer quality, Integer punctuality, String comment) {
        var order = db.query("""
                select status, service_id, venue_id, master_id, (select partner_id from marketplace.booking_venues v where v.id = b.venue_id)
                from transactions.bookings b where id = ? and user_id = ? and category = ? for share
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                rs.getObject(4, UUID.class), rs.getObject(5, UUID.class)}, booking, user, CATEGORY).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        if (!"COMPLETED".equals(order[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_NOT_COMPLETED", "Only a completed order can be reviewed");
        }
        String text = comment == null || comment.isBlank() ? null : comment.strip();
        List<String> inserted = db.query("""
                insert into marketplace.home_service_reviews (booking_id, service_id, venue_id, partner_id, master_id, user_id,
                    rating, quality_rating, punctuality_rating, comment)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) on conflict (booking_id) do nothing returning id
                """, (rs, n) -> rs.getString(1), booking, order[1], order[2], order[4], order[3], user, rating, quality, punctuality, text);
        if (!inserted.isEmpty()) {
            event(UUID.fromString(inserted.getFirst()), user, "CUSTOMER", "CREATED", null);
            return new Created(mine(user, booking), true);
        }
        MyReview existing = mine(user, booking);
        boolean same = existing.rating() == rating && Objects.equals(existing.qualityRating(), quality)
                && Objects.equals(existing.punctualityRating(), punctuality) && Objects.equals(existing.comment(), text);
        if (!same) {
            throw new ApiException(HttpStatus.CONFLICT, "REVIEW_EXISTS", "This order has already been reviewed");
        }
        return new Created(existing, false);
    }

    public record Created(MyReview review, boolean created) {}

    public MyReview mine(UUID user, UUID booking) {
        return db.query("""
                select id, booking_id, rating, quality_rating, punctuality_rating, comment, status, created_at
                from marketplace.home_service_reviews where booking_id = ? and user_id = ?
                """, (rs, n) -> new MyReview(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getObject(4, Integer.class),
                rs.getObject(5, Integer.class), rs.getString(6), rs.getString(7), rs.getObject(8, OffsetDateTime.class)), booking, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Review not found"));
    }

    // ---- public reads (PUBLISHED only)

    /** Reviews of one dimension: {@code service_id}, {@code master_id} or {@code partner_id}; the column name is fixed by the caller. */
    ReviewPage page(String column, UUID id, Integer rating, UUID masterId, UUID venueId, int limit, int offset) {
        String where = " where r." + column + " = ? and r.status = 'PUBLISHED' and (?::int is null or r.rating = ?::int)"
                + " and (?::uuid is null or r.master_id = ?::uuid) and (?::uuid is null or r.venue_id = ?::uuid)";
        Object[] filter = {id, rating, rating, masterId, masterId, venueId, venueId};
        long total = db.queryForObject("select count(*) from marketplace.home_service_reviews r" + where, Long.class, filter);
        List<Object> args = new java.util.ArrayList<>(java.util.Arrays.asList(filter));
        args.add(limit);
        args.add(offset);
        List<Review> items = db.query("""
                select r.id, r.rating, r.quality_rating, r.punctuality_rating, r.comment, r.author_name,
                       m.name, s.name, r.created_at
                from marketplace.home_service_reviews r
                left join marketplace.booking_masters m on m.id = r.master_id
                left join marketplace.booking_services s on s.id = r.service_id
                """ + where + " order by r.created_at desc, r.id limit ? offset ?", (rs, n) -> new Review(rs.getString(1), rs.getInt(2),
                rs.getObject(3, Integer.class), rs.getObject(4, Integer.class), rs.getString(5), rs.getString(6), rs.getString(7),
                rs.getString(8), rs.getObject(9, OffsetDateTime.class)), args.toArray());
        return new ReviewPage(rating(column, id), items, total, limit, offset);
    }

    /** Average over published reviews; {@code null} ratings when there is none. {@code column} is one of three fixed names. */
    Rating rating(String column, UUID id) {
        if (!List.of("service_id", "master_id", "partner_id", "venue_id").contains(column)) {
            throw new IllegalArgumentException(column);
        }
        return db.queryForObject("""
                select round(avg(rating)::numeric, 1)::float8, count(*), round(avg(quality_rating)::numeric, 1)::float8,
                       round(avg(punctuality_rating)::numeric, 1)::float8
                from marketplace.home_service_reviews where status = 'PUBLISHED' and """ + " " + column + " = ?",
                (rs, n) -> new Rating(rs.getObject(1, Double.class), rs.getLong(2), rs.getObject(3, Double.class), rs.getObject(4, Double.class)), id);
    }

    // ---- partner (tenant isolation by partner_id)

    public ReviewPage partnerReviews(UUID user, UUID partnerId, Integer rating, UUID masterId, UUID venueId, int limit, int offset) {
        requireStaff(user, partnerId);
        return page("partner_id", partnerId, rating, masterId, venueId, limit, offset);
    }

    public PartnerSummary partnerSummary(UUID user, UUID partnerId) {
        requireStaff(user, partnerId);
        List<MasterRating> masters = db.query("""
                select m.id, m.name, round(avg(r.rating)::numeric, 1)::float8, count(r.id)
                from marketplace.booking_masters m join marketplace.booking_venues v on v.id = m.venue_id and v.partner_id = ?
                left join marketplace.home_service_reviews r on r.master_id = m.id and r.status = 'PUBLISHED'
                where v.category = ? and m.active group by m.id, m.name order by m.name, m.id
                """, (rs, n) -> new MasterRating(rs.getString(1), rs.getString(2), rs.getObject(3, Double.class), rs.getLong(4)), partnerId, CATEGORY);
        return new PartnerSummary(rating("partner_id", partnerId), masters);
    }

    /** One complaint per reporter and review; repeating it returns the existing one. */
    @Transactional
    public Complaint complain(UUID user, UUID partnerId, UUID reviewId, String reason) {
        requireStaff(user, partnerId);
        db.query("select id from marketplace.home_service_reviews where id = ? and partner_id = ? and status = 'PUBLISHED' for share",
                (rs, n) -> rs.getString(1), reviewId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Review not found"));
        List<String> inserted = db.query("""
                insert into marketplace.home_service_review_complaints (review_id, partner_id, reporter_user_id, reason)
                values (?, ?, ?, ?) on conflict (review_id, reporter_user_id) do nothing returning id
                """, (rs, n) -> rs.getString(1), reviewId, partnerId, user, reason.strip());
        if (!inserted.isEmpty()) {
            event(reviewId, user, "PARTNER", "COMPLAINT", reason.strip());
        }
        return complaints(null, "c.review_id = ? and c.reporter_user_id = ?", 1, 0, reviewId, user).getFirst();
    }

    // ---- executor

    public Rating masterRating(UUID master) {
        return rating("master_id", master);
    }

    // ---- staff (Admin; the controller checks the grant)

    public List<StaffReview> staffReviews(String status, int limit, int offset) {
        return db.query("""
                select r.id, b.booking_number, s.name, m.name, v.name, r.rating, r.quality_rating, r.punctuality_rating, r.comment,
                       r.status, r.moderation_note, r.version,
                       (select count(*) from marketplace.home_service_review_complaints c where c.review_id = r.id and c.status = 'OPEN'),
                       r.created_at
                from marketplace.home_service_reviews r
                left join transactions.bookings b on b.id = r.booking_id
                left join marketplace.booking_services s on s.id = r.service_id
                left join marketplace.booking_masters m on m.id = r.master_id
                left join marketplace.booking_venues v on v.id = r.venue_id
                where (?::text is null or r.status = ?::text)
                order by (r.status = 'PUBLISHED' and exists (select 1 from marketplace.home_service_review_complaints c
                    where c.review_id = r.id and c.status = 'OPEN')) desc, r.created_at desc, r.id limit ? offset ?
                """, (rs, n) -> new StaffReview(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                rs.getInt(6), rs.getObject(7, Integer.class), rs.getObject(8, Integer.class), rs.getString(9), rs.getString(10),
                rs.getString(11), rs.getLong(12), rs.getLong(13), rs.getObject(14, OffsetDateTime.class)), status, status, limit, offset);
    }

    /** Hides or republishes a review at the version the screen saw; the reason is mandatory and audited. */
    @Transactional
    public StaffReview moderate(UUID admin, UUID reviewId, boolean hide, long expectedVersion, String reason) {
        var row = db.query("select status, version from marketplace.home_service_reviews where id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getLong(2)}, reviewId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "REVIEW_NOT_FOUND", "Review not found"));
        if ((long) row[1] != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The review has changed; reload it");
        }
        String target = hide ? "HIDDEN" : "PUBLISHED";
        if (target.equals(row[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "REVIEW_STATE_INVALID", "The review is already " + target.toLowerCase());
        }
        db.update("update marketplace.home_service_reviews set status = ?, moderation_note = ?, version = version + 1, updated_at = now() where id = ?",
                target, reason.strip(), reviewId);
        event(reviewId, admin, "ADMIN", target, reason.strip());
        return staffReview(reviewId);
    }

    StaffReview staffReview(UUID id) {
        return db.query("""
                select r.id, b.booking_number, s.name, m.name, v.name, r.rating, r.quality_rating, r.punctuality_rating, r.comment,
                       r.status, r.moderation_note, r.version,
                       (select count(*) from marketplace.home_service_review_complaints c where c.review_id = r.id and c.status = 'OPEN'),
                       r.created_at
                from marketplace.home_service_reviews r
                left join transactions.bookings b on b.id = r.booking_id
                left join marketplace.booking_services s on s.id = r.service_id
                left join marketplace.booking_masters m on m.id = r.master_id
                left join marketplace.booking_venues v on v.id = r.venue_id where r.id = ?
                """, (rs, n) -> new StaffReview(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                rs.getInt(6), rs.getObject(7, Integer.class), rs.getObject(8, Integer.class), rs.getString(9), rs.getString(10),
                rs.getString(11), rs.getLong(12), rs.getLong(13), rs.getObject(14, OffsetDateTime.class)), id).getFirst();
    }

    public List<Complaint> staffComplaints(String status, int limit, int offset) {
        return complaints(status, "true", limit, offset);
    }

    private List<Complaint> complaints(String status, String extra, int limit, int offset, Object... extraArgs) {
        List<Object> args = new java.util.ArrayList<>();
        args.add(status);
        args.add(status);
        args.addAll(java.util.Arrays.asList(extraArgs));
        args.add(limit);
        args.add(offset);
        return db.query("""
                select c.id, c.review_id, c.reason, c.status, c.resolution, c.created_at, r.comment, r.rating, r.status, r.version
                from marketplace.home_service_review_complaints c join marketplace.home_service_reviews r on r.id = c.review_id
                where (?::text is null or c.status = ?::text) and """ + " " + extra + " order by c.created_at, c.id limit ? offset ?",
                (rs, n) -> new Complaint(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                rs.getObject(6, OffsetDateTime.class), rs.getString(7), rs.getInt(8), rs.getString(9), rs.getLong(10)), args.toArray());
    }

    /** Closes a complaint; {@code hide} also hides the review it is about (the review is locked and audited like a moderation). */
    @Transactional
    public Complaint resolve(UUID admin, UUID complaintId, String resolution, boolean hide) {
        var row = db.query("select review_id, status from marketplace.home_service_review_complaints where id = ? for update",
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2)}, complaintId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "COMPLAINT_NOT_FOUND", "Complaint not found"));
        if (!"OPEN".equals(row[1])) {
            throw new ApiException(HttpStatus.CONFLICT, "COMPLAINT_RESOLVED", "The complaint is already resolved");
        }
        UUID review = (UUID) row[0];
        if (hide) {
            db.query("select id from marketplace.home_service_reviews where id = ? for update", (rs, n) -> 1, review);
            db.update("update marketplace.home_service_reviews set status = 'HIDDEN', moderation_note = ?, version = version + 1, updated_at = now() "
                    + "where id = ? and status = 'PUBLISHED'", resolution.strip(), review);
            event(review, admin, "ADMIN", "HIDDEN", resolution.strip());
        }
        db.update("update marketplace.home_service_review_complaints set status = 'RESOLVED', resolution = ?, resolved_by = ?, resolved_at = now() where id = ?",
                resolution.strip(), admin, complaintId);
        event(review, admin, "ADMIN", "COMPLAINT_DONE", resolution.strip());
        return complaints(null, "c.id = ?", 1, 0, complaintId).getFirst();
    }

    // ---- internals

    private void requireStaff(UUID user, UUID partnerId) {
        if (!partners.isActiveStaffOfApprovedPartner(user, partnerId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND", "Partner not found");
        }
    }

    private void event(UUID review, UUID actor, String type, String action, String note) {
        db.update("insert into marketplace.home_service_review_events (review_id, actor_user_id, actor_type, action, note) values (?, ?, ?, ?, ?)",
                review, actor, type, action, note);
    }
}
