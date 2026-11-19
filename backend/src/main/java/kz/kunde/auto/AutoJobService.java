package kz.kunde.auto;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * On-site (roadside) Auto jobs and the AUTO_SPECIALIST executor. Separate tables and permissions from Rides and Delivery.
 * A specialist works only in categories an administrator approved. Accepting is atomic (row lock + one active job per specialist
 * and per car enforced by unique indexes), the customer's exact location is shown only to the assigned specialist, and the final
 * price is proposed on site and approved by the customer. New requests and accepts stop when Auto is switched off; jobs already
 * assigned can still be progressed or cancelled.
 */
@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoJobService {
    private static final Pattern KEY = Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final int RADIUS_KM = 30;
    private static final String ACTIVE = "('ASSIGNED', 'ARRIVED', 'IN_PROGRESS')";

    public enum Action { ARRIVE, START, PROPOSE_PRICE, COMPLETE, RELEASE }

    public record JobRequest(UUID vehicleId, String category, String description, String addressText, BigDecimal latitude, BigDecimal longitude) {}

    public record Timeline(String status, OffsetDateTime at, String actor, String reason) {}

    /** Customer view. The specialist's name appears once one is assigned; no contact data is exposed. */
    public record JobView(String id, String vehicle, String category, String description, String addressText, String status,
            String specialist, long priceMinor, String priceKind, Long finalPriceMinor, String priceApproval, boolean cancellable,
            OffsetDateTime createdAt, List<Timeline> timeline) {}

    /** Specialist view: coordinates and address only after assignment; before that an approximate area and distance. */
    public record SpecialistJob(String id, String vehicle, String category, String description, String addressText, BigDecimal latitude,
            BigDecimal longitude, String status, long priceMinor, String priceKind, Long finalPriceMinor, String priceApproval,
            Double distanceKm, List<String> allowedActions) {}

    public record Profile(String userId, String name, String status, boolean online, List<String> categories) {}

    public record Reviewed(String userId, String name, String status, boolean online, List<String> categories) {}

    private final JdbcTemplate db;
    private final AutoProperties props;

    public AutoJobService(JdbcTemplate db, AutoProperties props) {
        this.db = db;
        this.props = props;
    }

    // ---- customer ------------------------------------------------------------------------------

    @Transactional
    public JobView request(UUID user, JobRequest r, String key) {
        if (key == null || !KEY.matcher(key).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_INVALID", "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }
        db.query("select pg_advisory_xact_lock(hashtext('auto-job'), hashtext(?))", (RowCallbackHandler) rs -> {}, user.toString());
        var existing = db.query("select id, category, vehicle_id from transactions.auto_jobs where user_id = ? and idempotency_key = ?",
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2), rs.getObject(3, UUID.class)}, user, key).stream().findFirst();
        if (existing.isPresent()) {
            if (r.vehicleId() == null || !existing.get()[2].equals(r.vehicleId()) || !existing.get()[1].equals(r.category())) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "Idempotency-Key was already used for a different request");
            }
            return job(user, (UUID) existing.get()[0]);
        }
        requireEnabled();
        if (r.vehicleId() == null || r.category() == null || r.latitude() == null || r.longitude() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "JOB_INVALID", "vehicleId, category and location are required");
        }
        String address = r.addressText() == null ? "" : r.addressText().strip();
        if (address.length() < 5 || address.length() > 300) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ADDRESS_REQUIRED", "Describe where the car is (5-300 characters)");
        }
        if (r.latitude().abs().compareTo(BigDecimal.valueOf(90)) > 0 || r.longitude().abs().compareTo(BigDecimal.valueOf(180)) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "LOCATION_INVALID", "Invalid coordinates");
        }
        String description = r.description() == null ? "" : r.description().strip();
        if (description.length() > 300) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "DESCRIPTION_INVALID", "Description is at most 300 characters");
        }
        String label = db.query("select make || ' ' || model || ' ' || production_year || coalesce(' ' || plate, '') from transactions.customer_vehicles "
                + "where id = ? and user_id = ? and not archived", (rs, n) -> rs.getString(1), r.vehicleId(), user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VEHICLE_NOT_FOUND", "Vehicle not found"));
        Long price = db.query("select t.base_price_minor from marketplace.auto_roadside_tariffs t join marketplace.auto_service_categories c on c.code = t.category "
                + "where t.category = ? and c.mobile and c.enabled", (rs, n) -> rs.getLong(1), r.category()).stream().findFirst().orElse(null);
        if (price == null) {
            throw new ApiException(HttpStatus.CONFLICT, "AUTO_CATEGORY_DISABLED", "This kind of on-site help is unavailable");
        }
        Integer active = db.queryForObject("select count(*) from transactions.auto_jobs where vehicle_id = ? and status in ('REQUESTED', 'ASSIGNED', 'ARRIVED', 'IN_PROGRESS')",
                Integer.class, r.vehicleId());
        if (active != null && active > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "JOB_ALREADY_ACTIVE", "This car already has an active on-site request");
        }
        try {
            UUID id = db.queryForObject("""
                    insert into transactions.auto_jobs (user_id, vehicle_id, vehicle_label, category, description, address_text, latitude, longitude,
                        price_minor, idempotency_key) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                    """, UUID.class, user, r.vehicleId(), label, r.category(), description, address, r.latitude(), r.longitude(), price, key);
            event(id, "REQUESTED", "CUSTOMER", user, null);
            return job(user, id);
        } catch (DataIntegrityViolationException e) {
            if (e.getMostSpecificCause() instanceof SQLException sql && "23505".equals(sql.getSQLState())) {
                throw new ApiException(HttpStatus.CONFLICT, "JOB_ALREADY_ACTIVE", "This car already has an active on-site request");
            }
            throw e;
        }
    }

    @Transactional(readOnly = true)
    public List<JobView> jobs(UUID user) {
        return query(user, null);
    }

    @Transactional(readOnly = true)
    public JobView job(UUID user, UUID id) {
        return query(user, id).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
    }

    @Transactional
    public JobView cancel(UUID user, UUID id) {
        String status = db.query("select status from transactions.auto_jobs where id = ? and user_id = ? for update", (rs, n) -> rs.getString(1), id, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
        if ("CANCELLED".equals(status)) { return job(user, id); }
        if (!("REQUESTED".equals(status) || "ASSIGNED".equals(status))) {
            throw new ApiException(HttpStatus.CONFLICT, "JOB_NOT_CANCELLABLE", "The specialist has already arrived");
        }
        db.update("update transactions.auto_jobs set status = 'CANCELLED', cancelled_by = 'CUSTOMER', updated_at = now(), version = version + 1 where id = ?", id);
        event(id, "CANCELLED", "CUSTOMER", user, null);
        return job(user, id);
    }

    @Transactional
    public JobView decidePrice(UUID user, UUID id, boolean approve) {
        String current = db.query("select price_approval from transactions.auto_jobs where id = ? and user_id = ? for update", (rs, n) -> rs.getString(1), id, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
        String wanted = approve ? "APPROVED" : "DECLINED";
        if (wanted.equals(current)) { return job(user, id); }
        if (!"PENDING".equals(current)) {
            throw new ApiException(HttpStatus.CONFLICT, "NO_PRICE_PROPOSAL", "There is no price proposal to decide on");
        }
        db.update("update transactions.auto_jobs set price_approval = ?, final_price_minor = case when ? then final_price_minor else null end, updated_at = now(), "
                + "version = version + 1 where id = ?", wanted, approve, id);
        event(id, "IN_PROGRESS", "CUSTOMER", user, approve ? "PRICE_APPROVED" : "PRICE_DECLINED");
        return job(user, id);
    }

    // ---- specialist ----------------------------------------------------------------------------

    @Transactional
    public Profile register(UUID user, String name) {
        String clean = name == null ? "" : name.strip();
        if (clean.isEmpty() || clean.length() > 80) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "NAME_INVALID", "Name must be 1-80 characters");
        }
        db.update("insert into transactions.auto_specialists (user_id, display_name) values (?, ?) on conflict (user_id) do nothing", user, clean);
        Profile p = profile(user);
        if (!p.name().equals(clean)) {
            throw new ApiException(HttpStatus.CONFLICT, "SPECIALIST_PROFILE_EXISTS", "Specialist profile already exists");
        }
        return p;
    }

    @Transactional(readOnly = true)
    public Profile profile(UUID user) {
        var row = db.query("select display_name, status, online from transactions.auto_specialists where user_id = ?",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getBoolean(3)}, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SPECIALIST_NOT_FOUND", "Specialist profile not found"));
        return new Profile(user.toString(), (String) row[0], (String) row[1], (boolean) row[2], categories(user));
    }

    private List<String> categories(UUID user) {
        return db.queryForList("select category from transactions.auto_specialist_categories where user_id = ? order by category", String.class, user);
    }

    @Transactional
    public Profile availability(UUID user, boolean online) {
        Profile p = profile(user);
        if (online && !"APPROVED".equals(p.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "SPECIALIST_NOT_APPROVED", "Administrator approval is required");
        }
        db.update("update transactions.auto_specialists set online = ?, latitude = null, longitude = null, observed_at = null where user_id = ?", online, user);
        return profile(user);
    }

    @Transactional
    public void location(UUID user, BigDecimal lat, BigDecimal lon) {
        if (lat == null || lon == null || lat.abs().compareTo(BigDecimal.valueOf(90)) > 0 || lon.abs().compareTo(BigDecimal.valueOf(180)) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "LOCATION_INVALID", "Invalid coordinates");
        }
        if (db.update("update transactions.auto_specialists set latitude = ?, longitude = ?, observed_at = now() where user_id = ? and online and status = 'APPROVED'",
                lat, lon, user) == 0) {
            profile(user);
            throw new ApiException(HttpStatus.CONFLICT, "SPECIALIST_OFFLINE", "Go online first");
        }
    }

    /** Open requests of the specialist's approved categories within the radius; location and address are not disclosed yet. */
    @Transactional(readOnly = true)
    public List<SpecialistJob> available(UUID user) {
        Profile p = profile(user);
        if (!"APPROVED".equals(p.status()) || !p.online()) { return List.of(); }
        return db.query("""
                select * from (
                    select j.id, j.vehicle_label, j.category, j.description, j.price_minor, j.price_kind,
                           round(cast(6371 * acos(least(1, greatest(-1, cos(radians(s.latitude)) * cos(radians(j.latitude)) * cos(radians(j.longitude) - radians(s.longitude))
                               + sin(radians(s.latitude)) * sin(radians(j.latitude))))) as numeric), 1) as km
                    from transactions.auto_jobs j
                    join transactions.auto_specialists s on s.user_id = ?
                    join transactions.auto_specialist_categories c on c.user_id = s.user_id and c.category = j.category
                    where j.status = 'REQUESTED' and s.online and s.status = 'APPROVED' and s.latitude is not null and j.user_id <> s.user_id
                ) x where km <= ? order by km, id limit 20
                """, (rs, n) -> new SpecialistJob(rs.getString("id"), rs.getString("vehicle_label"), rs.getString("category"), rs.getString("description"), null,
                null, null, "REQUESTED", rs.getLong("price_minor"), rs.getString("price_kind"), null, null, rs.getDouble("km"), List.of("ACCEPT")),
                user, RADIUS_KM);
    }

    @Transactional
    public SpecialistJob accept(UUID user, UUID id) {
        requireEnabled();
        Profile p = profile(user);
        if (!"APPROVED".equals(p.status()) || !p.online()) {
            throw new ApiException(HttpStatus.CONFLICT, "SPECIALIST_NOT_AVAILABLE", "Approved and online specialist required");
        }
        var row = db.query("select status, category, specialist_id, user_id from transactions.auto_jobs where id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getObject(3, UUID.class), rs.getObject(4, UUID.class)}, id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
        if (user.equals(row[2]) && !"REQUESTED".equals(row[0])) { return specialistJob(user, id); } // idempotent repeat
        if (!"REQUESTED".equals(row[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "JOB_TAKEN", "The job is no longer available");
        }
        if (!p.categories().contains(row[1])) {
            throw new ApiException(HttpStatus.FORBIDDEN, "CATEGORY_NOT_PERMITTED", "You are not approved for this kind of work");
        }
        if (user.equals(row[3])) {
            throw new ApiException(HttpStatus.FORBIDDEN, "OWN_JOB", "You cannot take your own request");
        }
        Integer busy = db.queryForObject("select count(*) from transactions.auto_jobs where specialist_id = ? and status in " + ACTIVE, Integer.class, user);
        if (busy != null && busy > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "SPECIALIST_BUSY", "Finish your current job first");
        }
        try {
            db.update("update transactions.auto_jobs set status = 'ASSIGNED', specialist_id = ?, updated_at = now(), version = version + 1 where id = ?", user, id);
        } catch (DataIntegrityViolationException e) {
            if (e.getMostSpecificCause() instanceof SQLException sql && "23505".equals(sql.getSQLState())) {
                throw new ApiException(HttpStatus.CONFLICT, "SPECIALIST_BUSY", "Finish your current job first");
            }
            throw e;
        }
        event(id, "ASSIGNED", "SPECIALIST", user, null);
        return specialistJob(user, id);
    }

    @Transactional(readOnly = true)
    public List<SpecialistJob> mine(UUID user) {
        return db.queryForList("select id from transactions.auto_jobs where specialist_id = ? order by created_at desc limit 50", UUID.class, user)
                .stream().map(id -> specialistJob(user, id)).toList();
    }

    @Transactional(readOnly = true)
    public SpecialistJob specialistJob(UUID user, UUID id) {
        return db.query("""
                select id, vehicle_label, category, description, address_text, latitude, longitude, status, price_minor, price_kind, final_price_minor, price_approval
                from transactions.auto_jobs where id = ? and specialist_id = ?
                """, (rs, n) -> {
                    String status = rs.getString("status");
                    List<String> actions = new ArrayList<>();
                    switch (status) {
                        case "ASSIGNED" -> { actions.add("ARRIVE"); actions.add("RELEASE"); }
                        case "ARRIVED" -> actions.add("START");
                        case "IN_PROGRESS" -> {
                            if (!"FIXED".equals(rs.getString("price_kind"))) { actions.add("PROPOSE_PRICE"); }
                            if (!"PENDING".equals(rs.getString("price_approval"))) { actions.add("COMPLETE"); }
                        }
                        default -> { }
                    }
                    return new SpecialistJob(rs.getString("id"), rs.getString("vehicle_label"), rs.getString("category"), rs.getString("description"),
                            rs.getString("address_text"), rs.getBigDecimal("latitude"), rs.getBigDecimal("longitude"), status, rs.getLong("price_minor"),
                            rs.getString("price_kind"), rs.getObject("final_price_minor", Long.class), rs.getString("price_approval"), null, actions);
                }, id, user).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
    }

    @Transactional
    public SpecialistJob progress(UUID user, UUID id, Action action, Long finalPriceMinor) {
        var row = db.query("select status, price_kind, price_approval, price_minor from transactions.auto_jobs where id = ? and specialist_id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getString(3), rs.getLong(4)}, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "JOB_NOT_FOUND", "Job not found"));
        String status = (String) row[0];
        switch (action) {
            case ARRIVE -> {
                if ("ARRIVED".equals(status)) { break; }
                require("ASSIGNED".equals(status), action, status);
                move(id, "ARRIVED", user, null);
            }
            case START -> {
                if ("IN_PROGRESS".equals(status)) { break; }
                require("ARRIVED".equals(status), action, status);
                move(id, "IN_PROGRESS", user, null);
            }
            case PROPOSE_PRICE -> {
                require("IN_PROGRESS".equals(status) && !"FIXED".equals(row[1]), action, status);
                if (finalPriceMinor == null || finalPriceMinor < 0 || finalPriceMinor > 100_000_000_00L) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "PRICE_INVALID", "finalPriceMinor must be a non-negative amount in tiyn");
                }
                db.update("update transactions.auto_jobs set final_price_minor = ?, price_approval = 'PENDING', updated_at = now(), version = version + 1 where id = ?",
                        finalPriceMinor, id);
                event(id, "IN_PROGRESS", "SPECIALIST", user, "PRICE_PROPOSED");
            }
            case COMPLETE -> {
                if ("COMPLETED".equals(status)) { break; }
                require("IN_PROGRESS".equals(status), action, status);
                if ("PENDING".equals(row[2])) {
                    throw new ApiException(HttpStatus.CONFLICT, "PRICE_APPROVAL_PENDING", "The customer has not approved the final price yet");
                }
                // Without an approved proposal the job is closed at the tariff price; the final price is never invented.
                db.update("update transactions.auto_jobs set status = 'COMPLETED', final_price_minor = case when price_approval = 'APPROVED' then final_price_minor else price_minor end, "
                        + "updated_at = now(), version = version + 1 where id = ?", id);
                event(id, "COMPLETED", "SPECIALIST", user, null);
            }
            case RELEASE -> {
                if ("REQUESTED".equals(status)) { break; }
                require("ASSIGNED".equals(status), action, status);
                db.update("update transactions.auto_jobs set status = 'REQUESTED', specialist_id = null, updated_at = now(), version = version + 1 where id = ?", id);
                event(id, "REQUESTED", "SPECIALIST", user, "RELEASED");
            }
        }
        // after RELEASE the job no longer belongs to the specialist: return a minimal released view
        if (action == Action.RELEASE) {
            return new SpecialistJob(id.toString(), "", "", "", null, null, null, "REQUESTED", (long) row[3], (String) row[1], null, null, null, List.of());
        }
        return specialistJob(user, id);
    }

    // ---- admin ---------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<Reviewed> specialistsForReview(boolean includeReviewed) {
        return db.queryForList("select user_id from transactions.auto_specialists where ? or status = 'PENDING' order by (status = 'PENDING') desc, created_at limit 100",
                UUID.class, includeReviewed).stream().map(id -> {
                    Profile p = profile(id);
                    return new Reviewed(p.userId(), p.name(), p.status(), p.online(), p.categories());
                }).toList();
    }

    @Transactional
    public Reviewed review(UUID admin, UUID specialist, boolean approve, List<String> categories, String reason) {
        if (admin.equals(specialist)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "SELF_REVIEW", "Self review is forbidden");
        }
        String clean = reason == null ? "" : reason.strip();
        if (clean.isEmpty() || clean.length() > 200) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of 1-200 characters is required");
        }
        List<String> cats = approve && categories != null ? categories.stream().distinct().sorted().toList() : List.of();
        if (approve) {
            if (cats.isEmpty()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "CATEGORIES_REQUIRED", "Approve at least one on-site category");
            }
            for (String c : cats) {
                Integer ok = db.queryForObject("select count(*) from marketplace.auto_service_categories where code = ? and mobile", Integer.class, c);
                if (ok == null || ok == 0) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "CATEGORY_NOT_MOBILE", "Only on-site categories can be approved: " + c);
                }
            }
        }
        if (db.query("select 1 from transactions.auto_specialists where user_id = ? for update", (rs, n) -> 1, specialist).isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "SPECIALIST_NOT_FOUND", "Specialist profile not found");
        }
        db.update("update transactions.auto_specialists set status = ?, online = false, latitude = null, longitude = null, observed_at = null where user_id = ?",
                approve ? "APPROVED" : "BLOCKED", specialist);
        db.update("delete from transactions.auto_specialist_categories where user_id = ?", specialist);
        for (String c : cats) {
            db.update("insert into transactions.auto_specialist_categories (user_id, category) values (?, ?)", specialist, c);
        }
        db.update("insert into transactions.auto_specialist_reviews (specialist_id, reviewer_id, decision, categories, reason) values (?, ?, ?, ?, ?)",
                specialist, admin, approve ? "APPROVED" : "BLOCKED", String.join(",", cats), clean);
        Profile p = profile(specialist);
        return new Reviewed(p.userId(), p.name(), p.status(), p.online(), p.categories());
    }

    // ---- internals -----------------------------------------------------------------------------

    private void requireEnabled() {
        if (!props.enabled()) {
            throw new ApiException(HttpStatus.CONFLICT, "AUTO_DISABLED", "KUNDE Auto is not available right now");
        }
    }

    private static void require(boolean ok, Action action, String status) {
        if (!ok) {
            throw new ApiException(HttpStatus.CONFLICT, "JOB_TRANSITION_INVALID", action + " is not possible for a " + status + " job");
        }
    }

    private void move(UUID id, String to, UUID actor, String reason) {
        db.update("update transactions.auto_jobs set status = ?, updated_at = now(), version = version + 1 where id = ?", to, id);
        event(id, to, "SPECIALIST", actor, reason);
    }

    private void event(UUID id, String status, String actorType, UUID actor, String reason) {
        db.update("insert into transactions.auto_job_events (job_id, status, actor_type, actor_user_id, reason) values (?, ?, ?, ?, ?)", id, status, actorType, actor, reason);
    }

    private List<JobView> query(UUID user, UUID id) {
        List<JobView> base = db.query("""
                select j.id, j.vehicle_label, j.category, j.description, j.address_text, j.status, s.display_name, j.price_minor, j.price_kind,
                       j.final_price_minor, j.price_approval, (j.status in ('REQUESTED', 'ASSIGNED')) as cancellable, j.created_at
                from transactions.auto_jobs j left join transactions.auto_specialists s on s.user_id = j.specialist_id
                where j.user_id = ? and (?::uuid is null or j.id = ?::uuid) order by j.created_at desc, j.id limit 50
                """, (rs, n) -> new JobView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6),
                rs.getString(7), rs.getLong(8), rs.getString(9), rs.getObject(10, Long.class), rs.getString(11), rs.getBoolean(12),
                rs.getObject(13, OffsetDateTime.class), List.of()), user, id, id);
        List<JobView> out = new ArrayList<>();
        for (JobView j : base) {
            List<Timeline> t = db.query("select status, occurred_at, actor_type, reason from transactions.auto_job_events where job_id = ? order by id",
                    (rs, n) -> new Timeline(rs.getString(1), rs.getObject(2, OffsetDateTime.class), rs.getString(3), rs.getString(4)), UUID.fromString(j.id()));
            out.add(new JobView(j.id(), j.vehicle(), j.category(), j.description(), j.addressText(), j.status(), j.specialist(), j.priceMinor(), j.priceKind(),
                    j.finalPriceMinor(), j.priceApproval(), j.cancellable(), j.createdAt(), t));
        }
        return out;
    }
}
