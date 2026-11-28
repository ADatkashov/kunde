package kz.kunde.homeservices;

import java.sql.SQLException;
import java.util.UUID;
import kz.kunde.booking.BookingService;
import kz.kunde.platform.ApiException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/** Shared mutation for authorized operations while the Booking row remains locked. */
@Service
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
class HomeServiceAssignments {
    /** Active masters of a venue that perform a service: the only ones an order of that service can be handed to. */
    static final String PERFORMERS = """
            select m.id, m.name, m.online from marketplace.booking_masters m
            join marketplace.booking_master_services ms on ms.master_id = m.id and ms.service_id = ?
            where m.venue_id = ? and m.active""";

    record Assignment(String status, UUID venue, UUID master, UUID service, Double latitude, Double longitude) {}

    private final JdbcTemplate db;
    private final BookingService bookings;
    private final HomeServicePricing pricing;

    HomeServiceAssignments(JdbcTemplate db, BookingService bookings, HomeServicePricing pricing) {
        this.db = db;
        this.bookings = bookings;
        this.pricing = pricing;
    }

    record Master(UUID id, String name) {}

    java.util.List<Master> candidates(UUID id, Assignment order) {
        UUID declined = bookings.homeLastDeclinedMaster(id);
        return db.query(PERFORMERS + " and m.online order by m.name, m.id",
                (rs, row) -> new Master(rs.getObject(1, UUID.class), rs.getString(2)), order.service(), order.venue())
                .stream().filter(master -> !master.id().equals(declined))
                .filter(master -> bookings.homeReplacementSlotAvailable(id, order.venue(), order.service(), master.id()))
                .toList();
    }

    void replace(UUID id, Assignment order, UUID masterId, long version, String actorType, UUID actor, String reason) {
        if (masterId.equals(order.master())) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_UNCHANGED", "The order already belongs to this master");
        }
        String name = db.query(PERFORMERS + " and m.id = ?", (rs, n) -> rs.getString(2), order.service(), order.venue(), masterId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "MASTER_INVALID",
                        "Choose an active master of the same venue who performs this service"));
        boolean taken = Boolean.TRUE.equals(db.queryForObject("""
                select exists (select 1 from transactions.bookings o join transactions.bookings b on b.master_id = ? and b.id <> o.id
                    and b.status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS')
                    and tstzrange(b.starts_at, b.ends_at) && tstzrange(o.starts_at, o.ends_at) where o.id = ?)
                """, Boolean.class, masterId, id));
        if (taken) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_BUSY", "The master is busy at this time");
        }
        if (order.master() == null) {
            pricing.requireServiceable(order.venue(), order.latitude(), order.longitude());
            bookings.requireHomeReplacementSlot(id, order.venue(), order.service(), masterId);
        }
        try {
            // Backstop for a race: the Booking Engine's exclusion constraint refuses a second confirmed visit at the same time.
            bookings.changeHomeAssignment(id, masterId, name);
        } catch (DataIntegrityViolationException busy) {
            if (busy.getMostSpecificCause() instanceof SQLException sql && "23P01".equals(sql.getSQLState())) {
                throw new ApiException(HttpStatus.CONFLICT, "MASTER_BUSY", "The master is busy at this time");
            }
            throw busy;
        }
        // The previous master's "on the way" report does not carry over to the new one.
        db.update("delete from marketplace.home_service_visits where booking_id = ?", id);
        bookings.assignmentEvent(id, version, order.status(), actorType, actor,
                "REASSIGNED: " + reason, order.master(), masterId);
    }
}
