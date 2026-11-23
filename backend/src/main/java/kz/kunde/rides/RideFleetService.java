package kz.kunde.rides;

import kz.kunde.platform.FeatureToggles;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideDriverService.Decision;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RideFleetService {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;
    private final PartnerService partners;

    public RideFleetService(JdbcTemplate db, FeatureToggles toggles, PartnerService partners) {
        this.db = db;
        this.toggles = toggles;
        this.partners = partners;
    }

    @Transactional
    public Fleet apply(UUID actor, UUID partner) {
        requirePartner(actor, partner, Role.OWNER);
        if (db.update("insert into transactions.ride_fleets (partner_id) values (?) on conflict do nothing", partner) == 1) {
            event(partner, actor, null, "APPLIED");
        }
        return view(actor, partner);
    }

    @Transactional(readOnly = true)
    public Fleet view(UUID actor, UUID partner) {
        requirePartner(actor, partner);
        String current = status(partner, false);
        var drivers = db.query("""
                select d.user_id, d.display_name, d.status, d.online, v.description, v.plate, v.ride_class, v.status,
                    (select round(avg(x.stars), 1) from transactions.ride_ratings x where x.driver_id = d.user_id),
                    (select count(*) from transactions.ride_ratings x where x.driver_id = d.user_id)
                from transactions.ride_drivers d left join transactions.ride_vehicles v on v.driver_id = d.user_id
                where d.fleet_partner_id = ? order by d.display_name, d.user_id limit 100
                """, (rs, row) -> new Driver(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3),
                        rs.getBoolean(4), rs.getString(5), rs.getString(6), rs.getString(7), rs.getString(8),
                        rs.getLong(10) == 0 ? null : rs.getBigDecimal(9), rs.getLong(10)), partner);
        var trips = db.query("""
                select r.id, r.status, r.driver_id, r.created_at, q.synthetic, q.ride_class, q.estimate_kzt
                from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
                where r.fleet_partner_id = ? order by r.created_at desc, r.id desc limit 100
                """, (rs, row) -> new Trip(rs.getObject(1, UUID.class), RideState.valueOf(rs.getString(2)),
                        rs.getObject(3, UUID.class), rs.getObject(4, OffsetDateTime.class), rs.getBoolean(5),
                        RideMatching.RideClass.valueOf(rs.getString(6)), rs.getBigDecimal(7)), partner);
        var stats = db.queryForObject("""
                select count(*) filter (where status = 'COMPLETED'),
                    count(*) filter (where status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')),
                    coalesce(sum(q.estimate_kzt) filter (where status = 'COMPLETED'), 0)
                from transactions.rides r join transactions.ride_fare_quotes q on q.id = r.quote_id
                where r.fleet_partner_id = ? and not q.synthetic
                """, (rs, row) -> new Stats(rs.getLong(1), rs.getLong(2), rs.getBigDecimal(3)), partner);
        var role = partners.activeRole(partner, actor).orElseThrow(RideFleetService::missing);
        List<Candidate> candidates = role == Role.OPERATOR ? List.of() : db.query("""
                select d.user_id, d.display_name from transactions.ride_drivers d
                join marketplace.partner_staff s on s.user_id = d.user_id
                join identity.users u on u.id = d.user_id
                where s.partner_id = ? and s.status = 'ACTIVE' and u.status = 'ACTIVE'
                    and d.fleet_partner_id is null
                order by d.display_name, d.user_id limit 100
                """, (rs, row) -> new Candidate(rs.getObject(1, UUID.class), rs.getString(2)), partner);
        return new Fleet(partner, current, drivers, candidates, trips, stats);
    }

    @Transactional
    public Fleet assignment(UUID actor, UUID partner, UUID driver, boolean attach) {
        requirePartner(actor, partner, Role.OWNER, Role.MANAGER);
        if (attach && !"APPROVED".equals(status(partner, true))) {
            throw conflict("RIDE_FLEET_NOT_APPROVED");
        }
        if (attach) {
            partners.requireProcessing(driver, partner);
        } else {
            status(partner, true);
        }
        var rows = db.query("""
                select fleet_partner_id from transactions.ride_drivers where user_id = ? for update
                """, (rs, row) -> rs.getObject(1, UUID.class), driver);
        if (rows.isEmpty()) {
            throw missing();
        }
        UUID existing = rows.getFirst();
        if (existing != null && !existing.equals(partner)) {
            throw missing();
        }
        if (attach == (existing != null)) {
            return view(actor, partner);
        }
        if (Boolean.TRUE.equals(db.queryForObject("""
                select exists(select 1 from transactions.rides where driver_id = ?
                    and status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS'))
                """, Boolean.class, driver))) {
            throw conflict("RIDE_DRIVER_BUSY");
        }
        db.update("""
                update transactions.ride_drivers set fleet_partner_id = ?, online = false,
                    latitude = null, longitude = null, observed_at = null where user_id = ?
                """, attach ? partner : null, driver);
        event(partner, actor, driver, attach ? "ATTACHED" : "DETACHED");
        return view(actor, partner);
    }

    public List<FleetReview> reviewQueue() {
        requireEnabled();
        return db.query("""
                select f.partner_id, f.status, p.display_name
                from transactions.ride_fleets f join marketplace.partners p on p.id = f.partner_id
                order by (f.status = 'PENDING') desc, f.created_at desc, f.partner_id limit 100
                """, (rs, row) -> new FleetReview(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3)));
    }

    @Transactional
    public void review(UUID reviewer, UUID partner, Decision decision) {
        requireEnabled();
        if (partners.activeRole(partner, reviewer).isPresent()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "RIDE_SELF_REVIEW", "Fleet members cannot review their fleet");
        }
        var prior = status(partner, true);
        if (decision == Decision.APPROVED && !partners.eligibleForCatalogGate(partner)) {
            throw conflict("RIDE_PARTNER_NOT_APPROVED");
        }
        if (!prior.equals(decision.name())) {
            db.update("update transactions.ride_fleets set status = ? where partner_id = ?", decision.name(), partner);
            event(partner, reviewer, null, decision.name());
        }
    }

    public List<FleetEvent> audit(UUID partner) {
        requireEnabled();
        status(partner, false);
        return db.query("""
                select id, actor_id, driver_id, action, occurred_at
                from transactions.ride_fleet_events where partner_id = ? order by id desc limit 100
                """, (rs, row) -> new FleetEvent(rs.getLong(1), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                        rs.getString(4), rs.getObject(5, OffsetDateTime.class)), partner);
    }

    private void requirePartner(UUID actor, UUID partner, Role... roles) {
        requireEnabled();
        partners.requireProcessing(actor, partner, roles);
    }

    private void requireEnabled() {
        if (!toggles.rides().partnerAvailable()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RIDES_PARTNER_UNAVAILABLE", "Fleet service is unavailable");
        }
    }

    private String status(UUID partner, boolean lock) {
        return db.query("select status from transactions.ride_fleets where partner_id = ?" + (lock ? " for update" : ""),
                (rs, row) -> rs.getString(1), partner).stream().findFirst().orElseThrow(RideFleetService::missing);
    }

    private void event(UUID partner, UUID actor, UUID driver, String action) {
        db.update("insert into transactions.ride_fleet_events (partner_id, actor_id, driver_id, action) values (?, ?, ?, ?)",
                partner, actor, driver, action);
    }

    private static ApiException missing() {
        return new ApiException(HttpStatus.NOT_FOUND, "RIDE_FLEET_NOT_FOUND", "Fleet resource not found");
    }

    private static ApiException conflict(String code) {
        return new ApiException(HttpStatus.CONFLICT, code, "Fleet operation is unavailable in its current state");
    }

    public record Fleet(UUID partnerId, String status, List<Driver> drivers, List<Candidate> candidates, List<Trip> trips, Stats stats) {}
    public record Driver(UUID id, String name, String status, boolean online, String vehicle,
            String plate, String rideClass, String vehicleStatus, java.math.BigDecimal rating, long ratings) {}
    public record Candidate(UUID id, String name) {}
    public record Trip(UUID id, RideState status, UUID driverId, OffsetDateTime createdAt, boolean synthetic,
            RideMatching.RideClass rideClass, java.math.BigDecimal fareKzt) {}
    /** completedFareKzt sums quoted tariff fares of completed, non-synthetic rides; no payment is captured. */
    public record Stats(long completed, long active, java.math.BigDecimal completedFareKzt) {}
    public record FleetReview(UUID id, String status, String name) {}
    public record FleetEvent(long id, UUID actorId, UUID driverId, String action, OffsetDateTime occurredAt) {}
}
