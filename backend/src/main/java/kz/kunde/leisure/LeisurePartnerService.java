package kz.kunde.leisure;

import java.security.MessageDigest;
import java.sql.Array;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Partner side of Leisure: venues, events, ticket types, sessions (with seat maps), bookings, QR check-in, attendance and audit history.
 * Every method starts with the membership gate (404 for strangers, 403 for an unapproved partner or a role that may not do this) and then only
 * touches rows of the partner's own venues. Roles: OWNER and MANAGER manage the catalogue and may cancel; OPERATOR (Staff) can see bookings,
 * confirm or reject pending ones and check tickets in. New or changed content goes through administrator moderation before it is public.
 */
@Service
public class LeisurePartnerService {
    private static final Pattern CODE = Pattern.compile("^KT1\\.([0-9a-f-]{36})\\.([0-9a-f]{32})$");
    private static final Pattern URL = Pattern.compile("^https://[^\\s]{4,300}$");
    private static final Role[] MANAGE = {Role.OWNER, Role.MANAGER};
    private static final List<String> TYPES = List.of("TIME_SLOT", "CAPACITY", "SEAT_MAP", "GENERAL_ADMISSION", "PRIVATE_SESSION");

    public record VenueInput(String name, String description, String address, String district, Double latitude, Double longitude, List<String> photoUrls,
            String rules, Integer cancellationHours) {}

    public record VenueRow(String id, String name, String description, String address, String district, Double latitude, Double longitude, List<String> photoUrls,
            String rules, int cancellationHours, String status, String moderationNote, long version, int events) {}

    public record EventInput(String categoryCode, String bookingType, String title, String description, List<String> photoUrls, Integer durationMinutes,
            Integer minAge, Boolean familyFriendly, Integer maxGuests, String confirmation, Boolean needsExecutor) {}

    public record EventRow(String id, String venueId, String venueName, String categoryCode, String bookingType, String title, String description,
            List<String> photoUrls, int durationMinutes, int minAge, boolean familyFriendly, int maxGuests, String confirmation, boolean needsExecutor,
            String status, String moderationNote, long version, int upcomingSessions) {}

    public record TicketTypeInput(String name, Long priceMinor, String pricing, String seatZone, Boolean active) {}

    public record TicketTypeRow(String id, String name, long priceMinor, String currency, String pricing, String seatZone, boolean active) {}

    public record SessionInput(List<OffsetDateTime> startsAt, Integer capacity, Integer rows, Integer seatsPerRow, Integer vipRows) {}

    public record SessionRow(String id, String eventId, String eventTitle, OffsetDateTime startsAt, OffsetDateTime endsAt, int capacity, int sold, int held,
            int admitted, String status, String cancelReason) {}

    public record PartnerOrder(String id, String status, String sessionId, String eventTitle, String venueName, OffsetDateTime startsAt, int guests, long totalMinor,
            String paymentMethod, LeisurePayments.PaymentView payment, String reference, OffsetDateTime createdAt, String cancelledBy, String cancelReason,
            List<LeisureOrderService.TicketView> tickets) {}

    public record CheckinResult(String result, boolean admitted, String message, String ticketId, String eventTitle, String sessionId, OffsetDateTime startsAt,
            String seat, String ticketType, int admits, OffsetDateTime usedAt) {}

    public record CheckinRow(long id, String result, int admits, String eventTitle, OffsetDateTime startsAt, OffsetDateTime at) {}

    public record AuditRow(long id, String action, String target, String detail, String actor, OffsetDateTime at) {}

    /** One line of the sales report: what an event sold in the window, what was refunded, and how full its upcoming sessions are. */
    public record SalesLine(String eventId, String title, String category, String product, int upcomingSessions, int upcomingCapacity, int upcomingSold,
            long tickets, long revenueMinor, long refundedMinor, long admittedGuests) {}

    public record Stats(int days, long orders, long tickets, long bookedMinor, long admittedGuests, long upcomingSessions) {}

    private final JdbcTemplate db;
    private final PartnerService partners;
    private final LeisureOrderService orders;
    private final LeisurePayments payments;
    private final FeatureToggles toggles;

    public LeisurePartnerService(JdbcTemplate db, PartnerService partners, LeisureOrderService orders, LeisurePayments payments, FeatureToggles toggles) {
        this.db = db;
        this.partners = partners;
        this.orders = orders;
        this.payments = payments;
        this.toggles = toggles;
    }

    private void audit(UUID actor, UUID partner, String action, String target, String detail) {
        db.update("insert into marketplace.leisure_audit (actor_user_id, actor_type, partner_id, action, target, detail) values (?, 'PARTNER', ?, ?, ?, ?)",
                actor, partner, action, target, detail == null ? null : detail.length() > 300 ? detail.substring(0, 300) : detail);
    }

    private void requireEnabled() {
        if (!toggles.enabled(FeatureToggles.Feature.LEISURE) && !toggles.enabled(FeatureToggles.Feature.EVENTS)) {
            throw new ApiException(HttpStatus.CONFLICT, "LEISURE_DISABLED", "Leisure is switched off; new venues, events and sessions are not accepted");
        }
    }

    /** EVENTS or LEISURE (the two products on one engine); absent = both. */
    private static String product(String product) {
        if (product == null || product.isBlank()) { return null; }
        if (!"EVENTS".equals(product) && !"LEISURE".equals(product)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PRODUCT_INVALID", "product must be EVENTS or LEISURE");
        }
        return product;
    }

    private static ApiException notFound(String code) { return new ApiException(HttpStatus.NOT_FOUND, code, "Not found"); }

    private void requireOwnVenue(UUID partner, UUID venue) {
        if (db.queryForObject("select count(*) from marketplace.leisure_venues where id = ? and partner_id = ?", Integer.class, venue, partner) == 0) { throw notFound("VENUE_NOT_FOUND"); }
    }

    private void requireOwnEvent(UUID partner, UUID event) {
        if (db.queryForObject("select count(*) from marketplace.leisure_events e join marketplace.leisure_venues v on v.id = e.venue_id where e.id = ? and v.partner_id = ?",
                Integer.class, event, partner) == 0) { throw notFound("EVENT_NOT_FOUND"); }
    }

    private static List<String> photos(List<String> in) {
        if (in == null) { return List.of(); }
        if (in.size() > 8) { throw new ApiException(HttpStatus.BAD_REQUEST, "PHOTOS_INVALID", "At most 8 photos"); }
        List<String> out = new ArrayList<>();
        for (String u : in) {
            String t = u == null ? "" : u.strip();
            if (!URL.matcher(t).matches()) { throw new ApiException(HttpStatus.BAD_REQUEST, "PHOTOS_INVALID", "Photos must be https links"); }
            out.add(t);
        }
        return out;
    }

    private static String text(String v, int max, String field, boolean required) {
        String t = v == null ? "" : v.strip();
        if ((required && t.isEmpty()) || t.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", field + (required ? " is required and" : "") + " must be at most " + max + " characters");
        }
        return t;
    }

    // ---- venues --------------------------------------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<VenueRow> venues(UUID actor, UUID partner) {
        partners.requireProcessing(actor, partner);
        return db.query("select v.id, v.name, v.description, v.address, v.district, v.latitude, v.longitude, v.photo_urls, v.rules, v.cancellation_hours, v.status, v.moderation_note, v.version, "
                + "(select count(*) from marketplace.leisure_events e where e.venue_id = v.id) from marketplace.leisure_venues v where v.partner_id = ? order by v.created_at, v.id",
                (rs, n) -> new VenueRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), (Double) rs.getObject(6), (Double) rs.getObject(7),
                        list(rs.getArray(8)), rs.getString(9), rs.getInt(10), rs.getString(11), rs.getString(12), rs.getLong(13), rs.getInt(14)), partner);
    }

    @Transactional
    public VenueRow createVenue(UUID actor, UUID partner, VenueInput in) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireEnabled();
        Long count = db.queryForObject("select count(*) from marketplace.leisure_venues where partner_id = ?", Long.class, partner);
        if (count != null && count >= 20) { throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_VENUES", "At most 20 venues per partner"); }
        UUID id = db.queryForObject("insert into marketplace.leisure_venues (partner_id, name, description, address, district, latitude, longitude, photo_urls, rules, cancellation_hours) "
                + "values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id", UUID.class, partner, text(in.name(), 120, "name", true), text(in.description(), 2000, "description", false),
                text(in.address(), 200, "address", true), text(in.district(), 80, "district", false), in.latitude(), in.longitude(), photos(in.photoUrls()).toArray(new String[0]),
                text(in.rules(), 1500, "rules", false), hours(in.cancellationHours()));
        audit(actor, partner, "VENUE_CREATED", id.toString(), null);
        return venue(partner, id);
    }

    private static int hours(Integer h) {
        int v = h == null ? 2 : h;
        if (v < 0 || v > 720) { throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "cancellationHours must be 0-720"); }
        return v;
    }

    @Transactional
    public VenueRow updateVenue(UUID actor, UUID partner, UUID id, VenueInput in, long version) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireOwnVenue(partner, id);
        int n = db.update("update marketplace.leisure_venues set name = ?, description = ?, address = ?, district = ?, latitude = ?, longitude = ?, photo_urls = ?, rules = ?, cancellation_hours = ?, "
                + "updated_at = now(), version = version + 1 where id = ? and partner_id = ? and version = ? and status <> 'BLOCKED'", text(in.name(), 120, "name", true),
                text(in.description(), 2000, "description", false), text(in.address(), 200, "address", true), text(in.district(), 80, "district", false), in.latitude(), in.longitude(),
                photos(in.photoUrls()).toArray(new String[0]), text(in.rules(), 1500, "rules", false), hours(in.cancellationHours()), id, partner, version);
        if (n == 0) { throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "Reload the venue (it changed or is blocked)"); }
        audit(actor, partner, "VENUE_UPDATED", id.toString(), null);
        return venue(partner, id);
    }

    @Transactional
    public VenueRow submitVenue(UUID actor, UUID partner, UUID id) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireEnabled();
        requireOwnVenue(partner, id);
        if (db.update("update marketplace.leisure_venues set status = 'PENDING', moderation_note = null, version = version + 1, updated_at = now() where id = ? and status in ('DRAFT', 'REJECTED')", id) == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "Only a draft or rejected venue can be submitted");
        }
        audit(actor, partner, "VENUE_SUBMITTED", id.toString(), null);
        return venue(partner, id);
    }

    private VenueRow venue(UUID partner, UUID id) {
        return db.query("select v.id, v.name, v.description, v.address, v.district, v.latitude, v.longitude, v.photo_urls, v.rules, v.cancellation_hours, v.status, v.moderation_note, v.version, "
                + "(select count(*) from marketplace.leisure_events e where e.venue_id = v.id) from marketplace.leisure_venues v where v.id = ? and v.partner_id = ?",
                (rs, n) -> new VenueRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), (Double) rs.getObject(6), (Double) rs.getObject(7),
                        list(rs.getArray(8)), rs.getString(9), rs.getInt(10), rs.getString(11), rs.getString(12), rs.getLong(13), rs.getInt(14)), id, partner)
                .stream().findFirst().orElseThrow(() -> notFound("VENUE_NOT_FOUND"));
    }

    // ---- events --------------------------------------------------------------------------------------------------------------

    private static final String EVENT_SELECT = "select e.id, e.venue_id, v.name, e.category_code, e.booking_type, e.title, e.description, e.photo_urls, e.duration_minutes, e.min_age, "
            + "e.family_friendly, e.max_guests, e.confirmation, e.needs_executor, e.status, e.moderation_note, e.version, "
            + "(select count(*) from marketplace.leisure_sessions s where s.event_id = e.id and s.status = 'SCHEDULED' and s.starts_at > now()) "
            + "from marketplace.leisure_events e join marketplace.leisure_venues v on v.id = e.venue_id ";

    private static EventRow eventRow(java.sql.ResultSet rs, int n) throws SQLException {
        return new EventRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7), list(rs.getArray(8)),
                rs.getInt(9), rs.getInt(10), rs.getBoolean(11), rs.getInt(12), rs.getString(13), rs.getBoolean(14), rs.getString(15), rs.getString(16), rs.getLong(17), rs.getInt(18));
    }

    @Transactional(readOnly = true)
    public List<EventRow> events(UUID actor, UUID partner, UUID venueId, String product) {
        partners.requireProcessing(actor, partner);
        String pr = product(product);
        return db.query(EVENT_SELECT + "where v.partner_id = ? and (?::uuid is null or e.venue_id = ?::uuid) "
                + "and (?::text is null or (select c.product from marketplace.leisure_categories c where c.code = e.category_code) = ?::text) order by e.created_at desc, e.id limit 200",
                LeisurePartnerService::eventRow, partner, venueId, venueId, pr, pr);
    }

    @Transactional
    public EventRow createEvent(UUID actor, UUID partner, UUID venueId, EventInput in) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireEnabled();
        requireOwnVenue(partner, venueId);
        if (in.categoryCode() != null) {
            String product = db.query("select product from marketplace.leisure_categories where code = ?", (rs, n) -> rs.getString(1),
                    in.categoryCode().toUpperCase(java.util.Locale.ROOT)).stream().findFirst().orElse(null);
            if (product != null && !toggles.enabled("EVENTS".equals(product) ? FeatureToggles.Feature.EVENTS : FeatureToggles.Feature.LEISURE)) {
                throw new ApiException(HttpStatus.CONFLICT, "EVENTS".equals(product) ? "EVENTS_DISABLED" : "LEISURE_DISABLED", "This product is switched off; new events are not accepted");
            }
        }
        Long count = db.queryForObject("select count(*) from marketplace.leisure_events where venue_id = ?", Long.class, venueId);
        if (count != null && count >= 100) { throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_EVENTS", "At most 100 events per venue"); }
        Valid v = validate(in);
        UUID id = db.queryForObject("insert into marketplace.leisure_events (venue_id, category_code, booking_type, title, description, photo_urls, duration_minutes, min_age, family_friendly, "
                + "max_guests, confirmation, needs_executor) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id", UUID.class, venueId, v.category, v.type, v.title, v.description,
                v.photos.toArray(new String[0]), v.duration, v.minAge, v.family, v.maxGuests, v.confirmation, v.executor);
        audit(actor, partner, "EVENT_CREATED", id.toString(), v.title);
        return event(partner, id);
    }

    private record Valid(String category, String type, String title, String description, List<String> photos, int duration, int minAge, boolean family, int maxGuests,
            String confirmation, boolean executor) {}

    private Valid validate(EventInput in) {
        String category = in.categoryCode() == null ? "" : in.categoryCode().strip().toUpperCase(Locale.ROOT);
        var cat = db.query("select default_booking_type, needs_executor from marketplace.leisure_categories where code = ? and enabled",
                (rs, n) -> new Object[] {rs.getString(1), rs.getBoolean(2)}, category).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "CATEGORY_INVALID", "Unknown or disabled category"));
        String type = in.bookingType() == null || in.bookingType().isBlank() ? (String) cat[0] : in.bookingType().strip().toUpperCase(Locale.ROOT);
        if (!TYPES.contains(type)) { throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "BOOKING_TYPE_INVALID", "Unknown booking type"); }
        int duration = in.durationMinutes() == null ? 90 : in.durationMinutes();
        int minAge = in.minAge() == null ? 0 : in.minAge();
        int maxGuests = in.maxGuests() == null ? 10 : in.maxGuests();
        if (duration < 10 || duration > 1440 || minAge < 0 || minAge > 21 || maxGuests < 1 || maxGuests > 100) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "duration 10-1440, age 0-21, guests 1-100");
        }
        String confirmation = in.confirmation() == null ? "AUTO" : in.confirmation().toUpperCase(Locale.ROOT);
        if (!List.of("AUTO", "MANUAL").contains(confirmation)) { throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "confirmation is AUTO or MANUAL"); }
        return new Valid(category, type, text(in.title(), 140, "title", true), text(in.description(), 2000, "description", false), photos(in.photoUrls()), duration, minAge,
                Boolean.TRUE.equals(in.familyFriendly()), maxGuests, confirmation, in.needsExecutor() == null ? (boolean) cat[1] : in.needsExecutor());
    }

    @Transactional
    public EventRow updateEvent(UUID actor, UUID partner, UUID id, EventInput in, long version) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireOwnEvent(partner, id);
        Valid v = validate(in);
        int n = db.update("update marketplace.leisure_events set category_code = ?, title = ?, description = ?, photo_urls = ?, duration_minutes = ?, min_age = ?, family_friendly = ?, max_guests = ?, "
                + "confirmation = ?, needs_executor = ?, updated_at = now(), version = version + 1 where id = ? and version = ? and status <> 'BLOCKED' and booking_type = ?", v.category, v.title,
                v.description, v.photos.toArray(new String[0]), v.duration, v.minAge, v.family, v.maxGuests, v.confirmation, v.executor, id, version, v.type);
        if (n == 0) { throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "Reload the event (it changed, is blocked, or its booking type cannot change)"); }
        audit(actor, partner, "EVENT_UPDATED", id.toString(), v.title);
        return event(partner, id);
    }

    @Transactional
    public EventRow submitEvent(UUID actor, UUID partner, UUID id) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireEnabled();
        requireOwnEvent(partner, id);
        if (db.queryForObject("select count(*) from marketplace.leisure_ticket_types where event_id = ? and active", Integer.class, id) == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "TICKET_TYPES_REQUIRED", "Add at least one ticket type before submitting");
        }
        if (db.update("update marketplace.leisure_events set status = 'PENDING', moderation_note = null, version = version + 1, updated_at = now() where id = ? and status in ('DRAFT', 'REJECTED', 'ARCHIVED')", id) == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "Only a draft, rejected or archived event can be submitted");
        }
        audit(actor, partner, "EVENT_SUBMITTED", id.toString(), null);
        return event(partner, id);
    }

    @Transactional
    public EventRow archiveEvent(UUID actor, UUID partner, UUID id) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireOwnEvent(partner, id);
        if (db.queryForObject("select count(*) from marketplace.leisure_sessions s where s.event_id = ? and s.status = 'SCHEDULED' and s.starts_at > now() "
                + "and exists (select 1 from transactions.leisure_orders o where o.session_id = s.id and o.status in ('PENDING', 'CONFIRMED'))", Integer.class, id) > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "HAS_UPCOMING_ORDERS", "Cancel the upcoming sessions with bookings first");
        }
        if (db.update("update marketplace.leisure_events set status = 'ARCHIVED', version = version + 1, updated_at = now() where id = ? and status in ('PUBLISHED', 'PENDING', 'DRAFT', 'REJECTED')", id) == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "The event cannot be archived in its current status");
        }
        audit(actor, partner, "EVENT_ARCHIVED", id.toString(), null);
        return event(partner, id);
    }

    private EventRow event(UUID partner, UUID id) {
        return db.query(EVENT_SELECT + "where e.id = ? and v.partner_id = ?", LeisurePartnerService::eventRow, id, partner).stream().findFirst().orElseThrow(() -> notFound("EVENT_NOT_FOUND"));
    }

    // ---- ticket types --------------------------------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<TicketTypeRow> ticketTypes(UUID actor, UUID partner, UUID eventId) {
        partners.requireProcessing(actor, partner);
        requireOwnEvent(partner, eventId);
        return db.query("select id, name, price_minor, currency, pricing, seat_zone, active from marketplace.leisure_ticket_types where event_id = ? order by sort_order, price_minor",
                (rs, n) -> new TicketTypeRow(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getBoolean(7)), eventId);
    }

    @Transactional
    public TicketTypeRow saveTicketType(UUID actor, UUID partner, UUID eventId, UUID typeId, TicketTypeInput in) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireOwnEvent(partner, eventId);
        String name = text(in.name(), 60, "name", true);
        if (in.priceMinor() == null || in.priceMinor() < 0 || in.priceMinor() > 100_000_000_00L) { throw new ApiException(HttpStatus.BAD_REQUEST, "PRICE_INVALID", "Price must be between 0 and 100,000,000 KZT"); }
        String bookingType = db.queryForObject("select booking_type from marketplace.leisure_events where id = ?", String.class, eventId);
        String pricing = in.pricing() == null ? ("TIME_SLOT".equals(bookingType) || "PRIVATE_SESSION".equals(bookingType) ? "PER_BOOKING" : "PER_TICKET") : in.pricing().toUpperCase(Locale.ROOT);
        boolean perBooking = "TIME_SLOT".equals(bookingType) || "PRIVATE_SESSION".equals(bookingType);
        if (!List.of("PER_TICKET", "PER_BOOKING").contains(pricing) || perBooking != "PER_BOOKING".equals(pricing)) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PRICING_INVALID", "TIME_SLOT and PRIVATE_SESSION events are priced per booking, the others per ticket");
        }
        String zone = in.seatZone() == null || in.seatZone().isBlank() ? null : in.seatZone().strip().toUpperCase(Locale.ROOT);
        if (typeId == null && db.queryForObject("select count(*) from marketplace.leisure_ticket_types where event_id = ? and name = ?", Integer.class, eventId, name) > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "TICKET_TYPE_EXISTS", "A ticket type with this name already exists");
        }
        try {
            UUID id;
            if (typeId == null) {
                id = db.queryForObject("insert into marketplace.leisure_ticket_types (event_id, name, price_minor, pricing, seat_zone, active) values (?, ?, ?, ?, ?, ?) returning id",
                        UUID.class, eventId, name, in.priceMinor(), pricing, zone, in.active() == null || in.active());
                audit(actor, partner, "TICKET_TYPE_CREATED", id.toString(), name + " " + in.priceMinor());
            } else {
                Long old = db.query("select price_minor from marketplace.leisure_ticket_types where id = ? and event_id = ? for update", (rs, n) -> rs.getLong(1), typeId, eventId)
                        .stream().findFirst().orElseThrow(() -> notFound("TICKET_TYPE_NOT_FOUND"));
                db.update("update marketplace.leisure_ticket_types set name = ?, price_minor = ?, pricing = ?, seat_zone = ?, active = ? where id = ?", name, in.priceMinor(), pricing, zone,
                        in.active() == null || in.active(), typeId);
                id = typeId;
                audit(actor, partner, "TICKET_TYPE_UPDATED", id.toString(), name + " " + old + " -> " + in.priceMinor());
            }
            return db.query("select id, name, price_minor, currency, pricing, seat_zone, active from marketplace.leisure_ticket_types where id = ?",
                    (rs, n) -> new TicketTypeRow(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getBoolean(7)), id).get(0);
        } catch (DuplicateKeyException e) {
            throw new ApiException(HttpStatus.CONFLICT, "TICKET_TYPE_EXISTS", "A ticket type with this name already exists");
        }
    }

    // ---- sessions ------------------------------------------------------------------------------------------------------------

    @Transactional
    public List<SessionRow> createSessions(UUID actor, UUID partner, UUID eventId, SessionInput in) {
        partners.requireProcessing(actor, partner, MANAGE);
        requireEnabled();
        requireOwnEvent(partner, eventId);
        if (in.startsAt() == null || in.startsAt().isEmpty() || in.startsAt().size() > 60) { throw new ApiException(HttpStatus.BAD_REQUEST, "SESSIONS_INVALID", "Provide 1-60 start times"); }
        var ev = db.query("select booking_type, duration_minutes, status from marketplace.leisure_events where id = ? for update", (rs, n) -> new Object[] {rs.getString(1), rs.getInt(2), rs.getString(3)}, eventId).get(0);
        if ("BLOCKED".equals(ev[2])) { throw new ApiException(HttpStatus.CONFLICT, "EVENT_BLOCKED", "The event is blocked"); }
        String type = (String) ev[0];
        int duration = (int) ev[1];
        boolean seatMap = "SEAT_MAP".equals(type);
        int capacity;
        int rows = 0;
        int perRow = 0;
        if (seatMap) {
            rows = in.rows() == null ? 0 : in.rows();
            perRow = in.seatsPerRow() == null ? 0 : in.seatsPerRow();
            if (rows < 1 || rows > 26 || perRow < 1 || perRow > 40) { throw new ApiException(HttpStatus.BAD_REQUEST, "SEAT_LAYOUT_INVALID", "rows 1-26 and seatsPerRow 1-40 are required"); }
            capacity = rows * perRow;
        } else if ("PRIVATE_SESSION".equals(type)) {
            capacity = 1;
        } else {
            capacity = in.capacity() == null ? 0 : in.capacity();
            if (capacity < 1 || capacity > 5000) { throw new ApiException(HttpStatus.BAD_REQUEST, "CAPACITY_INVALID", "capacity must be 1-5000"); }
        }
        int vip = in.vipRows() == null ? 0 : Math.max(0, Math.min(in.vipRows(), rows));
        List<SessionRow> out = new ArrayList<>();
        for (OffsetDateTime start : in.startsAt()) {
            if (start == null || !start.isAfter(OffsetDateTime.now())) { throw new ApiException(HttpStatus.BAD_REQUEST, "SESSION_IN_PAST", "Sessions must start in the future"); }
            if (db.queryForObject("select count(*) from marketplace.leisure_sessions where event_id = ? and starts_at = ?", Integer.class, eventId, start) > 0) {
                throw new ApiException(HttpStatus.CONFLICT, "SESSION_EXISTS", "A session already starts at " + start);
            }
            UUID id;
            try {
                id = db.queryForObject("insert into marketplace.leisure_sessions (event_id, starts_at, ends_at, capacity) values (?, ?, ?, ?) returning id", UUID.class, eventId, start,
                        start.plusMinutes(duration), capacity);
            } catch (DuplicateKeyException e) {
                throw new ApiException(HttpStatus.CONFLICT, "SESSION_EXISTS", "A session already starts at " + start);
            }
            if (seatMap) {
                for (int r = 0; r < rows; r++) {
                    String label = String.valueOf((char) ('A' + r));
                    for (int s = 1; s <= perRow; s++) {
                        db.update("insert into marketplace.leisure_seats (session_id, row_label, seat_number, zone) values (?, ?, ?, ?)", id, label, s, r < vip ? "VIP" : "STANDARD");
                    }
                }
            }
            out.add(session(id));
        }
        audit(actor, partner, "SESSIONS_CREATED", eventId.toString(), out.size() + " x " + capacity);
        return out;
    }

    @Transactional(readOnly = true)
    public List<SessionRow> sessions(UUID actor, UUID partner, UUID eventId, boolean past, int limit, int offset) {
        partners.requireProcessing(actor, partner);
        requireOwnEvent(partner, eventId);
        List<UUID> ids = db.queryForList("select id from marketplace.leisure_sessions where event_id = ? and " + (past ? "ends_at <= now()" : "ends_at > now()")
                + " order by starts_at " + (past ? "desc" : "asc") + " limit ? offset ?", UUID.class, eventId, Math.max(1, Math.min(limit, 100)), Math.max(0, offset));
        return ids.stream().map(this::session).toList();
    }

    private SessionRow session(UUID id) {
        return db.query("""
                select s.id, e.id, e.title, s.starts_at, s.ends_at, s.capacity,
                  (select count(*) from transactions.leisure_tickets t where t.session_id = s.id and t.status in ('PENDING', 'VALID', 'USED')),
                  (select count(*) from transactions.leisure_hold_lines hl join transactions.leisure_holds h on h.id = hl.hold_id where h.session_id = s.id and h.status = 'ACTIVE' and h.expires_at > now()),
                  coalesce((select sum(t.admits) from transactions.leisure_tickets t where t.session_id = s.id and t.status = 'USED'), 0), s.status, s.cancel_reason
                from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id where s.id = ?""",
                (rs, n) -> new SessionRow(rs.getString(1), rs.getString(2), rs.getString(3), kz.kunde.leisure.LeisureTime.local(rs, 4), kz.kunde.leisure.LeisureTime.local(rs, 5), rs.getInt(6),
                        rs.getInt(7), rs.getInt(8), rs.getInt(9), rs.getString(10), rs.getString(11)), id).get(0);
    }

    @Transactional
    public SessionRow setCapacity(UUID actor, UUID partner, UUID sessionId, int capacity) {
        partners.requireProcessing(actor, partner, MANAGE);
        UUID eventId = ownSession(partner, sessionId);
        String type = db.queryForObject("select booking_type from marketplace.leisure_events where id = ?", String.class, eventId);
        if ("SEAT_MAP".equals(type) || "PRIVATE_SESSION".equals(type)) { throw new ApiException(HttpStatus.CONFLICT, "CAPACITY_FIXED", "The capacity of this booking type follows its layout"); }
        db.query("select 1 from marketplace.leisure_sessions where id = ? for update", rs -> {}, sessionId);
        SessionRow s = session(sessionId);
        if (capacity < Math.max(1, s.sold() + s.held()) || capacity > 5000) {
            throw new ApiException(HttpStatus.CONFLICT, "CAPACITY_BELOW_SOLD", "Capacity cannot be below the places already sold or held");
        }
        db.update("update marketplace.leisure_sessions set capacity = ?, version = version + 1 where id = ?", capacity, sessionId);
        audit(actor, partner, "SESSION_CAPACITY", sessionId.toString(), s.capacity() + " -> " + capacity);
        return session(sessionId);
    }

    private UUID ownSession(UUID partner, UUID sessionId) {
        return db.query("select s.event_id from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id join marketplace.leisure_venues v on v.id = e.venue_id "
                + "where s.id = ? and v.partner_id = ?", (rs, n) -> rs.getObject(1, UUID.class), sessionId, partner).stream().findFirst().orElseThrow(() -> notFound("SESSION_NOT_FOUND"));
    }

    /** Cancels the session and every live booking of it; each customer is refunded (test payments) and each ticket stops working. */
    @Transactional
    public SessionRow cancelSession(UUID actor, UUID partner, UUID sessionId, String reason) {
        partners.requireProcessing(actor, partner, MANAGE);
        ownSession(partner, sessionId);
        String why = text(reason, 200, "reason", true);
        db.query("select 1 from marketplace.leisure_sessions where id = ? for update", rs -> {}, sessionId);
        if (db.update("update marketplace.leisure_sessions set status = 'CANCELLED', cancel_reason = ?, version = version + 1 where id = ? and status = 'SCHEDULED'", why, sessionId) == 0) {
            return session(sessionId);
        }
        List<UUID> live = db.queryForList("select id from transactions.leisure_orders where session_id = ? and status in ('PENDING', 'CONFIRMED') order by id for update", UUID.class, sessionId);
        for (UUID order : live) { orders.cancelOrder(order, "PARTNER", actor, "Session cancelled: " + why); }
        audit(actor, partner, "SESSION_CANCELLED", sessionId.toString(), live.size() + " bookings: " + why);
        return session(sessionId);
    }

    // ---- bookings ------------------------------------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<PartnerOrder> orders(UUID actor, UUID partner, String scope, UUID eventId, UUID sessionId, int limit, int offset, String product) {
        partners.requireProcessing(actor, partner);
        String pr = product(product);
        String filter = switch (scope) {
            case "requests" -> "o.status = 'PENDING' and s.ends_at > now()";
            case "history" -> "(o.status = 'CANCELLED' or s.ends_at <= now())";
            default -> "o.status in ('PENDING', 'CONFIRMED') and s.ends_at > now()";
        };
        String order = "history".equals(scope) ? "s.starts_at desc" : "s.starts_at asc";
        List<UUID> ids = db.queryForList("select o.id from transactions.leisure_orders o join marketplace.leisure_sessions s on s.id = o.session_id join marketplace.leisure_venues v on v.id = o.venue_id "
                + "join marketplace.leisure_events e on e.id = o.event_id join marketplace.leisure_categories c on c.code = e.category_code "
                + "where v.partner_id = ? and " + filter + " and (?::uuid is null or o.event_id = ?::uuid) and (?::uuid is null or o.session_id = ?::uuid) and (?::text is null or c.product = ?::text) "
                + "order by " + order + ", o.id limit ? offset ?",
                UUID.class, partner, eventId, eventId, sessionId, sessionId, pr, pr, Math.max(1, Math.min(limit, 100)), Math.max(0, offset));
        return ids.stream().map(id -> partnerOrder(partner, id)).toList();
    }

    @Transactional(readOnly = true)
    public PartnerOrder order(UUID actor, UUID partner, UUID id) {
        partners.requireProcessing(actor, partner);
        return partnerOrder(partner, id);
    }

    private PartnerOrder partnerOrder(UUID partner, UUID id) {
        var row = db.query("""
                select o.id, o.status, o.session_id, e.title, v.name, s.starts_at, o.guests, o.total_minor, o.payment_method, o.created_at, o.cancelled_by, o.cancel_reason
                from transactions.leisure_orders o join marketplace.leisure_sessions s on s.id = o.session_id join marketplace.leisure_events e on e.id = o.event_id
                join marketplace.leisure_venues v on v.id = o.venue_id where o.id = ? and v.partner_id = ?""", (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getString(3),
                rs.getString(4), rs.getString(5), kz.kunde.leisure.LeisureTime.local(rs, 6), rs.getInt(7), rs.getLong(8), rs.getString(9), kz.kunde.leisure.LeisureTime.local(rs, 10),
                rs.getString(11), rs.getString(12)}, id, partner).stream().findFirst().orElseThrow(() -> notFound("ORDER_NOT_FOUND"));
        List<LeisureOrderService.TicketView> tickets = db.query("""
                select t.id, t.status, tt.name, st.row_label || st.seat_number, t.admits, t.price_minor, t.used_at from transactions.leisure_tickets t
                join marketplace.leisure_ticket_types tt on tt.id = t.ticket_type_id left join marketplace.leisure_seats st on st.id = t.seat_id where t.order_id = ?
                order by st.row_label, st.seat_number, t.created_at, t.id""", (rs, n) -> new LeisureOrderService.TicketView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getInt(5), rs.getLong(6), null, kz.kunde.leisure.LeisureTime.local(rs, 7)), id);
        return new PartnerOrder((String) row[0], (String) row[1], (String) row[2], (String) row[3], (String) row[4], (OffsetDateTime) row[5], (int) row[6], (long) row[7], (String) row[8],
                payments.ofOrder(id), ((String) row[0]).substring(0, 8).toUpperCase(Locale.ROOT), (OffsetDateTime) row[9], (String) row[10], (String) row[11], tickets);
    }

    public enum Action { CONFIRM, REJECT, CANCEL }

    @Transactional
    public PartnerOrder act(UUID actor, UUID partner, UUID id, Action action, String reason) {
        partners.requireProcessing(actor, partner, action == Action.CANCEL ? MANAGE : new Role[0]);
        var row = db.query("select o.status, o.session_id from transactions.leisure_orders o join marketplace.leisure_venues v on v.id = o.venue_id where o.id = ? and v.partner_id = ? for update of o",
                (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class)}, id, partner).stream().findFirst().orElseThrow(() -> notFound("ORDER_NOT_FOUND"));
        db.query("select 1 from marketplace.leisure_sessions where id = ? for update", rs -> {}, row[1]);
        String status = (String) row[0];
        String why = reason == null ? null : text(reason, 200, "reason", false);
        switch (action) {
            case CONFIRM -> {
                if ("CONFIRMED".equals(status)) { break; }
                if (!"PENDING".equals(status)) { throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "Only a pending booking can be confirmed"); }
                if (Boolean.FALSE.equals(db.queryForObject("select starts_at > now() from marketplace.leisure_sessions where id = ?", Boolean.class, row[1]))) {
                    throw new ApiException(HttpStatus.CONFLICT, "SESSION_STARTED", "The session has already started");
                }
                db.update("update transactions.leisure_orders set status = 'CONFIRMED', updated_at = now(), version = version + 1 where id = ?", id);
                db.update("update transactions.leisure_tickets set status = 'VALID' where order_id = ? and status = 'PENDING'", id);
                payments.capture(id, "PARTNER", actor);
                orders.event(id, "CONFIRMED", "PARTNER", actor, why);
            }
            case REJECT -> {
                if ("CANCELLED".equals(status)) { break; }
                if (!"PENDING".equals(status)) { throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "Only a pending booking can be rejected"); }
                orders.cancelOrder(id, "PARTNER", actor, why == null || why.isBlank() ? "Rejected by the organiser" : why);
            }
            case CANCEL -> {
                if ("CANCELLED".equals(status)) { break; }
                if (Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from transactions.leisure_tickets where order_id = ? and status = 'USED')", Boolean.class, id))) {
                    throw new ApiException(HttpStatus.CONFLICT, "TICKET_USED", "A ticket of this booking has already been used");
                }
                orders.cancelOrder(id, "PARTNER", actor, why == null || why.isBlank() ? "Cancelled by the organiser" : why);
            }
        }
        audit(actor, partner, "ORDER_" + action.name(), id.toString(), why);
        return partnerOrder(partner, id);
    }

    // ---- check-in ------------------------------------------------------------------------------------------------------------

    /**
     * Gate scan. The code is verified on the server: signature-free design (a 128-bit random secret per ticket), compared in constant time. The
     * ticket row is locked, so two simultaneous scans of one ticket admit exactly one. Every outcome, also a refusal, is written to the gate log.
     * A ticket of another organisation is refused without revealing anything about it.
     */
    @Transactional
    public CheckinResult checkin(UUID actor, UUID partner, String code, UUID expectedSession) {
        partners.requireProcessing(actor, partner);
        return scan(actor, partner, code, expectedSession);
    }

    /**
     * Gate scan by a controller (executor) of Events. Access exists only for a ticket of a session to which the organiser assigned this person as
     * GATE and who accepted it; anything else is ACCESS_DENIED without a word about the ticket. Verification itself is {@link #scan}.
     */
    @Transactional
    public CheckinResult gateScan(UUID executor, String code) {
        Matcher m = CODE.matcher(code == null ? "" : code.strip());
        if (!m.matches()) { return new CheckinResult("INVALID", false, "Unreadable code", null, null, null, null, null, null, 0, null); }
        UUID ticketId = UUID.fromString(m.group(1).length() == 36 ? m.group(1) : "00000000-0000-0000-0000-000000000000");
        var ctx = db.query("select s.id, v.partner_id, v.id from transactions.leisure_tickets t join marketplace.leisure_sessions s on s.id = t.session_id "
                + "join marketplace.leisure_events e on e.id = s.event_id join marketplace.leisure_venues v on v.id = e.venue_id where t.id = ?",
                (rs, n) -> new UUID[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class)}, ticketId).stream().findFirst().orElse(null);
        if (ctx == null) { return new CheckinResult("INVALID", false, "Ticket not found", null, null, null, null, null, null, 0, null); }
        boolean assigned = Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from transactions.leisure_assignments where session_id = ? and executor_user_id = ? "
                + "and role = 'GATE' and status in ('ACCEPTED', 'STARTED'))", Boolean.class, ctx[0], executor));
        if (!assigned) {
            db.update("insert into transactions.leisure_checkins (ticket_id, session_id, venue_id, partner_id, actor_user_id, result, admits) values (?, ?, ?, ?, ?, 'ACCESS_DENIED', 0)",
                    ticketId, ctx[0], ctx[2], ctx[1], executor);
            return new CheckinResult("ACCESS_DENIED", false, "You are not assigned to this session", null, null, null, null, null, null, 0, null);
        }
        return scan(executor, ctx[1], code, ctx[0]);
    }

    private CheckinResult scan(UUID actor, UUID partner, String code, UUID expectedSession) {
        Matcher m = CODE.matcher(code == null ? "" : code.strip());
        if (!m.matches()) { return refuse(actor, partner, null, null, null, "INVALID", "Unreadable code", null); }
        UUID ticketId;
        try { ticketId = UUID.fromString(m.group(1)); } catch (IllegalArgumentException e) { return refuse(actor, partner, null, null, null, "INVALID", "Unreadable code", null); }
        var row = db.query("""
                select t.id, t.status, t.nonce, t.admits, t.used_at, s.id, s.starts_at, s.ends_at, s.status, v.id, v.partner_id, e.title, tt.name, st.row_label || st.seat_number
                from transactions.leisure_tickets t join marketplace.leisure_sessions s on s.id = t.session_id join marketplace.leisure_events e on e.id = s.event_id
                join marketplace.leisure_venues v on v.id = e.venue_id join marketplace.leisure_ticket_types tt on tt.id = t.ticket_type_id left join marketplace.leisure_seats st on st.id = t.seat_id
                where t.id = ? for update of t""", (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getString(3), rs.getInt(4), kz.kunde.leisure.LeisureTime.local(rs, 5),
                rs.getObject(6, UUID.class), kz.kunde.leisure.LeisureTime.local(rs, 7), kz.kunde.leisure.LeisureTime.local(rs, 8), rs.getString(9), rs.getObject(10, UUID.class),
                rs.getObject(11, UUID.class), rs.getString(12), rs.getString(13), rs.getString(14)}, ticketId).stream().findFirst().orElse(null);
        if (row == null) { return refuse(actor, partner, null, null, null, "INVALID", "Ticket not found", null); }
        boolean secretOk = MessageDigest.isEqual(((String) row[2]).getBytes(java.nio.charset.StandardCharsets.UTF_8), m.group(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        if (!secretOk) { return refuse(actor, partner, null, null, null, "INVALID", "Invalid ticket", null); }
        if (!partner.equals(row[10])) { return refuse(actor, partner, null, null, null, "WRONG_ORGANIZATION", "This ticket belongs to another organiser", null); }
        UUID sessionId = (UUID) row[5];
        UUID venueId = (UUID) row[9];
        OffsetDateTime starts = (OffsetDateTime) row[6];
        OffsetDateTime ends = (OffsetDateTime) row[7];
        String title = (String) row[11];
        UUID ticket = UUID.fromString((String) row[0]);
        Object[] info = {title, sessionId, starts, row[13], row[12], row[3], row[4]};
        if (expectedSession != null && !expectedSession.equals(sessionId)) { return refuse(actor, partner, ticket, sessionId, venueId, "WRONG_SESSION", "The ticket is for another session", info); }
        return switch ((String) row[1]) {
            case "USED" -> refuse(actor, partner, ticket, sessionId, venueId, "DUPLICATE", "Already used", info);
            case "CANCELLED" -> refuse(actor, partner, ticket, sessionId, venueId, "CANCELLED", "The booking was cancelled", info);
            case "PENDING" -> refuse(actor, partner, ticket, sessionId, venueId, "NOT_CONFIRMED", "The booking is not confirmed yet", info);
            default -> {
                if ("CANCELLED".equals(row[8])) { yield refuse(actor, partner, ticket, sessionId, venueId, "CANCELLED", "The session was cancelled", info); }
                OffsetDateTime now = OffsetDateTime.now();
                if (!now.isBefore(ends)) { yield refuse(actor, partner, ticket, sessionId, venueId, "EXPIRED", "The session is over", info); }
                if (now.isBefore(starts.minusHours(2))) { yield refuse(actor, partner, ticket, sessionId, venueId, "TOO_EARLY", "Entry opens 2 hours before the start", info); }
                db.update("update transactions.leisure_tickets set status = 'USED', used_at = now(), used_by = ? where id = ?", actor, ticket);
                db.update("insert into transactions.leisure_checkins (ticket_id, session_id, venue_id, partner_id, actor_user_id, result, admits) values (?, ?, ?, ?, ?, 'ADMITTED', ?)",
                        ticket, sessionId, venueId, partner, actor, row[3]);
                yield new CheckinResult("ADMITTED", true, "Welcome", ticket.toString(), title, sessionId.toString(), starts, (String) row[13], (String) row[12], (int) row[3], now);
            }
        };
    }

    private CheckinResult refuse(UUID actor, UUID partner, UUID ticket, UUID session, UUID venue, String result, String message, Object[] info) {
        db.update("insert into transactions.leisure_checkins (ticket_id, session_id, venue_id, partner_id, actor_user_id, result, admits) values (?, ?, ?, ?, ?, ?, 0)",
                ticket, session, venue, partner, actor, result);
        if (info == null || "WRONG_ORGANIZATION".equals(result)) { return new CheckinResult(result, false, message, null, null, null, null, null, null, 0, null); }
        return new CheckinResult(result, false, message, ticket == null ? null : ticket.toString(), (String) info[0], info[1].toString(), (OffsetDateTime) info[2], (String) info[3],
                (String) info[4], (int) info[5], (OffsetDateTime) info[6]);
    }

    @Transactional(readOnly = true)
    public List<CheckinRow> checkins(UUID actor, UUID partner, UUID sessionId, int limit, int offset) {
        partners.requireProcessing(actor, partner);
        return db.query("select c.id, c.result, c.admits, coalesce(e.title, ''), s.starts_at, c.occurred_at from transactions.leisure_checkins c left join marketplace.leisure_sessions s on s.id = c.session_id "
                + "left join marketplace.leisure_events e on e.id = s.event_id where c.partner_id = ? and (?::uuid is null or c.session_id = ?::uuid) order by c.id desc limit ? offset ?",
                (rs, n) -> new CheckinRow(rs.getLong(1), rs.getString(2), rs.getInt(3), rs.getString(4), kz.kunde.leisure.LeisureTime.local(rs, 5), kz.kunde.leisure.LeisureTime.local(rs, 6)),
                partner, sessionId, sessionId, Math.max(1, Math.min(limit, 100)), Math.max(0, offset));
    }

    @Transactional(readOnly = true)
    public Stats stats(UUID actor, UUID partner, int days, String product) {
        partners.requireProcessing(actor, partner);
        String pr = product(product);
        int d = Math.max(1, Math.min(days, 90));
        var r = db.query("""
                select count(*), coalesce(sum(o.total_minor), 0), coalesce(sum((select count(*) from transactions.leisure_tickets t where t.order_id = o.id)), 0),
                       coalesce(sum((select coalesce(sum(t.admits), 0) from transactions.leisure_tickets t where t.order_id = o.id and t.status = 'USED')), 0)
                from transactions.leisure_orders o join marketplace.leisure_venues v on v.id = o.venue_id
                join marketplace.leisure_events e on e.id = o.event_id join marketplace.leisure_categories c on c.code = e.category_code
                where v.partner_id = ? and o.status = 'CONFIRMED' and o.created_at > now() - (? * interval '1 day') and (?::text is null or c.product = ?::text)""",
                (rs, n) -> new long[] {rs.getLong(1), rs.getLong(2), rs.getLong(3), rs.getLong(4)}, partner, d, pr, pr).get(0);
        long upcoming = db.queryForObject("select count(*) from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id join marketplace.leisure_venues v on v.id = e.venue_id "
                + "join marketplace.leisure_categories c on c.code = e.category_code "
                + "where v.partner_id = ? and s.status = 'SCHEDULED' and s.starts_at > now() and (?::text is null or c.product = ?::text)", Long.class, partner, pr, pr);
        return new Stats(d, r[0], r[2], r[1], r[3], upcoming);
    }

    /**
     * Sales report per event of this organiser (OWNER/MANAGER only): confirmed orders created in the window, tickets, money taken and refunded
     * (the DEV/TEST ledger), guests admitted at the gate, and the fill of the event's upcoming sessions. Only this partner's events are visible.
     */
    @Transactional(readOnly = true)
    public List<SalesLine> salesReport(UUID actor, UUID partner, int days, String product) {
        partners.requireProcessing(actor, partner, MANAGE);
        String pr = product(product);
        int d = Math.max(1, Math.min(days, 90));
        return db.query("""
                select e.id, e.title, e.category_code, c.product,
                  (select count(*) from marketplace.leisure_sessions s where s.event_id = e.id and s.status = 'SCHEDULED' and s.starts_at > now()),
                  (select coalesce(sum(s.capacity), 0) from marketplace.leisure_sessions s where s.event_id = e.id and s.status = 'SCHEDULED' and s.starts_at > now()),
                  (select count(*) from transactions.leisure_tickets t join marketplace.leisure_sessions s on s.id = t.session_id
                     where s.event_id = e.id and s.status = 'SCHEDULED' and s.starts_at > now() and t.status in ('PENDING', 'VALID', 'USED')),
                  (select count(*) from transactions.leisure_tickets t join transactions.leisure_orders o on o.id = t.order_id
                     where o.event_id = e.id and o.status = 'CONFIRMED' and t.status in ('VALID', 'USED') and o.created_at > now() - (? * interval '1 day')),
                  (select coalesce(sum(o.total_minor), 0) from transactions.leisure_orders o
                     where o.event_id = e.id and o.status = 'CONFIRMED' and o.created_at > now() - (? * interval '1 day')),
                  (select coalesce(sum(p.refunded_minor), 0) from transactions.leisure_payments p join transactions.leisure_orders o on o.id = p.order_id
                     where o.event_id = e.id and o.created_at > now() - (? * interval '1 day')),
                  (select coalesce(sum(t.admits), 0) from transactions.leisure_tickets t join marketplace.leisure_sessions s on s.id = t.session_id
                     where s.event_id = e.id and t.status = 'USED' and t.used_at > now() - (? * interval '1 day'))
                from marketplace.leisure_events e join marketplace.leisure_venues v on v.id = e.venue_id join marketplace.leisure_categories c on c.code = e.category_code
                where v.partner_id = ? and e.status in ('PUBLISHED', 'ARCHIVED') and (?::text is null or c.product = ?::text)
                order by 9 desc, e.title limit 100""", (rs, n) -> new SalesLine(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getInt(5), rs.getInt(6),
                rs.getInt(7), rs.getLong(8), rs.getLong(9), rs.getLong(10), rs.getLong(11)), d, d, d, d, partner, pr, pr);
    }

    @Transactional(readOnly = true)
    public List<AuditRow> history(UUID actor, UUID partner, int limit, int offset) {
        partners.requireProcessing(actor, partner, MANAGE);
        return db.query("select id, action, target, detail, actor_type, occurred_at from marketplace.leisure_audit where partner_id = ? order by id desc limit ? offset ?",
                (rs, n) -> new AuditRow(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), kz.kunde.leisure.LeisureTime.local(rs, 6)),
                partner, Math.max(1, Math.min(limit, 100)), Math.max(0, offset));
    }

    private static List<String> list(Array array) throws SQLException {
        return array == null ? List.of() : List.of((String[]) array.getArray());
    }
}
