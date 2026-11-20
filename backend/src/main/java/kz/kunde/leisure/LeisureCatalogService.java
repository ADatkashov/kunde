package kz.kunde.leisure;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Array;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Read side of Leisure: categories, search with filters, event details, sessions with live availability and seat maps. Only APPROVED venues and
 * PUBLISHED events with an upcoming session are offered, and nothing is offered while the Leisure switch is off (existing orders stay readable
 * through {@link LeisureOrderService}). Ratings come only from real published reviews; nothing here is random or invented.
 */
@Service
public class LeisureCatalogService {
    public static final ZoneId ALMATY = ZoneId.of("Asia/Almaty");
    /** Free units of session {@code s}: capacity minus live tickets minus units reserved by unexpired holds. */
    static final String FREE = """
            (s.capacity
              - (select count(*) from transactions.leisure_tickets t where t.session_id = s.id and t.status in ('PENDING', 'VALID', 'USED'))
              - (select count(*) from transactions.leisure_hold_lines hl join transactions.leisure_holds h on h.id = hl.hold_id
                   where h.session_id = s.id and h.status = 'ACTIVE' and h.expires_at > now()))""";

    public record Category(String code, String nameRu, String nameKk, String nameEn, String bookingType, boolean familyFriendly, boolean enabled) {}

    public record Card(String id, String title, String venueId, String venueName, String district, String address, String categoryCode,
            String bookingType, String photoUrl, long minPriceMinor, String currency, int minAge, boolean familyFriendly, Double rating,
            int reviewCount, OffsetDateTime nextSessionAt, String nextSessionId, int nextSessionFree, Double distanceKm) {}

    public record Search(String q, String category, String district, LocalDate date, LocalTime timeFrom, LocalTime timeTo, Long minPriceMinor,
            Long maxPriceMinor, Integer age, Integer guests, boolean availableOnly, Boolean family, Double minRating, Double lat, Double lng,
            Double radiusKm, String sort, String preset, int limit, int offset) {}

    public record TicketType(String id, String name, long priceMinor, String currency, String pricing, String zone) {}

    public record Venue(String id, String name, String description, String address, String district, Double latitude, Double longitude,
            List<String> photos, String rules, int cancellationHours) {}

    public record Detail(String id, String title, String description, List<String> photos, Category category, String bookingType, int durationMinutes,
            int minAge, boolean familyFriendly, int maxGuests, String confirmation, Venue venue, String organizer, List<TicketType> ticketTypes,
            Double rating, int reviewCount, boolean bookable, String cancellationTerms, boolean demo) {}

    public record SessionView(String id, OffsetDateTime startsAt, OffsetDateTime endsAt, int capacity, int free, long fromPriceMinor) {}

    public record Seat(String id, String row, int number, String zone, String status, Long priceMinor) {}

    public record ReviewView(String id, int rating, String body, OffsetDateTime createdAt, String author) {}

    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public LeisureCatalogService(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    public boolean enabled() { return toggles.enabled(Feature.LEISURE); }

    @Transactional(readOnly = true)
    public List<Category> categories() {
        if (!enabled()) { return List.of(); }
        return db.query("select code, name_ru, name_kk, name_en, default_booking_type, family_friendly, enabled from marketplace.leisure_categories "
                + "where enabled order by sort_order", (rs, n) -> new Category(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getString(5), rs.getBoolean(6), rs.getBoolean(7)));
    }

    @Transactional(readOnly = true)
    public List<Card> search(Search p) {
        if (!enabled()) { return List.of(); }
        List<Object> args = new ArrayList<>();
        StringBuilder lateral = new StringBuilder("s.status = 'SCHEDULED' and s.starts_at > now() and s.event_id = e.id");
        LocalDate day = p.date();
        String preset = p.preset() == null ? "" : p.preset();
        if ("today".equals(preset)) { day = LocalDate.now(ALMATY); }
        if (day != null) {
            lateral.append(" and (s.starts_at at time zone v.timezone)::date = ?");
            args.add(day);
        }
        if ("weekend".equals(preset)) {
            lateral.append(" and extract(isodow from (s.starts_at at time zone v.timezone)) in (6, 7)"
                    + " and (s.starts_at at time zone v.timezone)::date <= (now() at time zone v.timezone)::date + 9");
        }
        if (p.timeFrom() != null) { lateral.append(" and (s.starts_at at time zone v.timezone)::time >= ?"); args.add(p.timeFrom()); }
        if (p.timeTo() != null) { lateral.append(" and (s.starts_at at time zone v.timezone)::time <= ?"); args.add(p.timeTo()); }
        if (p.availableOnly() || p.guests() != null) {
            int guests = p.guests() == null ? 1 : p.guests();
            lateral.append(" and " + FREE + " >= (case when e.booking_type in ('TIME_SLOT', 'PRIVATE_SESSION') then 1 else ? end)");
            args.add(guests);
        }
        List<Object> where = new ArrayList<>();
        StringBuilder w = new StringBuilder("e.status = 'PUBLISHED' and v.status = 'APPROVED' and c.enabled and ns.id is not null");
        if (p.category() != null && !p.category().isBlank()) { w.append(" and e.category_code = ?"); where.add(p.category().toUpperCase(Locale.ROOT)); }
        if (p.q() != null && !p.q().isBlank()) {
            w.append(" and (lower(e.title) like ? or lower(v.name) like ? or lower(e.description) like ?)");
            String like = "%" + p.q().strip().toLowerCase(Locale.ROOT).replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
            where.add(like); where.add(like); where.add(like);
        }
        if (p.district() != null && !p.district().isBlank()) { w.append(" and lower(v.district) = ?"); where.add(p.district().strip().toLowerCase(Locale.ROOT)); }
        if (p.minPriceMinor() != null) { w.append(" and price.min_price >= ?"); where.add(p.minPriceMinor()); }
        if (p.maxPriceMinor() != null) { w.append(" and price.min_price <= ?"); where.add(p.maxPriceMinor()); }
        if (p.age() != null) { w.append(" and e.min_age <= ?"); where.add(p.age()); }
        if (Boolean.TRUE.equals(p.family()) || "family".equals(preset)) { w.append(" and e.family_friendly and e.min_age <= 12"); }
        if (p.minRating() != null) { w.append(" and r.cnt > 0 and r.avg >= ?"); where.add(p.minRating()); }
        boolean geo = p.lat() != null && p.lng() != null;
        String dist = geo ? "(6371 * acos(least(1, greatest(-1, cos(radians(?)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(?))"
                + " + sin(radians(?)) * sin(radians(v.latitude))))))" : "null::float";
        if (geo && p.radiusKm() != null) {
            w.append(" and v.latitude is not null and " + dist + " <= ?");
            where.add(p.lat()); where.add(p.lng()); where.add(p.lat()); where.add(p.radiusKm());
        }
        String sort = p.sort() == null ? "time" : p.sort();
        String order = switch (sort) {
            case "price" -> "price.min_price asc, ns.starts_at asc";
            case "popular" -> "pop.cnt desc, ns.starts_at asc";
            case "distance" -> geo ? "dist asc nulls last, ns.starts_at asc" : "ns.starts_at asc";
            default -> "ns.starts_at asc";
        };
        if ("popular".equals(preset)) { order = "pop.cnt desc, ns.starts_at asc"; }
        // argument order = textual order in the statement: select-list distance, lateral session filter, where filters, limit/offset
        List<Object> all = new ArrayList<>();
        if (geo) { all.add(p.lat()); all.add(p.lng()); all.add(p.lat()); }
        all.addAll(args);
        all.addAll(where);
        all.add(Math.max(1, Math.min(p.limit(), 100)));
        all.add(Math.max(0, p.offset()));
        String sql = "select * from (select e.id, e.title, v.id venue_id, v.name venue_name, v.district, v.address, e.category_code, e.booking_type, "
                + "coalesce(e.photo_urls[1], v.photo_urls[1]) photo, price.min_price, e.min_age, e.family_friendly, r.avg, r.cnt, ns.starts_at, ns.id session_id, ns.free, "
                + dist + " dist, pop.cnt pop_cnt "
                + "from marketplace.leisure_events e join marketplace.leisure_venues v on v.id = e.venue_id join marketplace.leisure_categories c on c.code = e.category_code "
                + "join lateral (select s.id, s.starts_at, " + FREE + " free from marketplace.leisure_sessions s where " + lateral + " order by s.starts_at limit 1) ns on true "
                + "left join lateral (select min(tt.price_minor) min_price from marketplace.leisure_ticket_types tt where tt.event_id = e.id and tt.active) price on true "
                + "left join lateral (select avg(rv.rating)::float avg, count(*) cnt from transactions.leisure_reviews rv where rv.event_id = e.id and rv.status = 'PUBLISHED') r on true "
                + "left join lateral (select count(*) cnt from transactions.leisure_tickets t join marketplace.leisure_sessions s2 on s2.id = t.session_id "
                + "where s2.event_id = e.id and t.status in ('VALID', 'USED') and t.created_at > now() - interval '30 days') pop on true "
                + "where " + w + ") x order by " + order.replace("ns.", "x.").replace("price.min_price", "x.min_price").replace("pop.cnt", "x.pop_cnt").replace("dist", "x.dist")
                + " limit ? offset ?";
        // the order clause above runs on the wrapped result; where-clause aliases are resolved inside the inner select
        return db.query(sql, LeisureCatalogService::card, all.toArray());
    }

    private static Card card(ResultSet rs, int n) throws SQLException {
        double avg = rs.getDouble(13);
        boolean rated = !rs.wasNull();
        double dist = rs.getDouble(18);
        boolean hasDist = !rs.wasNull();
        return new Card(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7),
                rs.getString(8), rs.getString(9), rs.getLong(10), "KZT", rs.getInt(11), rs.getBoolean(12), rated ? Math.round(avg * 10) / 10.0 : null,
                rs.getInt(14), kz.kunde.leisure.LeisureTime.local(rs, 15), rs.getString(16), Math.max(0, rs.getInt(17)),
                hasDist ? Math.round(dist * 10) / 10.0 : null);
    }

    /** Sections of the Leisure home screen; every card comes from the same search so nothing is invented. */
    @Transactional(readOnly = true)
    public java.util.Map<String, List<Card>> home(Double lat, Double lng) {
        java.util.Map<String, List<Card>> out = new java.util.LinkedHashMap<>();
        out.put("today", search(new Search(null, null, null, null, null, null, null, null, null, null, false, null, null, null, null, null, "time", "today", 10, 0)));
        out.put("weekend", search(new Search(null, null, null, null, null, null, null, null, null, null, false, null, null, null, null, null, "time", "weekend", 10, 0)));
        out.put("family", search(new Search(null, null, null, null, null, null, null, null, null, null, false, true, null, null, null, null, "popular", null, 10, 0)));
        out.put("popular", search(new Search(null, null, null, null, null, null, null, null, null, null, false, null, null, null, null, null, "popular", "popular", 10, 0)));
        if (lat != null && lng != null) {
            out.put("near", search(new Search(null, null, null, null, null, null, null, null, null, null, false, null, null, lat, lng, 15.0, "distance", null, 10, 0)));
        }
        return out;
    }

    @Transactional(readOnly = true)
    public Detail detail(UUID id) {
        var rows = db.query("""
                select e.id, e.title, e.description, e.photo_urls, e.category_code, e.booking_type, e.duration_minutes, e.min_age, e.family_friendly, e.max_guests,
                       e.confirmation, e.is_synthetic, v.id, v.name, v.description, v.address, v.district, v.latitude, v.longitude, v.photo_urls, v.rules,
                       v.cancellation_hours, p.display_name, c.name_ru, c.name_kk, c.name_en, c.default_booking_type, c.family_friendly, c.enabled
                from marketplace.leisure_events e join marketplace.leisure_venues v on v.id = e.venue_id join marketplace.partners p on p.id = v.partner_id
                join marketplace.leisure_categories c on c.code = e.category_code
                where e.id = ? and e.status = 'PUBLISHED' and v.status = 'APPROVED' and c.enabled""", (rs, n) -> {
            Venue venue = new Venue(rs.getString(13), rs.getString(14), rs.getString(15), rs.getString(16), rs.getString(17), (Double) rs.getObject(18),
                    (Double) rs.getObject(19), list(rs.getArray(20)), rs.getString(21), rs.getInt(22));
            Category cat = new Category(rs.getString(5), rs.getString(24), rs.getString(25), rs.getString(26), rs.getString(27), rs.getBoolean(28), rs.getBoolean(29));
            return new Object[] {rs.getString(1), rs.getString(2), rs.getString(3), list(rs.getArray(4)), cat, rs.getString(6), rs.getInt(7), rs.getInt(8),
                    rs.getBoolean(9), rs.getInt(10), rs.getString(11), venue, rs.getString(23), rs.getBoolean(12)};
        }, id);
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "EVENT_NOT_FOUND", "Event not found");
        }
        Object[] r = rows.get(0);
        Venue venue = (Venue) r[11];
        List<String> photos = new ArrayList<>((List<String>) r[3]);
        if (photos.isEmpty()) { photos.addAll(venue.photos()); }
        var rating = db.query("select avg(rating)::float, count(*) from transactions.leisure_reviews where event_id = ? and status = 'PUBLISHED'",
                (rs, n) -> new Object[] {rs.getDouble(1), rs.getInt(2)}, id).get(0);
        int count = (int) rating[1];
        return new Detail((String) r[0], (String) r[1], (String) r[2], photos, (Category) r[4], (String) r[5], (int) r[6], (int) r[7], (boolean) r[8], (int) r[9],
                (String) r[10], venue, (String) r[12], ticketTypes(id), count == 0 ? null : Math.round((double) rating[0] * 10) / 10.0, count, enabled(),
                cancellationTerms(venue.cancellationHours()), (boolean) r[13]);
    }

    public static String cancellationTerms(int hours) {
        return hours == 0 ? "Free cancellation until the start of the session."
                : "Free cancellation up to " + hours + " h before the start; later cancellations are not refunded by the customer app (contact the organiser).";
    }

    List<TicketType> ticketTypes(UUID eventId) {
        return db.query("select id, name, price_minor, currency, pricing, seat_zone from marketplace.leisure_ticket_types where event_id = ? and active order by sort_order, price_minor",
                (rs, n) -> new TicketType(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getString(4), rs.getString(5), rs.getString(6)), eventId);
    }

    @Transactional(readOnly = true)
    public List<SessionView> sessions(UUID eventId, LocalDate date, int days) {
        if (!enabled()) { return List.of(); }
        ZoneId zone = ALMATY;
        OffsetDateTime from = (date == null ? LocalDate.now(zone) : date).atStartOfDay(zone).toOffsetDateTime();
        OffsetDateTime to = from.plusDays(Math.max(1, Math.min(days, 31)));
        return db.query("select s.id, s.starts_at, s.ends_at, s.capacity, " + FREE + " free, "
                + "coalesce((select min(price_minor) from marketplace.leisure_ticket_types tt where tt.event_id = s.event_id and tt.active), 0) "
                + "from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id join marketplace.leisure_venues v on v.id = e.venue_id "
                + "where s.event_id = ? and e.status = 'PUBLISHED' and v.status = 'APPROVED' and s.status = 'SCHEDULED' and s.starts_at > now() and s.starts_at >= ? and s.starts_at < ? "
                + "order by s.starts_at limit 300", (rs, n) -> new SessionView(rs.getString(1), kz.kunde.leisure.LeisureTime.local(rs, 2),
                kz.kunde.leisure.LeisureTime.local(rs, 3), rs.getInt(4), Math.max(0, rs.getInt(5)), rs.getLong(6)), eventId, from, to);
    }

    @Transactional(readOnly = true)
    public List<Seat> seats(UUID sessionId) {
        boolean exists = Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id "
                + "join marketplace.leisure_venues v on v.id = e.venue_id where s.id = ? and e.status = 'PUBLISHED' and v.status = 'APPROVED')", Boolean.class, sessionId));
        if (!exists) { throw new ApiException(HttpStatus.NOT_FOUND, "SESSION_NOT_FOUND", "Session not found"); }
        return db.query("""
                select st.id, st.row_label, st.seat_number, st.zone,
                  case when exists (select 1 from transactions.leisure_tickets t where t.seat_id = st.id and t.session_id = st.session_id and t.status in ('PENDING', 'VALID', 'USED')) then 'SOLD'
                       when exists (select 1 from transactions.leisure_hold_lines hl join transactions.leisure_holds h on h.id = hl.hold_id
                                    where hl.seat_id = st.id and h.status = 'ACTIVE' and h.expires_at > now()) then 'HELD' else 'FREE' end,
                  (select min(tt.price_minor) from marketplace.leisure_ticket_types tt join marketplace.leisure_sessions s on s.event_id = tt.event_id
                    where s.id = st.session_id and tt.active and (tt.seat_zone is null or tt.seat_zone = st.zone))
                from marketplace.leisure_seats st where st.session_id = ? order by st.row_label, st.seat_number""",
                (rs, n) -> new Seat(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getString(4), rs.getString(5), (Long) rs.getObject(6)), sessionId);
    }

    @Transactional(readOnly = true)
    public List<ReviewView> reviews(UUID eventId, int limit, int offset) {
        return db.query("select id, rating, body, created_at from transactions.leisure_reviews where event_id = ? and status = 'PUBLISHED' order by created_at desc limit ? offset ?",
                (rs, n) -> new ReviewView(rs.getString(1), rs.getInt(2), rs.getString(3), kz.kunde.leisure.LeisureTime.local(rs, 4), "Гость"),
                eventId, Math.max(1, Math.min(limit, 50)), Math.max(0, offset));
    }

    private static List<String> list(Array array) throws SQLException {
        return array == null ? List.of() : List.of((String[]) array.getArray());
    }
}
