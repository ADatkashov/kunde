package kz.kunde.leisure;

import java.security.SecureRandom;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Customer side of Leisure: server-priced holds, idempotent orders, tickets with server-verified QR codes, cancellation by the venue's rules,
 * reviews, favourites and complaints. Concurrency: every change of a session's inventory first takes a row lock on the session, so two buyers
 * can never both take the last place; seats are additionally protected by a partial unique index. While the Leisure switch is off no NEW hold or
 * order is accepted, but orders that already exist stay readable and can be cancelled.
 */
@Service
public class LeisureOrderService {
    private static final Pattern KEY = Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final int HOLD_MINUTES = 10;
    private static final int MAX_UPCOMING = 20;
    private static final SecureRandom RANDOM = new SecureRandom();

    public record Line(UUID ticketTypeId, Integer quantity, List<UUID> seatIds) {}

    public record HoldRequest(Integer guests, List<Line> lines) {}

    public record HoldLine(String ticketTypeId, String ticketType, String seatId, String seat, long unitPriceMinor) {}

    public record HoldView(String id, String sessionId, int guests, long totalMinor, String currency, OffsetDateTime expiresAt, List<HoldLine> lines) {}

    public record TicketView(String id, String status, String ticketType, String seat, int admits, long priceMinor, String qr, OffsetDateTime usedAt) {}

    public record TimelineEntry(String status, OffsetDateTime at, String actor, String reason) {}

    public record OrderView(String id, String status, String phase, String eventId, String eventTitle, String categoryCode, String bookingType, String venueId,
            String venueName, String venueAddress, String photoUrl, String sessionId, OffsetDateTime startsAt, OffsetDateTime endsAt, int guests,
            long totalMinor, String currency, String paymentMethod, LeisurePayments.PaymentView payment, boolean cancellable, OffsetDateTime cancelUntil,
            String cancelledBy, String cancelReason, OffsetDateTime createdAt, String rules, int minAge, boolean reviewed, boolean canReview,
            List<TicketView> tickets, List<TimelineEntry> timeline) {}

    public record Placed(OrderView order, boolean created) {}

    public record ReviewBody(Integer rating, String body) {}

    private final JdbcTemplate db;
    private final FeatureToggles toggles;
    private final LeisurePayments payments;

    public LeisureOrderService(JdbcTemplate db, FeatureToggles toggles, LeisurePayments payments) {
        this.db = db;
        this.toggles = toggles;
        this.payments = payments;
    }

    // ---- holds ---------------------------------------------------------------------------------------------------------------

    private record SessionRow(UUID id, UUID eventId, UUID venueId, String bookingType, int capacity, OffsetDateTime startsAt, OffsetDateTime endsAt, String status,
            int maxGuests, int minAge, String confirmation, int cancellationHours, String eventStatus, String venueStatus, String title) {}

    private SessionRow lockSession(UUID sessionId) {
        return db.query("""
                select s.id, e.id, v.id, e.booking_type, s.capacity, s.starts_at, s.ends_at, s.status, e.max_guests, e.min_age, e.confirmation,
                       v.cancellation_hours, e.status, v.status, e.title
                from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id join marketplace.leisure_venues v on v.id = e.venue_id
                where s.id = ? for update of s""", (rs, n) -> new SessionRow(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                rs.getString(4), rs.getInt(5), kz.kunde.leisure.LeisureTime.local(rs, 6), kz.kunde.leisure.LeisureTime.local(rs, 7), rs.getString(8), rs.getInt(9),
                rs.getInt(10), rs.getString(11), rs.getInt(12), rs.getString(13), rs.getString(14), rs.getString(15)), sessionId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SESSION_NOT_FOUND", "Session not found"));
    }

    /** New sales follow the switch of the product the session belongs to (Events or Leisure); existing orders stay readable either way. */
    private void requireEnabledForSession(UUID sessionId) {
        String product = db.query("select c.product from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id "
                + "join marketplace.leisure_categories c on c.code = e.category_code where s.id = ?", (rs, n) -> rs.getString(1), sessionId)
                .stream().findFirst().orElse("LEISURE");
        if ("EVENTS".equals(product)) {
            if (!toggles.enabled(Feature.EVENTS)) {
                throw new ApiException(HttpStatus.CONFLICT, "EVENTS_DISABLED", "Events is switched off; new ticket sales are not accepted");
            }
        } else if (!toggles.enabled(Feature.LEISURE)) {
            throw new ApiException(HttpStatus.CONFLICT, "LEISURE_DISABLED", "Leisure is switched off; new bookings are not accepted");
        }
    }

    private record Priced(UUID ticketTypeId, String name, long price, String pricing, String zone) {}

    @Transactional
    public HoldView hold(UUID user, UUID sessionId, HoldRequest req) {
        requireEnabledForSession(sessionId);
        if (req == null || req.lines() == null || req.lines().isEmpty() || req.lines().size() > 10) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "SELECTION_INVALID", "Choose at least one ticket");
        }
        SessionRow s = lockSession(sessionId);
        if (!"PUBLISHED".equals(s.eventStatus) || !"APPROVED".equals(s.venueStatus) || !"SCHEDULED".equals(s.status)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "SESSION_NOT_FOUND", "Session not found");
        }
        if (!s.startsAt.isAfter(OffsetDateTime.now())) {
            throw new ApiException(HttpStatus.CONFLICT, "SESSION_STARTED", "Sales for this session are closed");
        }
        expireStale(sessionId);
        // one live hold per customer and session: a new selection replaces the previous one
        db.update("update transactions.leisure_holds set status = 'RELEASED' where user_id = ? and session_id = ? and status = 'ACTIVE'", user, sessionId);

        List<Object[]> units = new ArrayList<>(); // {Priced, seatId|null}
        boolean seatMap = "SEAT_MAP".equals(s.bookingType);
        boolean perBooking = "TIME_SLOT".equals(s.bookingType) || "PRIVATE_SESSION".equals(s.bookingType);
        for (Line line : req.lines()) {
            if (line == null || line.ticketTypeId() == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "SELECTION_INVALID", "Ticket type is required"); }
            Priced type = db.query("select id, name, price_minor, pricing, seat_zone from marketplace.leisure_ticket_types where id = ? and event_id = ? and active",
                    (rs, n) -> new Priced(rs.getObject(1, UUID.class), rs.getString(2), rs.getLong(3), rs.getString(4), rs.getString(5)), line.ticketTypeId(), s.eventId)
                    .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "TICKET_TYPE_INVALID", "Unknown ticket type"));
            int qty = line.quantity() == null ? (seatMap && line.seatIds() != null ? line.seatIds().size() : 0) : line.quantity();
            if (qty < 1 || qty > 20) { throw new ApiException(HttpStatus.BAD_REQUEST, "SELECTION_INVALID", "Quantity must be between 1 and 20"); }
            if (perBooking != "PER_BOOKING".equals(type.pricing)) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "TICKET_TYPE_INVALID", "This ticket type does not fit the booking type");
            }
            if (seatMap) {
                if (line.seatIds() == null || line.seatIds().size() != qty) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "SEATS_REQUIRED", "Choose exactly one seat per ticket");
                }
                for (UUID seat : line.seatIds()) {
                    String zone = db.query("select zone from marketplace.leisure_seats where id = ? and session_id = ?", (rs, n) -> rs.getString(1), seat, sessionId)
                            .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "SEAT_INVALID", "Seat does not belong to the session"));
                    if (type.zone != null && !type.zone.equals(zone)) {
                        throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "SEAT_ZONE_MISMATCH", "The ticket type does not apply to this seat zone");
                    }
                    units.add(new Object[] {type, seat});
                }
            } else {
                if (line.seatIds() != null && !line.seatIds().isEmpty()) { throw new ApiException(HttpStatus.BAD_REQUEST, "SEATS_NOT_USED", "This event has no seat map"); }
                for (int i = 0; i < qty; i++) { units.add(new Object[] {type, null}); }
            }
        }
        if (perBooking && units.size() != 1) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "SELECTION_INVALID", "Exactly one booking is chosen for this event");
        }
        int guests = perBooking ? (req.guests() == null ? 1 : req.guests()) : units.size();
        if (guests < 1 || guests > s.maxGuests) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "GUESTS_LIMIT", "At most " + s.maxGuests + " guests");
        }
        if (units.size() > s.maxGuests && !perBooking) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "GUESTS_LIMIT", "At most " + s.maxGuests + " tickets per order");
        }
        int free = free(sessionId, s.capacity);
        if (free < units.size()) {
            throw new ApiException(HttpStatus.CONFLICT, "NOT_ENOUGH_PLACES", free <= 0 ? "No places left" : "Only " + free + " places left");
        }
        if (seatMap) {
            for (Object[] u : units) {
                if (seatTaken(sessionId, (UUID) u[1])) { throw new ApiException(HttpStatus.CONFLICT, "SEAT_TAKEN", "A chosen seat has just been taken"); }
            }
        }
        long total = 0;
        for (Object[] u : units) { total += ((Priced) u[0]).price; }
        UUID hold = db.queryForObject("insert into transactions.leisure_holds (user_id, session_id, guests, total_minor, expires_at) values (?, ?, ?, ?, now() + (? * interval '1 minute')) returning id",
                UUID.class, user, sessionId, guests, total, HOLD_MINUTES);
        for (Object[] u : units) {
            Priced p = (Priced) u[0];
            db.update("insert into transactions.leisure_hold_lines (hold_id, ticket_type_id, seat_id, unit_price_minor) values (?, ?, ?, ?)", hold, p.ticketTypeId, u[1], p.price);
        }
        return holdView(user, hold);
    }

    @Transactional
    public void releaseHold(UUID user, UUID holdId) {
        db.update("update transactions.leisure_holds set status = 'RELEASED' where id = ? and user_id = ? and status = 'ACTIVE'", holdId, user);
    }

    @Transactional(readOnly = true)
    public HoldView getHold(UUID user, UUID holdId) { return holdView(user, holdId); }

    private HoldView holdView(UUID user, UUID holdId) {
        var h = db.query("select id, session_id, guests, total_minor, expires_at, status from transactions.leisure_holds where id = ? and user_id = ?",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getInt(3), rs.getLong(4), kz.kunde.leisure.LeisureTime.local(rs, 5), rs.getString(6)}, holdId, user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "HOLD_NOT_FOUND", "Hold not found"));
        List<HoldLine> lines = db.query("""
                select hl.ticket_type_id, tt.name, hl.seat_id, st.row_label || st.seat_number, hl.unit_price_minor from transactions.leisure_hold_lines hl
                join marketplace.leisure_ticket_types tt on tt.id = hl.ticket_type_id left join marketplace.leisure_seats st on st.id = hl.seat_id
                where hl.hold_id = ? order by hl.id""", (rs, n) -> new HoldLine(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getLong(5)), holdId);
        return new HoldView((String) h[0], (String) h[1], (int) h[2], (long) h[3], "KZT", (OffsetDateTime) h[4], lines);
    }

    private void expireStale(UUID sessionId) {
        db.update("update transactions.leisure_holds set status = 'EXPIRED' where session_id = ? and status = 'ACTIVE' and expires_at <= now()", sessionId);
    }

    private int free(UUID sessionId, int capacity) {
        Integer taken = db.queryForObject("select (select count(*) from transactions.leisure_tickets where session_id = ? and status in ('PENDING', 'VALID', 'USED'))"
                + " + (select count(*) from transactions.leisure_hold_lines hl join transactions.leisure_holds h on h.id = hl.hold_id where h.session_id = ? and h.status = 'ACTIVE' and h.expires_at > now())",
                Integer.class, sessionId, sessionId);
        return capacity - (taken == null ? 0 : taken);
    }

    private boolean seatTaken(UUID sessionId, UUID seatId) {
        return Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from transactions.leisure_tickets where session_id = ? and seat_id = ? and status in ('PENDING', 'VALID', 'USED'))"
                + " or exists (select 1 from transactions.leisure_hold_lines hl join transactions.leisure_holds h on h.id = hl.hold_id where hl.seat_id = ? and h.status = 'ACTIVE' and h.expires_at > now())",
                Boolean.class, sessionId, seatId, seatId));
    }

    // ---- orders --------------------------------------------------------------------------------------------------------------

    public record PlaceBody(UUID holdId, String paymentMethod, Boolean ageConfirmed) {}

    @Transactional
    public Placed place(UUID user, String key, PlaceBody body) {
        if (key == null || !KEY.matcher(key).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key header (16-64 chars) is required");
        }
        if (body == null || body.holdId() == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "HOLD_REQUIRED", "holdId is required"); }
        var existing = db.query("select id, hold_id from transactions.leisure_orders where user_id = ? and idempotency_key = ?",
                (rs, n) -> new UUID[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class)}, user, key).stream().findFirst();
        if (existing.isPresent()) {
            if (!body.holdId().equals(existing.get()[1])) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "This key was used for another order");
            }
            return new Placed(order(user, existing.get()[0]), false);
        }
        requireEnabledForSession(db.query("select session_id from transactions.leisure_holds where id = ? and user_id = ?", (rs, n) -> rs.getObject(1, UUID.class), body.holdId(), user)
                .stream().findFirst().orElse(null));
        String method = payments.method(body.paymentMethod());
        var hold = db.query("select session_id, guests, total_minor, status, expires_at from transactions.leisure_holds where id = ? and user_id = ? for update",
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getInt(2), rs.getLong(3), rs.getString(4), kz.kunde.leisure.LeisureTime.local(rs, 5)}, body.holdId(), user)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "HOLD_NOT_FOUND", "Hold not found"));
        if ("CONSUMED".equals(hold[3])) { // a parallel request with the same key finished first while this one waited for the hold lock
            var done = db.query("select id from transactions.leisure_orders where user_id = ? and idempotency_key = ? and hold_id = ?", (rs, n) -> rs.getObject(1, UUID.class), user, key, body.holdId());
            if (!done.isEmpty()) { return new Placed(order(user, done.get(0)), false); }
        }
        UUID sessionId = (UUID) hold[0];
        SessionRow s = lockSession(sessionId);
        if (!"ACTIVE".equals(hold[3]) || !((OffsetDateTime) hold[4]).isAfter(OffsetDateTime.now())) {
            if ("ACTIVE".equals(hold[3])) { db.update("update transactions.leisure_holds set status = 'EXPIRED' where id = ?", body.holdId()); }
            throw new ApiException(HttpStatus.CONFLICT, "HOLD_EXPIRED", "The reservation has expired; choose places again");
        }
        if (!"SCHEDULED".equals(s.status) || !"PUBLISHED".equals(s.eventStatus) || !"APPROVED".equals(s.venueStatus) || !s.startsAt.isAfter(OffsetDateTime.now())) {
            throw new ApiException(HttpStatus.CONFLICT, "SESSION_NOT_AVAILABLE", "The session is no longer available");
        }
        if (s.minAge > 0 && !Boolean.TRUE.equals(body.ageConfirmed())) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "AGE_CONFIRMATION_REQUIRED", "Confirm that every guest is at least " + s.minAge + " years old");
        }
        Long active = db.queryForObject("select count(*) from transactions.leisure_orders o join marketplace.leisure_sessions x on x.id = o.session_id "
                + "where o.user_id = ? and o.status in ('PENDING', 'CONFIRMED') and x.ends_at > now()", Long.class, user);
        if (active != null && active >= MAX_UPCOMING) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_UPCOMING", "Too many upcoming bookings");
        }
        boolean manual = "MANUAL".equals(s.confirmation);
        UUID id = db.query("""
                insert into transactions.leisure_orders (user_id, session_id, event_id, venue_id, guests, status, total_minor, payment_method, idempotency_key, hold_id)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) on conflict (user_id, idempotency_key) do nothing returning id""", rs -> rs.next() ? rs.getObject(1, UUID.class) : null,
                user, sessionId, s.eventId, s.venueId, hold[1], manual ? "PENDING" : "CONFIRMED", hold[2], method, key, body.holdId());
        if (id == null) { // a parallel request with the same key won: return its order
            UUID prior = db.queryForObject("select id from transactions.leisure_orders where user_id = ? and idempotency_key = ?", UUID.class, user, key);
            return new Placed(order(user, prior), false);
        }
        var lines = db.query("select hl.ticket_type_id, hl.seat_id, hl.unit_price_minor, tt.pricing from transactions.leisure_hold_lines hl "
                + "join marketplace.leisure_ticket_types tt on tt.id = hl.ticket_type_id where hl.hold_id = ? order by hl.id",
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getLong(3), rs.getString(4)}, body.holdId());
        for (Object[] l : lines) {
            int admits = "PER_BOOKING".equals(l[3]) ? (int) hold[1] : 1;
            db.update("insert into transactions.leisure_tickets (order_id, session_id, ticket_type_id, seat_id, admits, price_minor, nonce, status) values (?, ?, ?, ?, ?, ?, ?, ?)",
                    id, sessionId, l[0], l[1], admits, l[2], nonce(), manual ? "PENDING" : "VALID");
        }
        db.update("update transactions.leisure_holds set status = 'CONSUMED' where id = ?", body.holdId());
        payments.open(user, id, method, (long) hold[2]);
        if (!manual) { payments.capture(id, "CUSTOMER", user); }
        event(id, manual ? "PENDING" : "CONFIRMED", "CUSTOMER", user, null);
        return new Placed(order(user, id), true);
    }

    private static String nonce() {
        byte[] b = new byte[16];
        RANDOM.nextBytes(b);
        return HexFormat.of().formatHex(b);
    }

    void event(UUID order, String status, String actor, UUID actorUser, String reason) {
        db.update("insert into transactions.leisure_order_events (order_id, status, actor, actor_user_id, reason) values (?, ?, ?, ?, ?)", order, status, actor, actorUser, reason);
    }

    @Transactional(readOnly = true)
    public List<OrderView> list(UUID user, String scope, int limit, int offset) {
        String filter = switch (scope == null ? "upcoming" : scope) {
            case "completed" -> "o.status = 'CONFIRMED' and s.ends_at <= now()";
            case "cancelled" -> "o.status = 'CANCELLED'";
            default -> "o.status in ('PENDING', 'CONFIRMED') and s.ends_at > now()";
        };
        String order = "completed".equals(scope) || "cancelled".equals(scope) ? "s.starts_at desc" : "s.starts_at asc";
        List<UUID> ids = db.queryForList("select o.id from transactions.leisure_orders o join marketplace.leisure_sessions s on s.id = o.session_id where o.user_id = ? and "
                + filter + " order by " + order + ", o.id limit ? offset ?", UUID.class, user, Math.max(1, Math.min(limit, 100)), Math.max(0, offset));
        return ids.stream().map(id -> order(user, id)).toList();
    }

    @Transactional(readOnly = true)
    public OrderView order(UUID user, UUID id) {
        var row = db.query("""
                select o.id, o.status, e.id, e.title, e.category_code, e.booking_type, v.id, v.name, v.address, coalesce(e.photo_urls[1], v.photo_urls[1]), s.id, s.starts_at, s.ends_at,
                       o.guests, o.total_minor, o.payment_method, v.cancellation_hours, o.cancelled_by, o.cancel_reason, o.created_at, v.rules, e.min_age,
                       exists (select 1 from transactions.leisure_reviews r where r.order_id = o.id),
                       exists (select 1 from transactions.leisure_tickets t where t.order_id = o.id and t.status = 'USED')
                from transactions.leisure_orders o join marketplace.leisure_sessions s on s.id = o.session_id join marketplace.leisure_events e on e.id = o.event_id
                join marketplace.leisure_venues v on v.id = o.venue_id where o.id = ? and o.user_id = ?""", (rs, n) -> new Object[] {
                rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7), rs.getString(8), rs.getString(9),
                rs.getString(10), rs.getString(11), kz.kunde.leisure.LeisureTime.local(rs, 12), kz.kunde.leisure.LeisureTime.local(rs, 13), rs.getInt(14), rs.getLong(15),
                rs.getString(16), rs.getInt(17), rs.getString(18), rs.getString(19), kz.kunde.leisure.LeisureTime.local(rs, 20), rs.getString(21), rs.getInt(22),
                rs.getBoolean(23), rs.getBoolean(24)}, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        String status = (String) row[1];
        OffsetDateTime starts = (OffsetDateTime) row[11];
        OffsetDateTime ends = (OffsetDateTime) row[12];
        OffsetDateTime cancelUntil = starts.minusHours((int) row[16]);
        boolean used = (boolean) row[23];
        boolean live = !"CANCELLED".equals(status);
        boolean cancellable = live && !used && OffsetDateTime.now().isBefore("PENDING".equals(status) ? starts : cancelUntil);
        String phase = "CANCELLED".equals(status) ? "CANCELLED" : ends.isAfter(OffsetDateTime.now()) ? "UPCOMING" : "COMPLETED";
        boolean reviewed = (boolean) row[22];
        boolean canReview = "CONFIRMED".equals(status) && !reviewed && (used || !ends.isAfter(OffsetDateTime.now()));
        List<TicketView> tickets = db.query("""
                select t.id, t.status, tt.name, st.row_label || st.seat_number, t.admits, t.price_minor, t.nonce, t.used_at from transactions.leisure_tickets t
                join marketplace.leisure_ticket_types tt on tt.id = t.ticket_type_id left join marketplace.leisure_seats st on st.id = t.seat_id
                where t.order_id = ? order by st.row_label, st.seat_number, t.created_at, t.id""", (rs, n) -> new TicketView(rs.getString(1), rs.getString(2), rs.getString(3),
                rs.getString(4), rs.getInt(5), rs.getLong(6), "VALID".equals(rs.getString(2)) || "USED".equals(rs.getString(2)) ? "KT1." + rs.getString(1) + "." + rs.getString(7) : null,
                kz.kunde.leisure.LeisureTime.local(rs, 8)), id);
        List<TimelineEntry> timeline = db.query("select status, occurred_at, actor, reason from transactions.leisure_order_events where order_id = ? order by id",
                (rs, n) -> new TimelineEntry(rs.getString(1), kz.kunde.leisure.LeisureTime.local(rs, 2), rs.getString(3), rs.getString(4)), id);
        return new OrderView((String) row[0], status, phase, (String) row[2], (String) row[3], (String) row[4], (String) row[5], (String) row[6], (String) row[7],
                (String) row[8], (String) row[9], (String) row[10], starts, ends, (int) row[13], (long) row[14], "KZT", (String) row[15], payments.ofOrder(id), cancellable,
                cancelUntil, (String) row[17], (String) row[18], (OffsetDateTime) row[19], (String) row[20], (int) row[21], reviewed, canReview, tickets, timeline);
    }

    @Transactional
    public OrderView cancel(UUID user, UUID id) {
        var row = db.query("""
                select o.status, o.session_id, s.starts_at, v.cancellation_hours from transactions.leisure_orders o join marketplace.leisure_sessions s on s.id = o.session_id
                join marketplace.leisure_venues v on v.id = o.venue_id where o.id = ? and o.user_id = ? for update of o""", (rs, n) -> new Object[] {rs.getString(1),
                rs.getObject(2, UUID.class), kz.kunde.leisure.LeisureTime.local(rs, 3), rs.getInt(4)}, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        if ("CANCELLED".equals(row[0])) { return order(user, id); } // idempotent repeat
        lockSession((UUID) row[1]);
        if (Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from transactions.leisure_tickets where order_id = ? and status = 'USED')", Boolean.class, id))) {
            throw new ApiException(HttpStatus.CONFLICT, "TICKET_USED", "A ticket of this order has already been used");
        }
        OffsetDateTime starts = (OffsetDateTime) row[2];
        OffsetDateTime deadline = "PENDING".equals(row[0]) ? starts : starts.minusHours((int) row[3]);
        if (!OffsetDateTime.now().isBefore(deadline)) {
            throw new ApiException(HttpStatus.CONFLICT, "CANCELLATION_WINDOW_CLOSED", "Free cancellation is over for this session");
        }
        cancelOrder(id, "CUSTOMER", user, "Cancelled by the customer");
        return order(user, id);
    }

    /** Shared by customer, partner, admin and session cancellation: tickets die, payment is refunded or voided, the places are free again. */
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY)
    void cancelOrder(UUID id, String actor, UUID actorUser, String reason) {
        db.update("update transactions.leisure_orders set status = 'CANCELLED', cancelled_by = ?, cancel_reason = ?, cancelled_at = now(), updated_at = now(), version = version + 1 where id = ?",
                actor, reason, id);
        db.update("update transactions.leisure_tickets set status = 'CANCELLED' where order_id = ? and status in ('PENDING', 'VALID')", id);
        payments.refundAll(id, actor, actorUser, reason);
        event(id, "CANCELLED", actor, actorUser, reason);
    }

    /** Administrator cancellation: always allowed unless a ticket was used; the customer is refunded in full (test payments). */
    @Transactional
    public void adminCancel(UUID admin, UUID id, String reason) {
        var row = db.query("select status, session_id from transactions.leisure_orders where id = ? for update", (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class)}, id)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        if ("CANCELLED".equals(row[0])) { return; }
        lockSession((UUID) row[1]);
        if (Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from transactions.leisure_tickets where order_id = ? and status = 'USED')", Boolean.class, id))) {
            throw new ApiException(HttpStatus.CONFLICT, "TICKET_USED", "A ticket of this order has already been used");
        }
        cancelOrder(id, "ADMIN", admin, reason);
        db.update("insert into marketplace.leisure_audit (actor_user_id, actor_type, action, target, detail) values (?, 'ADMIN', 'ORDER_CANCELLED', ?, ?)", admin, id.toString(), reason);
    }

    // ---- reviews, favourites, complaints --------------------------------------------------------------------------------------

    @Transactional
    public LeisureCatalogService.ReviewView review(UUID user, UUID orderId, ReviewBody body) {
        if (body == null || body.rating() == null || body.rating() < 1 || body.rating() > 5) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "RATING_INVALID", "Rating must be 1-5");
        }
        String text = body.body() == null ? "" : body.body().strip();
        if (text.length() > 1000) { throw new ApiException(HttpStatus.BAD_REQUEST, "REVIEW_TOO_LONG", "At most 1000 characters"); }
        OrderView o = order(user, orderId);
        if (o.reviewed()) { throw new ApiException(HttpStatus.CONFLICT, "ALREADY_REVIEWED", "This order has already been reviewed"); }
        if (!o.canReview()) { throw new ApiException(HttpStatus.CONFLICT, "REVIEW_NOT_ALLOWED", "A review is possible after the session"); }
        try {
            UUID id = db.queryForObject("insert into transactions.leisure_reviews (order_id, user_id, event_id, venue_id, rating, body) values (?, ?, ?, ?, ?, ?) returning id",
                    UUID.class, orderId, user, UUID.fromString(o.eventId()), UUID.fromString(o.venueId()), body.rating(), text);
            return new LeisureCatalogService.ReviewView(id.toString(), body.rating(), text, OffsetDateTime.now(), "Гость");
        } catch (DuplicateKeyException e) {
            throw new ApiException(HttpStatus.CONFLICT, "ALREADY_REVIEWED", "This order has already been reviewed");
        }
    }

    @Transactional(readOnly = true)
    public List<String> favoriteIds(UUID user) {
        return db.queryForList("select event_id::text from transactions.leisure_favorites where user_id = ? order by created_at desc", String.class, user);
    }

    @Transactional
    public void favorite(UUID user, UUID eventId, boolean on) {
        if (on) {
            if (db.queryForObject("select count(*) from marketplace.leisure_events where id = ? and status = 'PUBLISHED'", Integer.class, eventId) == 0) {
                throw new ApiException(HttpStatus.NOT_FOUND, "EVENT_NOT_FOUND", "Event not found");
            }
            db.update("insert into transactions.leisure_favorites (user_id, event_id) values (?, ?) on conflict do nothing", user, eventId);
        } else {
            db.update("delete from transactions.leisure_favorites where user_id = ? and event_id = ?", user, eventId);
        }
    }

    public record ComplaintBody(UUID venueId, UUID orderId, String body) {}

    @Transactional
    public Map<String, Object> complain(UUID user, ComplaintBody b) {
        String text = b == null || b.body() == null ? "" : b.body().strip();
        if (text.isEmpty() || text.length() > 1000) { throw new ApiException(HttpStatus.BAD_REQUEST, "COMPLAINT_INVALID", "Describe the problem (up to 1000 characters)"); }
        UUID venue = b.venueId();
        if (b.orderId() != null) {
            venue = db.query("select venue_id from transactions.leisure_orders where id = ? and user_id = ?", (rs, n) -> rs.getObject(1, UUID.class), b.orderId(), user)
                    .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
        }
        if (venue == null) { throw new ApiException(HttpStatus.BAD_REQUEST, "COMPLAINT_INVALID", "Venue or order is required"); }
        if (db.queryForObject("select count(*) from marketplace.leisure_venues where id = ?", Integer.class, venue) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found");
        }
        Long open = db.queryForObject("select count(*) from transactions.leisure_complaints where user_id = ? and status = 'OPEN'", Long.class, user);
        if (open != null && open >= 10) { throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "TOO_MANY_COMPLAINTS", "Too many open complaints"); }
        UUID id = db.queryForObject("insert into transactions.leisure_complaints (user_id, venue_id, order_id, body) values (?, ?, ?, ?) returning id", UUID.class, user, venue, b.orderId(), text);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", id.toString());
        out.put("status", "OPEN");
        return out;
    }
}
