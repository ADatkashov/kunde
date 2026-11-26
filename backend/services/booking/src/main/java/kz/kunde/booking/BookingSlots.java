package kz.kunde.booking;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Free-slot computation, shared by the public slot list and by booking validation so a booking can only be made on
 * a slot the API itself offers. Times are venue-local (default Asia/Almaty); starts are on a 15-minute grid inside the
 * master's working hours, outside their break, not in the past (30 min lead) and within a 14-day horizon.
 */
@Component
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BookingSlots {
    public static final int GRID_MINUTES = 15;
    public static final int HORIZON_DAYS = 14;
    public static final int LEAD_MINUTES = 30;

    public record Slot(OffsetDateTime startsAt, String masterId, String masterName) {}

    private record MasterRef(UUID id, String name) {}

    private final JdbcTemplate db;

    private final FeatureToggles toggles;

    private final BookingCategories categories;

    public BookingSlots(JdbcTemplate db, FeatureToggles toggles, BookingCategories categories) {
        this.db = db;
        this.toggles = toggles;
        this.categories = categories;
    }

    boolean healthEnabled() {
        return toggles.enabled(FeatureToggles.Feature.HEALTH);
    }

    void requireHomeServices() {
        categories.requireAvailable("CLEANING");
    }

    void requireBeauty() {
        categories.requireAvailable("BARBER");
    }

    public void requireHealthCatalog() {
        if (!healthEnabled()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HEALTH_DISABLED", "Health catalog is unavailable");
        }
    }

    public record Service(UUID id, String name, int durationMinutes, long priceMinor, long pricePerSqmMinor, Integer minAreaSqm,
            Integer maxAreaSqm) {
        public boolean areaBased() { return pricePerSqmMinor > 0; }

        /** The list price of one booking: the base price plus the per-square-metre price times the area. */
        public long listPriceMinor(Integer areaSqm) { return priceMinor + pricePerSqmMinor * (areaSqm == null ? 0 : areaSqm); }
    }

    public record Venue(UUID id, String category, String name, String address, ZoneId zone, int bufferMinutes) {}

    public Venue venue(UUID venueId) {
        Venue venue = db.query("select id, category, name, address_text, timezone, buffer_minutes from marketplace.booking_venues where id = ? and is_open and (category <> 'HEALTH' or (is_synthetic and health_published))",
                (rs, row) -> new Venue(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), rs.getString(4),
                        ZoneId.of(rs.getString(5)), rs.getInt(6)),
                venueId).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND",
                "Venue is not available"));
        if ("CLEANING".equals(venue.category())) {
            requireHomeServices();
        }
        if ("BARBER".equals(venue.category())) {
            requireBeauty();
        }
        return venue;
    }

    public Service service(UUID venueId, UUID serviceId) {
        return db.query("""
                select id, name, duration_minutes, price_minor, price_per_sqm_minor, min_area_sqm, max_area_sqm
                from marketplace.booking_services where id = ? and venue_id = ? and available
                """, (rs, row) -> new Service(rs.getObject(1, UUID.class), rs.getString(2), rs.getInt(3), rs.getLong(4),
                        rs.getLong(5), rs.getObject(6, Integer.class), rs.getObject(7, Integer.class)),
                serviceId, venueId).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                "SERVICE_NOT_FOUND", "Service is not available"));
    }

    public List<Slot> freeSlots(UUID venueId, UUID serviceId, UUID masterId, LocalDate date) {
        return freeSlots(venueId, serviceId, masterId, date, null);
    }

    /** {@code ignoreBooking}: a booking being moved does not block its own new time. */
    public List<Slot> freeSlots(UUID venueId, UUID serviceId, UUID masterId, LocalDate date, UUID ignoreBooking) {
        Venue venue = venue(venueId);
        if ("HEALTH".equals(venue.category())) { requireHealthCatalog(); }
        Service service = service(venueId, serviceId);
        ZonedDateTime now = ZonedDateTime.now(venue.zone());
        LocalDate today = now.toLocalDate();
        if (date.isBefore(today) || date.isAfter(today.plusDays(HORIZON_DAYS - 1))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "BOOKING_DATE_INVALID",
                    "Choose a date within the next " + HORIZON_DAYS + " days");
        }
        List<MasterRef> masters = db.query("""
                select m.id, m.name from marketplace.booking_masters m
                join marketplace.booking_master_services ms on ms.master_id = m.id and ms.service_id = ?
                where m.venue_id = ? and m.active and m.online and (?::uuid is null or m.id = ?::uuid)
                order by m.sort_order, m.name
                """, (rs, row) -> new MasterRef(rs.getObject(1, UUID.class), rs.getString(2)),
                serviceId, venueId, masterId, masterId);
        if (masterId != null && masters.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "MASTER_NOT_FOUND", "This master does not perform the service");
        }
        ZonedDateTime dayStart = date.atStartOfDay(venue.zone());
        Instant from = dayStart.toInstant();
        Instant to = dayStart.plusDays(1).toInstant();
        Map<UUID, List<Instant[]>> busy = new LinkedHashMap<>();
        long buffer = venue.bufferMinutes() * 60L;
        db.query("""
                select master_id, starts_at, ends_at from transactions.bookings
                where status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'COMPLETED') and starts_at < ? and ends_at > ?
                and (?::uuid is null or id <> ?::uuid)
                """, rs -> {
                    busy.computeIfAbsent(rs.getObject(1, UUID.class), k -> new ArrayList<>())
                            .add(new Instant[] {rs.getTimestamp(2).toInstant(), rs.getTimestamp(3).toInstant()});
                }, Timestamp.from(to.plusSeconds(buffer)), Timestamp.from(from.minusSeconds(buffer)), ignoreBooking, ignoreBooking);
        // Unavailable periods (holidays, repairs): venue-wide (master_id null) or for one post; no buffer applies to them.
        Map<UUID, List<Instant[]>> off = new LinkedHashMap<>();
        db.query("""
                select master_id, starts_at, ends_at from marketplace.booking_time_off
                where venue_id = ? and starts_at < ? and ends_at > ?
                """, rs -> {
                    UUID target = rs.getObject(1, UUID.class);
                    Instant[] period = {rs.getTimestamp(2).toInstant(), rs.getTimestamp(3).toInstant()};
                    for (MasterRef m : masters) {
                        if (target == null || target.equals(m.id())) {
                            off.computeIfAbsent(m.id(), k -> new ArrayList<>()).add(period);
                        }
                    }
                }, venueId, Timestamp.from(to), Timestamp.from(from));
        int weekday = date.getDayOfWeek().getValue();
        Instant earliest = now.toInstant().plus(Duration.ofMinutes(LEAD_MINUTES));
        Duration length = Duration.ofMinutes(service.durationMinutes());
        // time -> first master free at that time (any-master mode) or one slot per master (specific master)
        Map<Instant, Slot> out = new LinkedHashMap<>();
        List<Slot> perMaster = new ArrayList<>();
        for (MasterRef master : masters) {
            var hours = db.query("""
                    select start_time, end_time, break_start, break_end from marketplace.booking_working_hours
                    where master_id = ? and weekday = ?
                    """, (rs, row) -> new LocalTime[] {rs.getObject(1, LocalTime.class), rs.getObject(2, LocalTime.class),
                            rs.getObject(3, LocalTime.class), rs.getObject(4, LocalTime.class)},
                    master.id(), weekday).stream().findFirst().orElse(null);
            if (hours == null) { continue; }
            for (LocalTime t = hours[0]; !t.plus(length).isAfter(hours[1]) && !t.plus(length).isBefore(t);
                    t = t.plusMinutes(GRID_MINUTES)) {
                LocalTime end = t.plus(length);
                if (hours[2] != null && t.isBefore(hours[3]) && end.isAfter(hours[2])) { continue; }
                Instant start = date.atTime(t).atZone(venue.zone()).toInstant();
                Instant stop = start.plus(length);
                if (start.isBefore(earliest)) { continue; }
                boolean taken = busy.getOrDefault(master.id(), List.of()).stream()
                        .anyMatch(b -> start.isBefore(b[1].plusSeconds(buffer)) && stop.isAfter(b[0].minusSeconds(buffer)));
                boolean closed = off.getOrDefault(master.id(), List.of()).stream()
                        .anyMatch(b -> start.isBefore(b[1]) && stop.isAfter(b[0]));
                if (taken || closed) { continue; }
                Slot slot = new Slot(start.atZone(venue.zone()).toOffsetDateTime(), master.id().toString(), master.name());
                if (masterId == null) {
                    out.putIfAbsent(start, slot);
                } else {
                    perMaster.add(slot);
                }
            }
        }
        List<Slot> result = masterId == null ? new ArrayList<>(out.values()) : perMaster;
        result.sort(Comparator.comparing(Slot::startsAt));
        return result;
    }
}
