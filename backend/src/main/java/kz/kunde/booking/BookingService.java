package kz.kunde.booking;

import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Barbershop bookings: validated against the API's own free slots, saved in PostgreSQL, protected from double booking
 * by a database exclusion constraint (per master, overlapping time) plus a per-user lock. Free cancellation until the
 * start. Confirmation is a DEV mock ({@code confirmation = DEV_MOCK}); there is no payment.
 */
@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BookingService {
    private static final Pattern KEY = Pattern.compile("^[A-Za-z0-9_-]{16,64}$");
    private static final int MAX_UPCOMING = 5;

    public record BookRequest(@NotNull UUID venueId, @NotNull UUID serviceId, @NotNull UUID masterId,
            @NotNull OffsetDateTime startsAt, @Size(max = 300) String comment,
            @Size(max = 300) String addressText, @Min(1) @Max(1000) Integer areaSqm, @Min(0) Long expectedPriceMinor, @Size(max = 16) String paymentMethod,
            Boolean acceptsTerms) {}

    public record BookingView(String id, String venueId, String venueName, String venueAddress, String serviceName,
            int durationMinutes, String masterId, String masterName, OffsetDateTime startsAt, OffsetDateTime endsAt,
            long priceMinor, String currency, String status, String confirmation, String comment, boolean cancellable,
            OffsetDateTime createdAt, OffsetDateTime cancelledAt, String category, String addressText, Integer areaSqm,
            String cancelledBy, String cancelReason, String paymentMethod, String paymentStatus, String serviceId, boolean reschedulable,
            String bookingNumber, Integer discountPercent, Long originalPriceMinor) {}

    public record Booked(BookingView booking, boolean created) {}

    private final JdbcTemplate db;
    private final BookingSlots slots;
    private final kz.kunde.auto.AutoPayments payments;

    public BookingService(JdbcTemplate db, BookingSlots slots, kz.kunde.auto.AutoPayments payments) {
        this.db = db;
        this.slots = slots;
        this.payments = payments;
    }

    @Transactional
    public Booked book(UUID user, BookRequest request, String idempotencyKey) {
        if (idempotencyKey == null || !KEY.matcher(idempotencyKey).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_INVALID",
                    "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }
        db.query("select pg_advisory_xact_lock(hashtext('booking'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        Instant start = request.startsAt().toInstant();
        var existing = db.query("select id, master_id, coalesce(health_initial_starts_at, starts_at), venue_id, service_id, category, price_minor from transactions.bookings where user_id = ? and idempotency_key = ?",
                (rs, row) -> new Object[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getTimestamp(3).toInstant(),
                    rs.getObject(4, UUID.class), rs.getObject(5, UUID.class), rs.getString(6), rs.getLong(7)},
                user, idempotencyKey).stream().findFirst();
        if (existing.isPresent()) {
            var previous = existing.get();
            boolean sameHealthRequest = !"HEALTH".equals(previous[5]) || (
                    previous[3].equals(request.venueId()) && previous[4].equals(request.serviceId())
                    && previous[6].equals(request.expectedPriceMinor()) && Boolean.TRUE.equals(request.acceptsTerms())
                    && request.comment() == null && request.addressText() == null && request.areaSqm() == null
                    && payments.ofBooking((UUID) previous[0]).method().equals(payments.method(request.paymentMethod())));
            if (!previous[1].equals(request.masterId()) || !previous[2].equals(start) || !sameHealthRequest) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED",
                        "Idempotency-Key was already used for a different booking");
            }
            return new Booked(view(user, (UUID) existing.get()[0]), false);
        }
        var venue = slots.venue(request.venueId());
        if ("AUTO".equals(venue.category())) {
            throw new ApiException(HttpStatus.CONFLICT, "USE_AUTO_API", "Automotive services are booked through /api/v1/auto");
        }
        boolean health = "HEALTH".equals(venue.category());
        String paymentMethod = null;
        if (health) {
            slots.requireHealthCatalog();
            if (request.comment() != null || request.addressText() != null || request.areaSqm() != null) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "DETAILS_NOT_APPLICABLE", "Health bookings accept no notes or private details");
            }
            if (!Boolean.TRUE.equals(request.acceptsTerms()) || request.expectedPriceMinor() == null) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "BOOKING_TERMS_REQUIRED", "Confirm the displayed price and booking terms");
            }
            db.queryForObject("select id from marketplace.booking_venues where id = ? for share", UUID.class, venue.id());
            db.queryForList("select id from marketplace.booking_services where id = ? and venue_id = ? for share",
                    UUID.class, request.serviceId(), venue.id());
            db.queryForList("select id from marketplace.booking_masters where id = ? and venue_id = ? for share",
                    UUID.class, request.masterId(), venue.id());
            paymentMethod = payments.method(request.paymentMethod());
        }
        var service = slots.service(request.venueId(), request.serviceId());
        boolean home = "CLEANING".equals(venue.category());
        String address = request.addressText() == null || request.addressText().isBlank() ? null : request.addressText().strip();
        Integer area = request.areaSqm();
        if (home) {
            if (address == null || address.length() < 5) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ADDRESS_REQUIRED", "Enter the address where the service is needed");
            }
            if (service.areaBased()) {
                if (area == null || area < service.minAreaSqm() || area > service.maxAreaSqm()) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "AREA_INVALID",
                            "Area must be between " + service.minAreaSqm() + " and " + service.maxAreaSqm() + " m2");
                }
            } else if (area != null) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "AREA_NOT_APPLICABLE", "This service is not priced by area");
            }
        } else if (address != null || area != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "DETAILS_NOT_APPLICABLE", "Address and area apply to home services only");
        }
        // The price is always computed here; the app only previews it.
        long price = service.priceMinor() + service.pricePerSqmMinor() * (area == null ? 0 : area);
        // A Beauty promotion (the venue's or platform-wide) active right now is applied to the list price.
        Integer discount = "BARBER".equals(venue.category()) ? db.queryForObject("""
                select max(percent) from marketplace.beauty_promotions
                where active and now() >= starts_at and now() < ends_at and (venue_id = ? or venue_id is null)
                """, Integer.class, venue.id()) : null;
        long listPrice = price;
        if (discount != null) {
            price = listPrice - Math.round(listPrice * discount / 100.0);
        }
        if ((health || (request.expectedPriceMinor() != null && "BARBER".equals(venue.category())))
                && !java.util.Objects.equals(request.expectedPriceMinor(), price)) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_PRICE_CHANGED", "Reload the service and review the current price");
        }
        // Only a start time the slot list offers for this master can be booked (hours, break, grid, lead time, horizon).
        var date = start.atZone(venue.zone()).toLocalDate();
        boolean offered = slots.freeSlots(request.venueId(), request.serviceId(), request.masterId(), date).stream()
                .anyMatch(s -> s.startsAt().toInstant().equals(start));
        if (!offered) {
            throw new ApiException(HttpStatus.CONFLICT, "SLOT_UNAVAILABLE", "This time is no longer available");
        }
        Instant end = start.plusSeconds(service.durationMinutes() * 60L);
        Integer upcoming = db.queryForObject("""
                select count(*) from transactions.bookings where user_id = ? and status in ('PENDING', 'CONFIRMED') and starts_at > now()
                """, Integer.class, user);
        if (upcoming != null && upcoming >= MAX_UPCOMING) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_UPCOMING_BOOKINGS", "Too many upcoming bookings");
        }
        Integer clash = db.queryForObject("""
                select count(*) from transactions.bookings
                where user_id = ? and status in ('PENDING', 'CONFIRMED') and starts_at < ? and ends_at > ?
                """, Integer.class, user, Timestamp.from(end), Timestamp.from(start));
        if (clash != null && clash > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_OVERLAPS_YOURS", "You already have a booking at this time");
        }
        // Shared lock: a partner changing this master's schedule (FOR UPDATE) cannot interleave with this booking.
        String master = db.queryForObject("select name from marketplace.booking_masters where id = ? for share", String.class, request.masterId());
        // Beauty salons confirm instantly (the customer sees «Запись подтверждена»); other partner venues answer requests.
        boolean partnerManaged = db.queryForObject("select v.partner_id is not null and not exists (select 1 from marketplace.beauty_salon_profiles p where p.venue_id = v.id) "
                + "from marketplace.booking_venues v where v.id = ?", Boolean.class, venue.id());
        String comment = request.comment() == null || request.comment().isBlank() ? null : request.comment().strip();
        try {
            UUID id = db.queryForObject("""
                    insert into transactions.bookings (user_id, venue_id, service_id, master_id, venue_name, venue_address,
                        service_name, master_name, duration_minutes, starts_at, ends_at, price_minor, comment, idempotency_key,
                        category, address_text, area_sqm, status, confirmation, health_initial_starts_at, discount_percent, original_price_minor)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                    """, UUID.class, user, venue.id(), service.id(), request.masterId(), venue.name(), venue.address(),
                    service.name(), master, service.durationMinutes(), Timestamp.from(start), Timestamp.from(end),
                    price, comment, idempotencyKey, venue.category(), address, area,
                    partnerManaged ? "PENDING" : "CONFIRMED", partnerManaged ? "PARTNER" : "DEV_MOCK",
                    health ? Timestamp.from(start) : null, discount, discount == null ? null : listPrice);
            event(id, partnerManaged ? "PENDING" : "CONFIRMED", partnerManaged ? "CUSTOMER" : "SYSTEM", user, null);
            if (health) { payments.open(user, id, null, paymentMethod, price); }
            return new Booked(view(user, id), true);
        } catch (DataIntegrityViolationException conflict) {
            if (conflict.getMostSpecificCause() instanceof SQLException sql && "23P01".equals(sql.getSQLState())) {
                // Exclusion violation: another booking took (part of) this master's time between check and insert.
                throw new ApiException(HttpStatus.CONFLICT, "SLOT_TAKEN", "This time was just booked by someone else");
            }
            throw conflict;
        }
    }

    @Transactional
    public List<BookingView> list(UUID user, boolean healthOnly, int limit, int offset) {
        complete(user);
        return query(user, null, healthOnly, limit, offset);
    }

    @Transactional
    public BookingView get(UUID user, UUID id) {
        complete(user);
        return view(user, id);
    }

    /** Free cancellation until the appointment starts; afterwards it is a no-show/visit and cannot be cancelled. */
    @Transactional
    public BookingView cancel(UUID user, UUID id) {
        var row = db.query("""
                select status, starts_at > now() from transactions.bookings where id = ? and user_id = ? for update
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getBoolean(2)}, id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        if (!("CONFIRMED".equals(row[0]) || "PENDING".equals(row[0])) || !(boolean) row[1]) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_CANCELLABLE",
                    "Only an upcoming pending or confirmed booking can be cancelled");
        }
        db.update("""
                update transactions.bookings set status = 'CANCELLED', cancelled_at = now(), cancelled_by = 'CUSTOMER',
                    updated_at = now(), version = version + 1 where id = ?
                """, id);
        event(id, "CANCELLED", "CUSTOMER", user, null);
        if (payments != null) { payments.voidHold(id, null, "CUSTOMER", user, null); }
        return view(user, id);
    }

    private record HealthMove(UUID venue, UUID service, UUID master, Instant start, int duration,
            boolean allowed, boolean partnerManaged) {}

    /** Moves an owned Health appointment on the same specialist's schedule, preserving its price and hold. */
    @Transactional
    public BookingView rescheduleHealth(UUID user, UUID id, OffsetDateTime startsAt, OffsetDateTime expectedStartsAt) {
        db.query("select pg_advisory_xact_lock(hashtext('booking'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        var current = db.query("""
                select b.venue_id, b.service_id, b.master_id, b.starts_at, b.duration_minutes,
                       b.status in ('PENDING', 'CONFIRMED') and b.starts_at > now() + interval '2 hours'
                           and b.reschedule_count < 2, v.partner_id is not null
                from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id
                where b.id = ? and b.user_id = ? and b.category = 'HEALTH' for update of b
                """, (rs, n) -> new HealthMove(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class),
                        rs.getObject(3, UUID.class), rs.getTimestamp(4).toInstant(), rs.getInt(5),
                        rs.getBoolean(6), rs.getBoolean(7)), id, user).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
        var target = startsAt.toInstant();
        if (target.equals(current.start())) { return view(user, id); }
        slots.requireHealthCatalog();
        if (!current.start().equals(expectedStartsAt.toInstant())) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_CHANGED", "Reload the appointment before moving it");
        }
        if (!current.allowed()) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_RESCHEDULABLE", "This appointment cannot be moved");
        }
        db.queryForObject("select id from marketplace.booking_venues where id = ? for share", UUID.class, current.venue());
        db.queryForObject("select id from marketplace.booking_services where id = ? for share", UUID.class, current.service());
        db.queryForObject("select id from marketplace.booking_masters where id = ? for share", UUID.class, current.master());
        var venue = slots.venue(current.venue());
        var service = slots.service(current.venue(), current.service());
        var date = target.atZone(venue.zone()).toLocalDate();
        if (service.durationMinutes() != current.duration()
                || slots.freeSlots(current.venue(), current.service(), current.master(), date, id).stream()
                        .noneMatch(slot -> slot.startsAt().toInstant().equals(target))) {
            throw new ApiException(HttpStatus.CONFLICT, "SLOT_UNAVAILABLE", "This time is not available");
        }
        var end = target.plusSeconds(current.duration() * 60L);
        if (Boolean.TRUE.equals(db.queryForObject("""
                select exists (select 1 from transactions.bookings where user_id = ? and id <> ?
                    and status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS') and starts_at < ? and ends_at > ?)
                """, Boolean.class, user, id, Timestamp.from(end), Timestamp.from(target)))) {
            throw new ApiException(HttpStatus.CONFLICT, "BOOKING_OVERLAPS_YOURS", "You already have a booking at this time");
        }
        try {
            db.update("""
                    update transactions.bookings set starts_at = ?, ends_at = ?, status = ?, confirmation = ?,
                        reschedule_count = reschedule_count + 1, updated_at = now(), version = version + 1 where id = ?
                    """, Timestamp.from(target), Timestamp.from(end), current.partnerManaged() ? "PENDING" : "CONFIRMED",
                    current.partnerManaged() ? "PARTNER" : "DEV_MOCK", id);
        } catch (DataIntegrityViolationException conflict) {
            if (conflict.getMostSpecificCause() instanceof SQLException sql && "23P01".equals(sql.getSQLState())) {
                throw new ApiException(HttpStatus.CONFLICT, "SLOT_TAKEN", "This time was just booked by someone else");
            }
            throw conflict;
        }
        event(id, "RESCHEDULED", "CUSTOMER", user, null);
        if (current.partnerManaged()) { event(id, "PENDING", "SYSTEM", null, "RESCHEDULED"); }
        return view(user, id);
    }

    /** Past confirmed appointments become COMPLETED (lazily, on read). */
    private void complete(UUID user) {
        completeDue("user_id = ?", user);
    }

    /** Lazy transitions on read: finished confirmed visits are COMPLETED; a request nobody answered before the start expires. */
    void completeDue(String scope, Object arg) {
        for (UUID id : db.queryForList("select id from transactions.bookings where " + scope
                + " and status = 'CONFIRMED' and (category not in ('AUTO', 'HEALTH') or (category = 'HEALTH' and confirmation = 'DEV_MOCK')) and ends_at <= now() for update", UUID.class, arg)) {
            db.update("update transactions.bookings set status = 'COMPLETED', updated_at = now(), version = version + 1 where id = ?", id);
            event(id, "COMPLETED", "SYSTEM", null, null);
            if (payments != null) {
                Long syntheticPrice = db.queryForObject("""
                        select case when category = 'HEALTH' then price_minor end from transactions.bookings where id = ?
                        """, Long.class, id);
                if (syntheticPrice != null) { payments.capture(id, null, syntheticPrice, "SYSTEM", null); }
            }
        }
        for (UUID id : db.queryForList("select id from transactions.bookings where " + scope
                + " and status = 'PENDING' and starts_at <= now() for update", UUID.class, arg)) {
            db.update("""
                    update transactions.bookings set status = 'CANCELLED', cancelled_at = now(), cancelled_by = 'SYSTEM',
                        cancel_reason = 'NOT_ANSWERED', updated_at = now(), version = version + 1 where id = ?
                    """, id);
            event(id, "CANCELLED", "SYSTEM", null, "NOT_ANSWERED");
            if (payments != null) { payments.voidHold(id, null, "SYSTEM", null, "NOT_ANSWERED"); }
        }
    }

    void event(UUID bookingId, String status, String actorType, UUID actor, String reason) {
        db.update("""
                insert into transactions.booking_events (booking_id, status, actor_type, actor_user_id, reason)
                values (?, ?, ?, ?, ?)
                """, bookingId, status, actorType, actor, reason);
    }

    private BookingView view(UUID user, UUID id) {
        return query(user, id, false, 1, 0).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
    }

    private static OffsetDateTime localTime(OffsetDateTime value, String category) {
        return "HEALTH".equals(category) ? value.atZoneSameInstant(java.time.ZoneId.of("Asia/Almaty")).toOffsetDateTime() : value;
    }

    private List<BookingView> query(UUID user, UUID id, boolean healthOnly, int limit, int offset) {
        return db.query("""
                select id, venue_id, venue_name, venue_address, service_name, duration_minutes, master_id, master_name,
                       starts_at, ends_at, price_minor, currency, status, confirmation, comment,
                       (status in ('PENDING', 'CONFIRMED') and starts_at > now()) as cancellable, created_at, cancelled_at, category, address_text, area_sqm,
                       cancelled_by, cancel_reason, service_id, booking_number, discount_percent, original_price_minor,
                       (category = 'HEALTH' and status in ('PENDING', 'CONFIRMED') and
                           starts_at > now() + interval '2 hours' and reschedule_count < 2) as reschedulable,
                       (select method from transactions.auto_payments where booking_id = bookings.id and bookings.category = 'HEALTH') as payment_method,
                       (select status from transactions.auto_payments where booking_id = bookings.id and bookings.category = 'HEALTH') as payment_status
                from transactions.bookings where user_id = ? and (?::uuid is null or id = ?::uuid)
                and (not ? or category = 'HEALTH')
                order by starts_at desc, id limit ? offset ?
                """, (rs, row) -> new BookingView(rs.getString("id"), rs.getString("venue_id"), rs.getString("venue_name"),
                rs.getString("venue_address"), rs.getString("service_name"), rs.getInt("duration_minutes"),
                rs.getString("master_id"), rs.getString("master_name"), localTime(rs.getObject("starts_at", OffsetDateTime.class), rs.getString("category")),
                localTime(rs.getObject("ends_at", OffsetDateTime.class), rs.getString("category")), rs.getLong("price_minor"), rs.getString("currency"),
                rs.getString("status"), rs.getString("confirmation"), rs.getString("comment"), rs.getBoolean("cancellable"),
                rs.getObject("created_at", OffsetDateTime.class), rs.getObject("cancelled_at", OffsetDateTime.class),
                rs.getString("category"), rs.getString("address_text"), rs.getObject("area_sqm", Integer.class),
                rs.getString("cancelled_by"), rs.getString("cancel_reason"), rs.getString("payment_method"), rs.getString("payment_status"), rs.getString("service_id"),
                rs.getBoolean("reschedulable") && slots.healthEnabled(), rs.getString("booking_number"),
                rs.getObject("discount_percent", Integer.class), rs.getObject("original_price_minor", Long.class)),
                user, id, id, healthOnly, limit, offset);
    }
}
