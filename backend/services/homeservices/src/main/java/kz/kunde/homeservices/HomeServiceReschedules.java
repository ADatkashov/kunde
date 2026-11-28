package kz.kunde.homeservices;

import jakarta.validation.constraints.Future;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.UUID;
import kz.kunde.booking.BookingService;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class HomeServiceReschedules {
    public record Request(@NotNull @Min(0) Long expectedVersion,
            @NotNull @Future OffsetDateTime startsAt, @NotBlank @Size(max = 200) String reason) {}
    public record Decision(@NotNull @Min(0) Long expectedVersion, @NotNull Boolean accepted) {}
    public record Proposal(OffsetDateTime startsAt, String reason, long version) {}

    private record Order(UUID user, UUID venue, UUID service, UUID master, int duration, String status,
            long version, OffsetDateTime start, OffsetDateTime proposed, Double latitude, Double longitude) {}

    private final JdbcTemplate db;
    private final BookingService bookings;
    private final HomeServicePricing pricing;

    HomeServiceReschedules(JdbcTemplate db, BookingService bookings, HomeServicePricing pricing) {
        this.db = db;
        this.bookings = bookings;
        this.pricing = pricing;
    }

    void propose(UUID id, UUID partner, UUID actor, String actorType, Request request) {
        Order order = locked(id, partner, null);
        check(order, request.expectedVersion());
        if (order.start().isEqual(request.startsAt())) {
            throw new ApiException(HttpStatus.CONFLICT, "SCHEDULE_UNCHANGED", "Choose a different time");
        }
        validateSlot(id, order, request.startsAt());
        String reason = request.reason().strip();
        db.update("""
                update transactions.bookings set home_proposed_starts_at = ?, home_reschedule_reason = ?,
                    version = version + 1, updated_at = now() where id = ?
                """, request.startsAt(), reason, id);
        bookings.event(id, order.status(), actorType, actor, "RESCHEDULE_PROPOSED: " + request.startsAt() + " " + reason);
    }

    void decide(UUID id, UUID customer, Decision decision) {
        db.query("select pg_advisory_xact_lock(hashtext('booking'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, customer.toString());
        Order order = locked(id, null, customer);
        check(order, decision.expectedVersion());
        if (order.proposed() == null) {
            throw new ApiException(HttpStatus.CONFLICT, "RESCHEDULE_NOT_PENDING", "There is no proposed time");
        }
        if (decision.accepted()) {
            validateSlot(id, order, order.proposed());
            bookings.moveHomeBooking(id, order.user(), order.proposed(), order.proposed().plusMinutes(order.duration()));
            db.update("delete from marketplace.home_service_visits where booking_id = ?", id);
            bookings.event(id, "RESCHEDULED", "CUSTOMER", customer, "RESCHEDULE_ACCEPTED: " + order.proposed());
        } else {
            db.update("""
                    update transactions.bookings set home_proposed_starts_at = null, home_reschedule_reason = null,
                        version = version + 1, updated_at = now() where id = ?
                    """, id);
            bookings.event(id, order.status(), "CUSTOMER", customer, "RESCHEDULE_DECLINED: " + order.proposed());
        }
    }

    Proposal get(UUID id, UUID customer) {
        return db.query("""
                select home_proposed_starts_at, home_reschedule_reason, version from transactions.bookings
                where id = ? and user_id = ? and category = 'CLEANING'
                    and status = 'CONFIRMED' and home_proposed_starts_at is not null
                """, (rs, n) -> new Proposal(rs.getObject(1, OffsetDateTime.class), rs.getString(2), rs.getLong(3)),
                id, customer).stream().findFirst().orElse(null);
    }

    private Order locked(UUID id, UUID partner, UUID customer) {
        return db.query("""
                select b.user_id, b.venue_id, b.service_id, b.master_id, b.duration_minutes, b.status, b.version,
                    b.starts_at, b.home_proposed_starts_at, b.home_latitude, b.home_longitude
                from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id
                where b.id = ? and b.category = 'CLEANING' and (?::uuid is null or v.partner_id = ?)
                    and (?::uuid is null or b.user_id = ?) for update of b
                """, (rs, n) -> new Order(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class),
                rs.getObject(3, UUID.class), rs.getObject(4, UUID.class), rs.getInt(5), rs.getString(6), rs.getLong(7),
                rs.getObject(8, OffsetDateTime.class), rs.getObject(9, OffsetDateTime.class),
                rs.getObject(10, Double.class), rs.getObject(11, Double.class)),
                id, partner, partner, customer, customer).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND", "Booking not found"));
    }

    private static void check(Order order, long version) {
        if (order.version() != version) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The order has changed; reload it");
        }
        if (!"CONFIRMED".equals(order.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_NOT_OPERABLE", "Only an upcoming visit can be moved");
        }
    }

    private void validateSlot(UUID id, Order order, OffsetDateTime start) {
        pricing.requireServiceable(order.venue(), order.latitude(), order.longitude());
        bookings.requireHomeRescheduleSlot(id, order.venue(), order.service(), order.master(), start, order.duration());
    }
}
