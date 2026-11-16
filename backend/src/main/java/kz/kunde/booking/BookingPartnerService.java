package kz.kunde.booking;

import java.sql.Timestamp;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Partner operations for bookings: incoming requests of the partner's own venues, confirm/reject/cancel/complete,
 * and availability (venue open, services, masters, weekly hours). Same discipline as the Food partner service:
 * membership first (404 for strangers), rows only of the partner's own venues, row-locked and idempotent transitions,
 * append-only audit. Double booking stays impossible: the database exclusion constraint also covers PENDING requests,
 * and a schedule change that would strand an existing booking is refused.
 */
@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BookingPartnerService {
    public enum Action { CONFIRM, REJECT, CANCEL, COMPLETE }

    public record TimelineEntry(String status, OffsetDateTime at, String actor, String reason) {}

    public record PartnerBooking(String id, String venueId, String venueName, String category, String serviceName,
            int durationMinutes, String masterId, String masterName, OffsetDateTime startsAt, OffsetDateTime endsAt,
            long priceMinor, String currency, String status, String comment, String addressText, Integer areaSqm,
            String customerRef, OffsetDateTime createdAt, String cancelledBy, String cancelReason,
            List<String> allowedActions, List<TimelineEntry> timeline) {}

    public record VenueView(String id, String name, String category, boolean open) {}

    public record ServiceView(String id, String name, int durationMinutes, long priceMinor, boolean available) {}

    public record HoursView(int day, String from, String to, String breakFrom, String breakTo) {}

    public record MasterView(String id, String name, boolean active, List<HoursView> hours) {}

    private final JdbcTemplate db;
    private final BookingService bookings;
    private final PartnerService partners;

    public BookingPartnerService(JdbcTemplate db, BookingService bookings, PartnerService partners) {
        this.db = db;
        this.bookings = bookings;
        this.partners = partners;
    }

    // ---- bookings ------------------------------------------------------------------------------

    /** {@code scope}: requests (PENDING), upcoming (CONFIRMED, not yet over) or history (everything else). */
    @Transactional
    public List<PartnerBooking> list(UUID actor, UUID partnerId, String scope, int limit, int offset) {
        partners.requireProcessing(actor, partnerId);
        bookings.completeDue("venue_id in (select id from marketplace.booking_venues where partner_id = ?)", partnerId);
        String where = switch (scope) {
            case "requests" -> "b.status = 'PENDING'";
            case "upcoming" -> "b.status = 'CONFIRMED'";
            default -> "b.status in ('CANCELLED', 'COMPLETED')";
        };
        String order = "history".equals(scope) ? "b.starts_at desc" : "b.starts_at asc";
        List<UUID> ids = db.queryForList("select b.id from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id "
                + "where v.partner_id = ? and " + where + " order by " + order + ", b.id limit ? offset ?", UUID.class,
                partnerId, limit, offset);
        return load(ids);
    }

    @Transactional
    public PartnerBooking get(UUID actor, UUID partnerId, UUID bookingId) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedBooking(partnerId, bookingId);
        bookings.completeDue("id = ?", bookingId);
        return load(List.of(bookingId)).get(0);
    }

    @Transactional
    public PartnerBooking act(UUID actor, UUID partnerId, UUID bookingId, Action action, String reason) {
        partners.requireProcessing(actor, partnerId);
        var row = db.query("""
                select b.status, b.starts_at > now(), b.cancelled_by from transactions.bookings b
                join marketplace.booking_venues v on v.id = b.venue_id
                where b.id = ? and v.partner_id = ? for update of b
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getBoolean(2), rs.getString(3)}, bookingId, partnerId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        String status = (String) row[0];
        boolean future = (boolean) row[1];
        String clean = reason == null || reason.isBlank() ? null : reason.strip();
        if ((action == Action.REJECT || action == Action.CANCEL) && (clean == null || clean.length() < 3 || clean.length() > 300)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of 3-300 characters is required");
        }
        switch (action) {
            case CONFIRM -> {
                if ("CONFIRMED".equals(status)) { break; }
                require("PENDING".equals(status) && future, action, status);
                db.update("update transactions.bookings set status = 'CONFIRMED', confirmation = 'PARTNER', updated_at = now(), version = version + 1 where id = ?", bookingId);
                bookings.event(bookingId, "CONFIRMED", "PARTNER", actor, null);
            }
            case REJECT -> {
                if ("CANCELLED".equals(status) && "PARTNER".equals(row[2])) { break; }
                require("PENDING".equals(status), action, status);
                cancel(bookingId, actor, clean);
            }
            case CANCEL -> {
                if ("CANCELLED".equals(status) && "PARTNER".equals(row[2])) { break; }
                require("CONFIRMED".equals(status) && future, action, status);
                cancel(bookingId, actor, clean);
            }
            case COMPLETE -> {
                if ("COMPLETED".equals(status)) { break; }
                require("CONFIRMED".equals(status) && !future, action, status);
                db.update("update transactions.bookings set status = 'COMPLETED', updated_at = now(), version = version + 1 where id = ?", bookingId);
                bookings.event(bookingId, "COMPLETED", "PARTNER", actor, null);
            }
        }
        return load(List.of(bookingId)).get(0);
    }

    private void cancel(UUID bookingId, UUID actor, String reason) {
        db.update("""
                update transactions.bookings set status = 'CANCELLED', cancelled_at = now(), cancelled_by = 'PARTNER',
                    cancel_reason = ?, updated_at = now(), version = version + 1 where id = ?
                """, reason, bookingId);
        bookings.event(bookingId, "CANCELLED", "PARTNER", actor, reason);
    }

    private static void require(boolean allowed, Action action, String status) {
        if (!allowed) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_TRANSITION_INVALID",
                    action + " is not possible for a " + status + " booking");
        }
    }

    // ---- availability --------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<VenueView> venues(UUID actor, UUID partnerId) {
        partners.requireProcessing(actor, partnerId);
        return db.query("select id, name, category, is_open from marketplace.booking_venues where partner_id = ? order by sort_order, name",
                (rs, n) -> new VenueView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getBoolean(4)), partnerId);
    }

    @Transactional
    public VenueView setVenueOpen(UUID actor, UUID partnerId, UUID venueId, boolean open) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        Boolean previous = db.query("select is_open from marketplace.booking_venues where id = ? and partner_id = ? for update",
                (rs, n) -> rs.getBoolean(1), venueId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found"));
        if (previous != open) {
            db.update("update marketplace.booking_venues set is_open = ? where id = ?", open, venueId);
            audit(partnerId, actor, "VENUE", venueId, "open", String.valueOf(previous), String.valueOf(open));
        }
        return venues(actor, partnerId).stream().filter(v -> v.id().equals(venueId.toString())).findFirst().orElseThrow();
    }

    @Transactional(readOnly = true)
    public List<ServiceView> services(UUID actor, UUID partnerId, UUID venueId) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedVenue(partnerId, venueId);
        return db.query("select id, name, duration_minutes, price_minor, available from marketplace.booking_services where venue_id = ? order by sort_order, name",
                (rs, n) -> new ServiceView(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getLong(4), rs.getBoolean(5)), venueId);
    }

    @Transactional
    public ServiceView setServiceAvailable(UUID actor, UUID partnerId, UUID venueId, UUID serviceId, boolean available) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedVenue(partnerId, venueId);
        Boolean previous = db.query("select available from marketplace.booking_services where id = ? and venue_id = ? for update",
                (rs, n) -> rs.getBoolean(1), serviceId, venueId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SERVICE_NOT_FOUND", "Service not found"));
        if (previous != available) {
            db.update("update marketplace.booking_services set available = ? where id = ?", available, serviceId);
            audit(partnerId, actor, "SERVICE", serviceId, "available", String.valueOf(previous), String.valueOf(available));
        }
        return services(actor, partnerId, venueId).stream().filter(s -> s.id().equals(serviceId.toString())).findFirst().orElseThrow();
    }

    @Transactional(readOnly = true)
    public List<MasterView> masters(UUID actor, UUID partnerId, UUID venueId) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedVenue(partnerId, venueId);
        List<MasterView> out = new ArrayList<>();
        db.query("select id, name, active from marketplace.booking_masters where venue_id = ? order by sort_order, name", rs -> {
            UUID id = rs.getObject(1, UUID.class);
            out.add(new MasterView(id.toString(), rs.getString(2), rs.getBoolean(3), hours(id)));
        }, venueId);
        return out;
    }

    private List<HoursView> hours(UUID masterId) {
        return db.query("""
                select weekday, start_time, end_time, break_start, break_end from marketplace.booking_working_hours
                where master_id = ? order by weekday
                """, (rs, n) -> new HoursView(rs.getInt(1), rs.getString(2).substring(0, 5), rs.getString(3).substring(0, 5),
                rs.getString(4) == null ? null : rs.getString(4).substring(0, 5),
                rs.getString(5) == null ? null : rs.getString(5).substring(0, 5)), masterId);
    }

    @Transactional
    public MasterView setMasterActive(UUID actor, UUID partnerId, UUID venueId, UUID masterId, boolean active) {
        partners.requireProcessing(actor, partnerId);
        requireOwnedVenue(partnerId, venueId);
        Boolean previous = db.query("select active from marketplace.booking_masters where id = ? and venue_id = ? for update",
                (rs, n) -> rs.getBoolean(1), masterId, venueId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "MASTER_NOT_FOUND", "Master not found"));
        if (previous != active) {
            db.update("update marketplace.booking_masters set active = ? where id = ?", active, masterId);
            audit(partnerId, actor, "MASTER", masterId, "active", String.valueOf(previous), String.valueOf(active));
        }
        return masters(actor, partnerId, venueId).stream().filter(m -> m.id().equals(masterId.toString())).findFirst().orElseThrow();
    }

    /**
     * Replaces the weekly schedule of a master (a missing weekday is a day off). Refused with 409 when a pending or
     * confirmed future booking would no longer fit, so a confirmed customer is never silently stranded.
     */
    @Transactional
    public MasterView setHours(UUID actor, UUID partnerId, UUID venueId, UUID masterId, List<HoursView> hours) {
        partners.requireProcessing(actor, partnerId, Role.OWNER, Role.MANAGER);
        requireOwnedVenue(partnerId, venueId);
        // Exclusive lock: bookings take a shared lock on the master row, so none can be created while this runs.
        db.query("select id from marketplace.booking_masters where id = ? and venue_id = ? for update",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, masterId, venueId);
        Integer exists = db.queryForObject("select count(*) from marketplace.booking_masters where id = ? and venue_id = ?",
                Integer.class, masterId, venueId);
        if (exists == null || exists == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "MASTER_NOT_FOUND", "Master not found");
        }
        Set<Integer> days = new HashSet<>();
        record Window(LocalTime from, LocalTime to, LocalTime breakFrom, LocalTime breakTo) {}
        java.util.Map<Integer, Window> windows = new java.util.HashMap<>();
        for (HoursView h : hours) {
            try {
                LocalTime from = LocalTime.parse(h.from());
                LocalTime to = LocalTime.parse(h.to());
                LocalTime bf = h.breakFrom() == null ? null : LocalTime.parse(h.breakFrom());
                LocalTime bt = h.breakTo() == null ? null : LocalTime.parse(h.breakTo());
                boolean ok = h.day() >= 1 && h.day() <= 7 && days.add(h.day()) && to.isAfter(from)
                        && (bf == null) == (bt == null) && (bf == null || (bt.isAfter(bf) && !bf.isBefore(from) && !bt.isAfter(to)));
                if (!ok) { throw new IllegalArgumentException(); }
                windows.put(h.day(), new Window(from, to, bf, bt));
            } catch (RuntimeException e) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "HOURS_INVALID",
                        "Each weekday (1-7) at most once, HH:mm, end after start, break inside the day");
            }
        }
        ZoneId zone = ZoneId.of(db.queryForObject("select timezone from marketplace.booking_venues where id = ?", String.class, venueId));
        var upcoming = db.query("""
                select starts_at, ends_at from transactions.bookings
                where master_id = ? and status in ('PENDING', 'CONFIRMED') and ends_at > now()
                """, (rs, n) -> new Timestamp[] {rs.getTimestamp(1), rs.getTimestamp(2)}, masterId);
        for (Timestamp[] b : upcoming) {
            var start = b[0].toInstant().atZone(zone);
            var end = b[1].toInstant().atZone(zone);
            Window w = windows.get(start.getDayOfWeek().getValue());
            boolean fits = w != null && !start.toLocalTime().isBefore(w.from()) && !end.toLocalTime().isAfter(w.to())
                    && end.toLocalDate().equals(start.toLocalDate())
                    && (w.breakFrom() == null || !(start.toLocalTime().isBefore(w.breakTo()) && end.toLocalTime().isAfter(w.breakFrom())));
            if (!fits) {
                throw new ApiException(HttpStatus.CONFLICT, "SCHEDULE_CONFLICT",
                        "An existing booking on " + start.toLocalDate() + " would no longer fit the new hours");
            }
        }
        String before = hours(masterId).toString();
        db.update("delete from marketplace.booking_working_hours where master_id = ?", masterId);
        for (HoursView h : hours) {
            db.update("""
                    insert into marketplace.booking_working_hours (master_id, weekday, start_time, end_time, break_start, break_end)
                    values (?, ?, ?::time, ?::time, ?::time, ?::time)
                    """, masterId, h.day(), h.from(), h.to(), h.breakFrom(), h.breakTo());
        }
        String after = hours(masterId).toString();
        if (!before.equals(after)) {
            audit(partnerId, actor, "MASTER", masterId, "hours", abbreviate(before), abbreviate(after));
        }
        return masters(actor, partnerId, venueId).stream().filter(m -> m.id().equals(masterId.toString())).findFirst().orElseThrow();
    }

    // ---- internals -----------------------------------------------------------------------------

    private static String abbreviate(String s) { return s.length() <= 300 ? s : s.substring(0, 297) + "..."; }

    private void audit(UUID partnerId, UUID actor, String entityType, UUID entityId, String field, String oldValue, String newValue) {
        db.update("""
                insert into marketplace.partner_catalog_events (partner_id, actor_user_id, entity_type, entity_id, field, old_value, new_value)
                values (?, ?, ?, ?, ?, ?, ?)
                """, partnerId, actor, entityType, entityId, field, oldValue, newValue);
    }

    private void requireOwnedVenue(UUID partnerId, UUID venueId) {
        Integer found = db.queryForObject("select count(*) from marketplace.booking_venues where id = ? and partner_id = ?",
                Integer.class, venueId, partnerId);
        if (found == null || found == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found");
        }
    }

    private void requireOwnedBooking(UUID partnerId, UUID bookingId) {
        Integer found = db.queryForObject("""
                select count(*) from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id
                where b.id = ? and v.partner_id = ?
                """, Integer.class, bookingId, partnerId);
        if (found == null || found == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found");
        }
    }

    private List<PartnerBooking> load(List<UUID> ids) {
        if (ids.isEmpty()) { return List.of(); }
        UUID[] array = ids.toArray(UUID[]::new);
        java.util.Map<UUID, List<TimelineEntry>> timeline = new java.util.HashMap<>();
        db.query("select booking_id, status, occurred_at, actor_type, reason from transactions.booking_events where booking_id = any (?) order by id",
                rs -> {
                    timeline.computeIfAbsent(rs.getObject(1, UUID.class), k -> new ArrayList<>()).add(new TimelineEntry(
                            rs.getString(2), rs.getObject(3, OffsetDateTime.class), rs.getString(4), rs.getString(5)));
                }, (Object) array);
        java.util.Map<UUID, PartnerBooking> byId = new java.util.HashMap<>();
        db.query("""
                select id, venue_id, venue_name, category, service_name, duration_minutes, master_id, master_name, starts_at, ends_at,
                       price_minor, currency, status, comment, address_text, area_sqm, user_id, created_at, cancelled_by, cancel_reason,
                       starts_at > now() as future
                from transactions.bookings where id = any (?)
                """, rs -> {
                    UUID id = rs.getObject("id", UUID.class);
                    String status = rs.getString("status");
                    boolean future = rs.getBoolean("future");
                    List<String> actions = new ArrayList<>();
                    if ("PENDING".equals(status) && future) { actions.add("CONFIRM"); actions.add("REJECT"); }
                    if ("CONFIRMED".equals(status) && future) { actions.add("CANCEL"); }
                    if ("CONFIRMED".equals(status) && !future) { actions.add("COMPLETE"); }
                    byId.put(id, new PartnerBooking(id.toString(), rs.getString("venue_id"), rs.getString("venue_name"),
                            rs.getString("category"), rs.getString("service_name"), rs.getInt("duration_minutes"),
                            rs.getString("master_id"), rs.getString("master_name"), rs.getObject("starts_at", OffsetDateTime.class),
                            rs.getObject("ends_at", OffsetDateTime.class), rs.getLong("price_minor"), rs.getString("currency"),
                            status, rs.getString("comment"), rs.getString("address_text"), rs.getObject("area_sqm", Integer.class),
                            rs.getString("user_id").substring(0, 8), rs.getObject("created_at", OffsetDateTime.class),
                            rs.getString("cancelled_by"), rs.getString("cancel_reason"), actions,
                            timeline.getOrDefault(id, List.of())));
                }, (Object) array);
        return ids.stream().map(byId::get).filter(java.util.Objects::nonNull).toList();
    }
}
