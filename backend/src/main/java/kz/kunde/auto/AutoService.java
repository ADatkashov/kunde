package kz.kunde.auto;

import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.Year;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.regex.Pattern;
import kz.kunde.booking.BookingSlots;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Consumer side of KUNDE Auto on top of the Booking engine: vehicles, server-side quotes, idempotent booking,
 * reschedule, cancellation and customer price approval. The slot list stays the single source of truth (the same
 * {@link BookingSlots} as every other booking), a database exclusion constraint prevents double booking of a post and a
 * per-post advisory lock serialises bookings so the venue buffer between visits is enforced too.
 * New quotes and bookings are refused while {@code app.auto.enabled=false}; reading, cancelling and the customer's price
 * decision for already created bookings keep working so they can be completed or cancelled.
 */
@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class AutoService {
    private static final Pattern KEY = Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final Pattern PLATE = Pattern.compile("^[A-Z0-9]{3,12}$");
    private static final int MAX_VEHICLES = 5;
    private static final int MAX_UPCOMING = 5;
    private static final int QUOTE_MINUTES = 10;
    private static final int FREE_CANCEL_HOURS = 2;
    private static final int MIN_RESCHEDULE_HOURS = 2;
    private static final int MAX_RESCHEDULES = 2;
    public static final String CANCELLATION_TERMS =
            "Free cancellation until the start; a cancellation less than 2 hours before the start is marked as late. No payment is taken.";

    public record VehicleRequest(String make, String model, Integer year, String plate) {}

    public record Vehicle(String id, String make, String model, int year, String plate, long version) {}

    public record QuoteRequest(UUID venueId, UUID serviceId, UUID vehicleId, OffsetDateTime startsAt) {}

    public record Quote(String id, String venueId, String serviceId, String vehicleId, OffsetDateTime startsAt, int durationMinutes,
            long priceMinor, String currency, String priceKind, OffsetDateTime expiresAt, String cancellationTerms) {}

    public record TimelineEntry(String status, OffsetDateTime at, String actor, String reason) {}

    public record AutoBooking(String id, String venueId, String venueName, String venueAddress, String serviceName,
            int durationMinutes, String vehicleId, String vehicle, OffsetDateTime startsAt, OffsetDateTime endsAt,
            long priceMinor, String priceKind, Long finalPriceMinor, String priceApproval, String currency, String status,
            boolean cancellable, boolean reschedulable, int rescheduleCount, OffsetDateTime createdAt, String cancelledBy,
            String cancelReason, List<TimelineEntry> timeline, String serviceId, AutoPayments.PaymentView payment) {}

    public record Booked(AutoBooking booking, boolean created) {}

    private final JdbcTemplate db;
    private final BookingSlots slots;
    private final AutoProperties props;
    private final AutoPayments payments;

    public AutoService(JdbcTemplate db, BookingSlots slots, AutoProperties props, AutoPayments payments) {
        this.db = db;
        this.slots = slots;
        this.props = props;
        this.payments = payments;
    }

    // ---- vehicles ------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<Vehicle> vehicles(UUID user) {
        return db.query("select id, make, model, production_year, plate, version from transactions.customer_vehicles "
                + "where user_id = ? and not archived order by created_at, id", AutoService::vehicle, user);
    }

    @Transactional
    public Vehicle addVehicle(UUID user, VehicleRequest r) {
        Clean c = clean(r);
        lockUser(user);
        Integer count = db.queryForObject("select count(*) from transactions.customer_vehicles where user_id = ? and not archived", Integer.class, user);
        if (count != null && count >= MAX_VEHICLES) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_VEHICLES", "At most " + MAX_VEHICLES + " vehicles");
        }
        UUID id = db.queryForObject("insert into transactions.customer_vehicles (user_id, make, model, production_year, plate) "
                + "values (?, ?, ?, ?, ?) returning id", UUID.class, user, c.make, c.model, c.year, c.plate);
        return vehicle(user, id);
    }

    @Transactional
    public Vehicle updateVehicle(UUID user, UUID id, VehicleRequest r, long version) {
        Clean c = clean(r);
        int n = db.update("update transactions.customer_vehicles set make = ?, model = ?, production_year = ?, plate = ?, version = version + 1 "
                + "where id = ? and user_id = ? and not archived and version = ?", c.make, c.model, c.year, c.plate, id, user, version);
        if (n == 0) {
            vehicle(user, id); // 404 for a stranger's or archived vehicle
            throw new ApiException(HttpStatus.CONFLICT, "VEHICLE_VERSION_CONFLICT", "Reload the vehicle and retry");
        }
        return vehicle(user, id);
    }

    /** Archived, not deleted: bookings keep their vehicle label and the history stays intact. */
    @Transactional
    public void archiveVehicle(UUID user, UUID id) {
        if (db.update("update transactions.customer_vehicles set archived = true, version = version + 1 where id = ? and user_id = ? and not archived", id, user) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VEHICLE_NOT_FOUND", "Vehicle not found");
        }
    }

    private Vehicle vehicle(UUID user, UUID id) {
        return db.query("select id, make, model, production_year, plate, version from transactions.customer_vehicles "
                + "where id = ? and user_id = ? and not archived", AutoService::vehicle, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VEHICLE_NOT_FOUND", "Vehicle not found"));
    }

    private static Vehicle vehicle(java.sql.ResultSet rs, int n) throws SQLException {
        return new Vehicle(rs.getString(1), rs.getString(2), rs.getString(3), rs.getInt(4), rs.getString(5), rs.getLong(6));
    }

    private record Clean(String make, String model, int year, String plate) {}

    private static Clean clean(VehicleRequest r) {
        String make = r.make() == null ? "" : r.make().strip();
        String model = r.model() == null ? "" : r.model().strip();
        if (make.isEmpty() || make.length() > 40 || model.isEmpty() || model.length() > 40) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_INVALID", "Make and model are required (up to 40 characters)");
        }
        if (r.year() == null || r.year() < 1950 || r.year() > Year.now().getValue() + 1) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_YEAR_INVALID", "Year must be between 1950 and next year");
        }
        String plate = null;
        if (r.plate() != null && !r.plate().isBlank()) {
            plate = r.plate().replaceAll("[\\s-]", "").toUpperCase(Locale.ROOT);
            if (!PLATE.matcher(plate).matches()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "PLATE_INVALID", "Plate must be 3-12 letters or digits (optional)");
            }
        }
        return new Clean(make, model, r.year(), plate);
    }

    // ---- quote ---------------------------------------------------------------------------------

    @Transactional
    public Quote quote(UUID user, QuoteRequest r) {
        requireEnabled();
        if (r.venueId() == null || r.serviceId() == null || r.vehicleId() == null || r.startsAt() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "QUOTE_INVALID", "venueId, serviceId, vehicleId and startsAt are required");
        }
        Vehicle vehicle = vehicle(user, r.vehicleId());
        var venue = slots.venue(r.venueId());
        if (!"AUTO".equals(venue.category())) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue is not available");
        }
        var service = slots.service(r.venueId(), r.serviceId());
        var meta = db.query("select s.auto_category, s.price_kind, c.enabled from marketplace.booking_services s "
                + "left join marketplace.auto_service_categories c on c.code = s.auto_category where s.id = ?",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getObject(3, Boolean.class)}, r.serviceId()).get(0);
        if (meta[0] == null || !Boolean.TRUE.equals(meta[2])) {
            throw new ApiException(HttpStatus.CONFLICT, "AUTO_CATEGORY_DISABLED", "This kind of service is temporarily unavailable");
        }
        Instant start = r.startsAt().toInstant();
        var offered = slots.freeSlots(r.venueId(), r.serviceId(), null, start.atZone(venue.zone()).toLocalDate()).stream()
                .filter(s -> s.startsAt().toInstant().equals(start)).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.CONFLICT, "SLOT_UNAVAILABLE", "This time is no longer available"));
        // The price comes from the server's own service record only: the request carries no price at all.
        OffsetDateTime expires = OffsetDateTime.now().plusMinutes(QUOTE_MINUTES);
        UUID id = db.queryForObject("""
                insert into transactions.auto_quotes (user_id, venue_id, service_id, vehicle_id, master_id, starts_at, duration_minutes,
                    price_minor, price_kind, expires_at) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                """, UUID.class, user, r.venueId(), r.serviceId(), vehicle.id() == null ? null : UUID.fromString(vehicle.id()),
                UUID.fromString(offered.masterId()), Timestamp.from(start), service.durationMinutes(), service.priceMinor(),
                meta[1], Timestamp.from(expires.toInstant()));
        return new Quote(id.toString(), r.venueId().toString(), r.serviceId().toString(), r.vehicleId().toString(),
                start.atZone(venue.zone()).toOffsetDateTime(), service.durationMinutes(), service.priceMinor(), "KZT",
                (String) meta[1], expires, CANCELLATION_TERMS);
    }

    // ---- book ----------------------------------------------------------------------------------

    @Transactional
    public Booked book(UUID user, UUID quoteId, String idempotencyKey) {
        return book(user, quoteId, idempotencyKey, null);
    }

    @Transactional
    public Booked book(UUID user, UUID quoteId, String idempotencyKey, String paymentMethod) {
        if (idempotencyKey == null || !KEY.matcher(idempotencyKey).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_INVALID",
                    "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }
        lockUser(user);
        var existing = db.query("select id, vehicle_id, starts_at from transactions.bookings where user_id = ? and idempotency_key = ?",
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class)}, user, idempotencyKey).stream().findFirst();
        if (existing.isPresent()) {
            UUID same = db.query("select id from transactions.auto_quotes where id = ? and user_id = ? and consumed_at is not null",
                    (rs, n) -> rs.getObject(1, UUID.class), quoteId, user).stream().findFirst().orElse(null);
            Integer matches = db.queryForObject("select count(*) from transactions.bookings b join transactions.auto_quotes q "
                    + "on q.vehicle_id = b.vehicle_id and q.starts_at = b.starts_at and q.service_id = b.service_id "
                    + "where b.id = ? and q.id = ?", Integer.class, existing.get()[0], quoteId);
            if (same == null || matches == null || matches == 0) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "Idempotency-Key was already used for a different booking");
            }
            return new Booked(view(user, (UUID) existing.get()[0]), false);
        }
        requireEnabled();
        String method = payments.method(paymentMethod);
        var q = db.query("""
                select venue_id, service_id, vehicle_id, master_id, starts_at, duration_minutes, price_minor, price_kind,
                       expires_at > now(), consumed_at is not null
                from transactions.auto_quotes where id = ? and user_id = ? for update
                """, (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                rs.getObject(4, UUID.class), rs.getTimestamp(5).toInstant(), rs.getInt(6), rs.getLong(7), rs.getString(8),
                rs.getBoolean(9), rs.getBoolean(10)}, quoteId, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "QUOTE_NOT_FOUND", "Quote not found"));
        if ((boolean) q[9]) {
            throw new ApiException(HttpStatus.CONFLICT, "QUOTE_USED", "This quote was already used");
        }
        if (!(boolean) q[8]) {
            throw new ApiException(HttpStatus.CONFLICT, "QUOTE_EXPIRED", "The quote expired, request a new one");
        }
        UUID venueId = (UUID) q[0];
        UUID serviceId = (UUID) q[1];
        UUID vehicleId = (UUID) q[2];
        UUID masterId = (UUID) q[3];
        Instant start = (Instant) q[4];
        Vehicle vehicle = vehicle(user, vehicleId);
        var venue = slots.venue(venueId);
        var service = slots.service(venueId, serviceId);
        if (service.priceMinor() != (long) q[6] || service.durationMinutes() != (int) q[5]) {
            throw new ApiException(HttpStatus.CONFLICT, "QUOTE_STALE", "The price or duration changed, request a new quote");
        }
        Integer categoryOn = db.queryForObject("select count(*) from marketplace.booking_services s join marketplace.auto_service_categories c "
                + "on c.code = s.auto_category where s.id = ? and c.enabled", Integer.class, serviceId);
        if (categoryOn == null || categoryOn == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "AUTO_CATEGORY_DISABLED", "This kind of service is temporarily unavailable");
        }
        // Serialise bookings of one post so the buffer between visits is checked against a stable view.
        db.query("select pg_advisory_xact_lock(hashtext('auto-post'), hashtext(?))", (RowCallbackHandler) rs -> {}, masterId.toString());
        boolean offered = slots.freeSlots(venueId, serviceId, masterId, start.atZone(venue.zone()).toLocalDate()).stream()
                .anyMatch(s -> s.startsAt().toInstant().equals(start));
        if (!offered) {
            throw new ApiException(HttpStatus.CONFLICT, "SLOT_TAKEN", "This time was just booked by someone else");
        }
        Instant end = start.plusSeconds((int) q[5] * 60L);
        Integer upcoming = db.queryForObject("select count(*) from transactions.bookings where user_id = ? and status in "
                + "('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS') and ends_at > now()", Integer.class, user);
        if (upcoming != null && upcoming >= MAX_UPCOMING) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_UPCOMING_BOOKINGS", "Too many upcoming bookings");
        }
        Integer vehicleBusy = db.queryForObject("select count(*) from transactions.bookings where vehicle_id = ? and status in "
                + "('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS') and starts_at < ? and ends_at > ?", Integer.class,
                vehicleId, Timestamp.from(end), Timestamp.from(start));
        if (vehicleBusy != null && vehicleBusy > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "VEHICLE_ALREADY_BOOKED", "This vehicle already has a booking at this time");
        }
        String master = db.queryForObject("select name from marketplace.booking_masters where id = ? for share", String.class, masterId);
        boolean partnerManaged = Boolean.TRUE.equals(db.queryForObject(
                "select partner_id is not null from marketplace.booking_venues where id = ?", Boolean.class, venueId));
        String label = vehicle.make() + " " + vehicle.model() + " " + vehicle.year() + (vehicle.plate() == null ? "" : " " + vehicle.plate());
        try {
            UUID id = db.queryForObject("""
                    insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address, service_name,
                        master_name, duration_minutes, starts_at, ends_at, price_minor, idempotency_key, category, status, confirmation,
                        vehicle_id, vehicle_label, price_kind)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'AUTO', ?, ?, ?, ?, ?) returning id
                    """, UUID.class, user, venueId, serviceId, masterId, venue.name(), venue.address(), service.name(), master,
                    (int) q[5], Timestamp.from(start), Timestamp.from(end), (long) q[6], idempotencyKey,
                    partnerManaged ? "PENDING" : "CONFIRMED", partnerManaged ? "PARTNER" : "DEV_MOCK", vehicleId, label, q[7]);
            db.update("update transactions.auto_quotes set consumed_at = now() where id = ?", quoteId);
            payments.open(user, id, null, method, (long) q[6]);
            event(id, partnerManaged ? "PENDING" : "CONFIRMED", partnerManaged ? "CUSTOMER" : "SYSTEM", user, null);
            return new Booked(view(user, id), true);
        } catch (DataIntegrityViolationException conflict) {
            if (conflict.getMostSpecificCause() instanceof SQLException sql && "23P01".equals(sql.getSQLState())) {
                throw new ApiException(HttpStatus.CONFLICT, "SLOT_TAKEN", "This time was just booked by someone else");
            }
            throw conflict;
        }
    }

    // ---- read / cancel / reschedule / price ----------------------------------------------------

    @Transactional
    public List<AutoBooking> list(UUID user, int limit, int offset) {
        expire(user);
        return query(user, null, limit, offset);
    }

    @Transactional
    public AutoBooking get(UUID user, UUID id) {
        expire(user);
        return view(user, id);
    }

    @Transactional
    public AutoBooking cancel(UUID user, UUID id) {
        var row = db.query("select status, starts_at > now(), starts_at > now() + make_interval(hours => ?) from transactions.bookings "
                + "where id = ? and user_id = ? and category = 'AUTO' for update", (rs, n) -> new Object[] {rs.getString(1), rs.getBoolean(2), rs.getBoolean(3)},
                FREE_CANCEL_HOURS, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        if ("CANCELLED".equals(row[0])) {
            return view(user, id); // idempotent
        }
        if (!("PENDING".equals(row[0]) || "CONFIRMED".equals(row[0])) || !(boolean) row[1]) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_CANCELLABLE", "Only an upcoming pending or confirmed booking can be cancelled");
        }
        String reason = (boolean) row[2] ? null : "LATE_CANCEL";
        db.update("update transactions.bookings set status = 'CANCELLED', cancelled_at = now(), cancelled_by = 'CUSTOMER', cancel_reason = ?, "
                + "updated_at = now(), version = version + 1 where id = ?", reason, id);
        event(id, "CANCELLED", "CUSTOMER", user, reason);
        payments.voidHold(id, null, "CUSTOMER", user, "CANCELLED");
        return view(user, id);
    }

    /** Moves the booking to another free time (any post). Allowed at least 2 hours before the start, at most twice. */
    @Transactional
    public AutoBooking reschedule(UUID user, UUID id, OffsetDateTime startsAt) {
        requireEnabled();
        if (startsAt == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "STARTS_AT_REQUIRED", "startsAt is required");
        }
        var b = db.query("""
                select venue_id, service_id, duration_minutes, status, starts_at > now() + make_interval(hours => ?), reschedule_count, master_id,
                       (select partner_id is not null from marketplace.booking_venues v where v.id = venue_id)
                from transactions.bookings where id = ? and user_id = ? and category = 'AUTO' for update
                """, (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getInt(3), rs.getString(4),
                rs.getBoolean(5), rs.getInt(6), rs.getObject(7, UUID.class), rs.getBoolean(8)}, MIN_RESCHEDULE_HOURS, id, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        if (!("PENDING".equals(b[3]) || "CONFIRMED".equals(b[3])) || !(boolean) b[4]) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_RESCHEDULABLE",
                    "Only a pending or confirmed booking more than " + MIN_RESCHEDULE_HOURS + " hours before the start can be moved");
        }
        if ((int) b[5] >= MAX_RESCHEDULES) {
            throw new ApiException(HttpStatus.CONFLICT, "RESCHEDULE_LIMIT", "A booking can be moved at most " + MAX_RESCHEDULES + " times");
        }
        UUID venueId = (UUID) b[0];
        UUID serviceId = (UUID) b[1];
        var venue = slots.venue(venueId);
        Instant start = startsAt.toInstant();
        LocalDate date = start.atZone(venue.zone()).toLocalDate();
        // Candidate posts are tried in the engine's order; the booking's own current time does not block itself.
        BookingSlots.Slot offered = slots.freeSlots(venueId, serviceId, null, date, id).stream()
                .filter(s -> s.startsAt().toInstant().equals(start)).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.CONFLICT, "SLOT_UNAVAILABLE", "This time is not available"));
        UUID master = UUID.fromString(offered.masterId());
        db.query("select pg_advisory_xact_lock(hashtext('auto-post'), hashtext(?))", (RowCallbackHandler) rs -> {}, master.toString());
        if (slots.freeSlots(venueId, serviceId, master, date, id).stream().noneMatch(s -> s.startsAt().toInstant().equals(start))) {
            throw new ApiException(HttpStatus.CONFLICT, "SLOT_TAKEN", "This time was just booked by someone else");
        }
        Instant end = start.plusSeconds((int) b[2] * 60L);
        Integer vehicleBusy = db.queryForObject("select count(*) from transactions.bookings where vehicle_id = (select vehicle_id from transactions.bookings where id = ?) "
                + "and id <> ? and status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS') and starts_at < ? and ends_at > ?", Integer.class,
                id, id, Timestamp.from(end), Timestamp.from(start));
        if (vehicleBusy != null && vehicleBusy > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "VEHICLE_ALREADY_BOOKED", "This vehicle already has a booking at this time");
        }
        String masterName = db.queryForObject("select name from marketplace.booking_masters where id = ? for share", String.class, master);
        boolean partnerManaged = (boolean) b[7];
        try {
            db.update("""
                    update transactions.bookings set master_id = ?, master_name = ?, starts_at = ?, ends_at = ?, status = ?, confirmation = ?,
                        reschedule_count = reschedule_count + 1, updated_at = now(), version = version + 1 where id = ?
                    """, master, masterName, Timestamp.from(start), Timestamp.from(end), partnerManaged ? "PENDING" : "CONFIRMED",
                    partnerManaged ? "PARTNER" : "DEV_MOCK", id);
        } catch (DataIntegrityViolationException conflict) {
            if (conflict.getMostSpecificCause() instanceof SQLException sql && "23P01".equals(sql.getSQLState())) {
                throw new ApiException(HttpStatus.CONFLICT, "SLOT_TAKEN", "This time was just booked by someone else");
            }
            throw conflict;
        }
        event(id, "RESCHEDULED", "CUSTOMER", user, null);
        if (partnerManaged) { event(id, "PENDING", "SYSTEM", null, "RESCHEDULED"); }
        return view(user, id);
    }

    /** The customer's decision on the price a partner proposed after inspection (FROM / DIAGNOSTIC services). */
    @Transactional
    public AutoBooking decidePrice(UUID user, UUID id, boolean approve) {
        var row = db.query("select price_approval from transactions.bookings where id = ? and user_id = ? and category = 'AUTO' for update",
                (rs, n) -> new Object[] {rs.getString(1)}, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        String current = (String) row[0];
        String wanted = approve ? "APPROVED" : "DECLINED";
        if (wanted.equals(current)) {
            return view(user, id);
        }
        if (!"PENDING".equals(current)) {
            throw new ApiException(HttpStatus.CONFLICT, "NO_PRICE_PROPOSAL", "There is no price proposal to decide on");
        }
        db.update("update transactions.bookings set price_approval = ?, final_price_minor = case when ? then final_price_minor else null end, "
                + "updated_at = now(), version = version + 1 where id = ?", wanted, approve, id);
        event(id, "IN_PROGRESS", "CUSTOMER", user, approve ? "PRICE_APPROVED" : "PRICE_DECLINED");
        return view(user, id);
    }

    // ---- internals -----------------------------------------------------------------------------

    /** Feature flag: no new quote, booking or move while Auto is off; reads, cancellation and price decisions keep working. */
    private void requireEnabled() {
        if (!props.enabled()) {
            throw new ApiException(HttpStatus.CONFLICT, "AUTO_DISABLED", "KUNDE Auto is not available right now");
        }
    }

    private void lockUser(UUID user) {
        db.query("select pg_advisory_xact_lock(hashtext('auto'), hashtext(?))", (RowCallbackHandler) rs -> {}, user.toString());
    }

    /** A request nobody answered before the start expires; an unattended confirmed visit is left for the partner to close. */
    private void expire(UUID user) {
        for (UUID id : db.queryForList("select id from transactions.bookings where user_id = ? and category = 'AUTO' and status = 'PENDING' "
                + "and starts_at <= now() for update", UUID.class, user)) {
            db.update("update transactions.bookings set status = 'CANCELLED', cancelled_at = now(), cancelled_by = 'SYSTEM', "
                    + "cancel_reason = 'NOT_ANSWERED', updated_at = now(), version = version + 1 where id = ?", id);
            event(id, "CANCELLED", "SYSTEM", null, "NOT_ANSWERED");
            payments.voidHold(id, null, "SYSTEM", null, "NOT_ANSWERED");
        }
    }

    private void event(UUID id, String status, String actorType, UUID actor, String reason) {
        db.update("insert into transactions.booking_events (booking_id, status, actor_type, actor_user_id, reason) values (?, ?, ?, ?, ?)",
                id, status, actorType, actor, reason);
    }

    private AutoBooking view(UUID user, UUID id) {
        return query(user, id, 1, 0).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
    }

    private List<AutoBooking> query(UUID user, UUID id, int limit, int offset) {
        List<AutoBooking> rows = db.query("""
                select id, venue_id, venue_name, venue_address, service_name, duration_minutes, vehicle_id, service_id, vehicle_label, starts_at, ends_at,
                       price_minor, price_kind, final_price_minor, price_approval, currency, status,
                       (status in ('PENDING', 'CONFIRMED') and starts_at > now()) as cancellable,
                       (status in ('PENDING', 'CONFIRMED') and starts_at > now() + make_interval(hours => ?) and reschedule_count < ?) as reschedulable,
                       reschedule_count, created_at, cancelled_by, cancel_reason
                from transactions.bookings where user_id = ? and category = 'AUTO' and (?::uuid is null or id = ?::uuid)
                order by starts_at desc, id limit ? offset ?
                """, (rs, n) -> new AutoBooking(rs.getString("id"), rs.getString("venue_id"), rs.getString("venue_name"),
                rs.getString("venue_address"), rs.getString("service_name"), rs.getInt("duration_minutes"), rs.getString("vehicle_id"),
                rs.getString("vehicle_label"), rs.getObject("starts_at", OffsetDateTime.class), rs.getObject("ends_at", OffsetDateTime.class),
                rs.getLong("price_minor"), rs.getString("price_kind"), rs.getObject("final_price_minor", Long.class), rs.getString("price_approval"),
                rs.getString("currency"), rs.getString("status"), rs.getBoolean("cancellable"), rs.getBoolean("reschedulable"),
                rs.getInt("reschedule_count"), rs.getObject("created_at", OffsetDateTime.class), rs.getString("cancelled_by"),
                rs.getString("cancel_reason"), List.of(), rs.getString("service_id"), null), MIN_RESCHEDULE_HOURS, MAX_RESCHEDULES, user, id, id, limit, offset);
        List<AutoBooking> out = new ArrayList<>();
        for (AutoBooking b : rows) {
            List<TimelineEntry> timeline = db.query("select status, occurred_at, actor_type, reason from transactions.booking_events where booking_id = ? order by id",
                    (rs, n) -> new TimelineEntry(rs.getString(1), rs.getObject(2, OffsetDateTime.class), rs.getString(3), rs.getString(4)),
                    UUID.fromString(b.id()));
            out.add(new AutoBooking(b.id(), b.venueId(), b.venueName(), b.venueAddress(), b.serviceName(), b.durationMinutes(), b.vehicleId(),
                    b.vehicle(), b.startsAt(), b.endsAt(), b.priceMinor(), b.priceKind(), b.finalPriceMinor(), b.priceApproval(), b.currency(),
                    b.status(), b.cancellable(), b.reschedulable(), b.rescheduleCount(), b.createdAt(), b.cancelledBy(), b.cancelReason(), timeline, b.serviceId(), payments.ofBooking(UUID.fromString(b.id()))));
        }
        return out;
    }
}
