package kz.kunde.rides;

import kz.kunde.platform.FeatureToggles;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import kz.kunde.delivery.DeliveryDispatch;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideMatching.Candidate;
import kz.kunde.platform.geo.Point;
import kz.kunde.rides.RideMatching.RideClass;
import kz.kunde.rides.RideState.Action;
import kz.kunde.rides.RideState.Actor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RideDispatchService {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public RideDispatchService(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    @Transactional
    public void search(UUID customer, UUID ride) {
        if (!toggles.rides().consumerAvailable() || !toggles.rides().dispatchAvailable()) {
            throw missing("RIDE_DISPATCH_UNAVAILABLE");
        }
        var trip = lockTrip(ride);
        if (!customer.equals(trip.customerId())) {
            throw missing("RIDE_NOT_FOUND");
        }
        if (trip.status() == RideState.REQUESTED) {
            trip = change(trip, Actor.SYSTEM, Action.SEARCH, null);
            db.update("update transactions.rides set search_started_at = statement_timestamp() where id = ?", ride);
        }
        if (trip.status() != RideState.SEARCHING_DRIVER) {
            return;
        }
        db.update("""
                update transactions.ride_offers set state = 'EXPIRED'
                where ride_id = ? and state = 'PENDING' and expires_at <= statement_timestamp()
                """, ride);
        if (exists("select exists(select 1 from transactions.ride_offers where ride_id = ? and state = 'PENDING')", ride)) {
            return;
        }
        boolean elapsed = exists("""
                select search_started_at <= statement_timestamp() - interval '2 minutes'
                from transactions.rides where id = ?
                """, ride);
        if (elapsed) {
            change(trip, Actor.SYSTEM, Action.EXPIRE, null);
            return;
        }
        var candidates = db.query("""
                select d.user_id, v.ride_class, d.latitude, d.longitude, d.observed_at
                from transactions.ride_drivers d
                join transactions.ride_vehicles v on v.driver_id = d.user_id
                join identity.users u on u.id = d.user_id
                where d.online and d.status = 'APPROVED' and v.status = 'APPROVED' and u.status = 'ACTIVE'
                    and d.observed_at is not null and v.ride_class = ? and d.user_id <> ?
                    and not exists(select 1 from transactions.rides r where r.driver_id = d.user_id
                        and r.status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS'))
                    and not exists(select 1 from transactions.ride_offers o where o.ride_id = ? and o.driver_id = d.user_id)
                """ + ELIGIBLE_FLEET, (rs, row) -> new Candidate(rs.getObject("user_id", UUID.class),
                        RideClass.valueOf(rs.getString("ride_class")), true, true, true, false,
                        new Point(rs.getDouble("latitude"), rs.getDouble("longitude")),
                        rs.getObject("observed_at", OffsetDateTime.class).toInstant()),
                trip.rideClass().name(), customer, ride, toggles.rides().partnerAvailable());
        var asOf = Objects.requireNonNull(db.queryForObject("select statement_timestamp()", OffsetDateTime.class));
        RideMatching.nearest(trip.pickup(), trip.rideClass(), candidates, Set.of(), asOf.toInstant(),
                Duration.ofMinutes(2), 5000).ifPresent(candidate -> db.update("""
                        insert into transactions.ride_offers (ride_id, driver_id, expires_at)
                        values (?, ?, statement_timestamp() + interval '25 seconds')
                        """, ride, candidate.driverId()));
    }

    public List<Offer> offers(UUID driver) {
        if (!toggles.rides().dispatchAvailable()) {
            return List.of();
        }
        return db.query("""
                select o.id, o.ride_id, o.state, o.expires_at, q.synthetic
                from transactions.ride_offers o
                join transactions.rides r on r.id = o.ride_id
                join transactions.ride_fare_quotes q on q.id = r.quote_id
                join transactions.ride_drivers d on d.user_id = o.driver_id
                join transactions.ride_vehicles v on v.driver_id = d.user_id
                where o.driver_id = ? and o.state = 'PENDING' and o.expires_at > statement_timestamp()
                    and r.status = 'SEARCHING_DRIVER' and d.online and d.status = 'APPROVED' and v.status = 'APPROVED'
                """ + ELIGIBLE_FLEET + """
                order by o.expires_at, o.id limit 30
                """, (rs, row) -> new Offer(rs.getObject("id", UUID.class), rs.getObject("ride_id", UUID.class),
                        rs.getString("state"), rs.getObject("expires_at", OffsetDateTime.class),
                        rs.getBoolean("synthetic")), driver, toggles.rides().partnerAvailable());
    }

    @Transactional
    public void respond(UUID driver, UUID offerId, boolean accept) {
        var offer = db.query("""
                select ride_id from transactions.ride_offers where id = ? and driver_id = ?
                """, (rs, row) -> rs.getObject(1, UUID.class), offerId, driver)
                .stream().findFirst().orElseThrow(() -> missing("RIDE_OFFER_NOT_FOUND"));
        var trip = lockTrip(offer);
        String state = db.queryForObject("select state from transactions.ride_offers where id = ?", String.class, offerId);
        if (accept && "ACCEPTED".equals(state) || !accept && "REJECTED".equals(state)) {
            return;
        }
        if (!toggles.rides().dispatchAvailable() || trip.status() != RideState.SEARCHING_DRIVER || !"PENDING".equals(state)
                || !exists("select expires_at > statement_timestamp() from transactions.ride_offers where id = ?", offerId)) {
            throw conflict("RIDE_OFFER_UNAVAILABLE");
        }
        if (!accept) {
            db.update("update transactions.ride_offers set state = 'REJECTED' where id = ?", offerId);
            return;
        }
        db.queryForObject("select id from identity.users where id = ? for no key update", UUID.class, driver);
        db.queryForObject("select user_id from transactions.ride_drivers where user_id = ? for update", UUID.class, driver);
        if (!exists("""
                select exists(select 1 from transactions.ride_drivers d
                    join transactions.ride_vehicles v on v.driver_id = d.user_id
                    where d.user_id = ? and d.status = 'APPROVED' and d.online
                        and not exists (select 1 from transactions.deliveries active where active.courier_id = d.user_id
                            and active.status in
                """ + DeliveryDispatch.ACTIVE_DELIVERY_STATES + """
                        )
                        and d.observed_at > statement_timestamp() - interval '2 minutes'
                        and v.status = 'APPROVED' and v.ride_class = ?
                        and not exists(select 1 from transactions.rides r where r.driver_id = d.user_id
                            and r.status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS'))
                """ + ELIGIBLE_FLEET + ")", driver, trip.rideClass().name(), toggles.rides().partnerAvailable())
                || !exists("select expires_at > statement_timestamp() from transactions.ride_offers where id = ?", offerId)) {
            throw conflict("RIDE_DRIVER_UNAVAILABLE");
        }
        change(trip, Actor.SYSTEM, Action.ASSIGN, driver);
        db.update("""
                update transactions.rides set fleet_partner_id =
                    (select fleet_partner_id from transactions.ride_drivers where user_id = ?) where id = ?
                """, driver, trip.id());
        db.update("update transactions.ride_offers set state = 'ACCEPTED' where id = ?", offerId);
    }

    @Transactional
    public void progress(UUID driver, UUID ride, Action action) {
        var trip = lockTrip(ride);
        if (!driver.equals(trip.driverId())) {
            throw missing("RIDE_NOT_FOUND");
        }
        RideState target = switch (action) {
            case DEPART -> RideState.DRIVER_ARRIVING;
            case ARRIVE -> RideState.DRIVER_ARRIVED;
            case START -> RideState.IN_PROGRESS;
            case COMPLETE -> RideState.COMPLETED;
            case CANCEL -> RideState.CANCELLED_BY_DRIVER;
            default -> throw conflict("RIDE_TRANSITION_UNAVAILABLE");
        };
        if (!exists("select exists(select 1 from transactions.ride_events where ride_id = ? and status = ?)",
                ride, target.name())) {
            change(trip, Actor.ASSIGNED_DRIVER, action, driver);
        }
    }

    public Optional<DriverLocation> driverLocation(UUID customer, UUID ride) {
        var location = db.query("""
                select d.latitude, d.longitude, d.observed_at
                from transactions.rides r left join transactions.ride_drivers d on d.user_id = r.driver_id
                    and d.online and d.observed_at > statement_timestamp() - interval '2 minutes'
                    and r.status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')
                where r.id = ? and r.user_id = ?
                """, (rs, row) -> {
                    var observedAt = rs.getObject("observed_at", OffsetDateTime.class);
                    return observedAt == null ? Optional.<DriverLocation>empty() :
                            Optional.of(new DriverLocation(new Point(rs.getDouble("latitude"), rs.getDouble("longitude")),
                                    observedAt));
                }, ride, customer);
        return location.stream().findFirst().orElseThrow(() -> missing("RIDE_NOT_FOUND"));
    }

    /**
     * The assigned driver's trips. Pickup and destination coordinates are included only while the trip is active (the driver needs them to
     * navigate) and are withheld from finished or cancelled trips, so history keeps no location of the passenger.
     */
    public List<DriverTrip> history(UUID driver) {
        return db.query("""
                select r.id, r.status, q.ride_class, r.created_at, q.synthetic,
                       q.pickup_latitude, q.pickup_longitude, q.destination_latitude, q.destination_longitude,
                       q.estimate_kzt,
                       (select max(e.occurred_at) from transactions.ride_events e
                        where e.ride_id = r.id and e.status = 'COMPLETED')
                from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
                where r.driver_id = ? order by r.created_at desc, r.id desc limit 50
                """, (rs, row) -> {
                    var status = RideState.valueOf(rs.getString(2));
                    var active = ACTIVE_FOR_DRIVER.contains(status);
                    return new DriverTrip(rs.getObject(1, UUID.class), status, RideClass.valueOf(rs.getString(3)),
                            rs.getObject(4, OffsetDateTime.class), rs.getBoolean(5),
                            active ? new Point(rs.getDouble(6), rs.getDouble(7)) : null,
                            active ? new Point(rs.getDouble(8), rs.getDouble(9)) : null,
                            rs.getBigDecimal(10), rs.getObject(11, OffsetDateTime.class));
                }, driver);
    }

    private static final java.util.Set<RideState> ACTIVE_FOR_DRIVER = java.util.EnumSet.of(RideState.DRIVER_ASSIGNED,
            RideState.DRIVER_ARRIVING, RideState.DRIVER_ARRIVED, RideState.IN_PROGRESS);

    private static final String ELIGIBLE_FLEET = """
            and (d.fleet_partner_id is null or (? and exists (
                select 1 from transactions.ride_fleets f
                join marketplace.partners p on p.id = f.partner_id
                join marketplace.partner_staff s on s.partner_id = f.partner_id and s.user_id = d.user_id
                where f.partner_id = d.fleet_partner_id and f.status = 'APPROVED'
                    and p.verification_status = 'APPROVED' and s.status = 'ACTIVE')))
            """;

    private static final String SELECT = """
            select r.id, r.user_id, r.driver_id, r.status, q.ride_class, q.pickup_latitude, q.pickup_longitude
            from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
            """;

    private Trip lockTrip(UUID id) {
        return db.query(SELECT + " where r.id = ? for update of r", (rs, row) ->
                new Trip(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                        RideState.valueOf(rs.getString(4)), RideClass.valueOf(rs.getString(5)),
                        new Point(rs.getDouble(6), rs.getDouble(7))), id)
                .stream().findFirst().orElseThrow(() -> missing("RIDE_NOT_FOUND"));
    }

    private Trip change(Trip ride, Actor actor, Action action, UUID driver) {
        var state = ride.status().transition(actor, action).orElseThrow(() -> conflict("RIDE_TRANSITION_UNAVAILABLE"));
        db.update("update transactions.rides set status = ?, driver_id = ? where id = ?", state.name(), driver, ride.id());
        db.update("insert into transactions.ride_events (ride_id, status) values (?, ?)", ride.id(), state.name());
        return new Trip(ride.id(), ride.customerId(), driver, state, ride.rideClass(), ride.pickup());
    }

    private boolean exists(String sql, Object... args) {
        return Boolean.TRUE.equals(db.queryForObject(sql, Boolean.class, args));
    }

    private static ApiException missing(String code) {
        return new ApiException(HttpStatus.NOT_FOUND, code, "Ride resource not found");
    }

    private static ApiException conflict(String code) {
        return new ApiException(HttpStatus.CONFLICT, code, "Ride operation is unavailable in its current state");
    }

    private record Trip(UUID id, UUID customerId, UUID driverId, RideState status, RideClass rideClass, Point pickup) {}
    public record DriverLocation(Point point, OffsetDateTime observedAt) {}
    public record DriverTrip(UUID id, RideState status, RideClass rideClass, OffsetDateTime createdAt, boolean synthetic,
            Point pickup, Point destination, java.math.BigDecimal fareKzt, OffsetDateTime completedAt) {}
    public record Offer(UUID id, UUID rideId, String state, OffsetDateTime expiresAt, boolean synthetic) {}
}
