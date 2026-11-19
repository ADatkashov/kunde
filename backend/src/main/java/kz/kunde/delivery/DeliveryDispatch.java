package kz.kunde.delivery;

import static kz.kunde.delivery.DeliveryState.Action.*;
import static kz.kunde.delivery.DeliveryState.Actor.*;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideMatching;
import kz.kunde.rides.RideMatching.Point;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeliveryDispatch {
    public static final String ACTIVE_DELIVERY_STATES = """
            ('COURIER_ASSIGNED','COURIER_ARRIVING','COURIER_ARRIVED','PICKED_UP','IN_TRANSIT',
             'DELIVERED','DELIVERY_FAILED','RETURN_REQUESTED','RETURNING')
            """;

    private static final String AVAILABLE = """
            and c.online and c.status = 'APPROVED' and u.status = 'ACTIVE'
            and c.observed_at > statement_timestamp() - interval '2 minutes'
            and c.max_grams >= q.weight_grams and c.max_side_cm >= greatest(q.length_cm, q.width_cm, q.height_cm)
            and not exists (select 1 from transactions.rides r where r.driver_id = c.user_id and
                r.status in ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS'))
            and not exists (select 1 from transactions.deliveries active where active.courier_id = c.user_id
                and active.status in """ + " " + ACTIVE_DELIVERY_STATES + ") ";

    private final JdbcTemplate db;
    private final DeliveryProperties flags;
    private final byte[] handoffKey;

    public DeliveryDispatch(JdbcTemplate db, DeliveryProperties flags,
            @Value("${DELIVERY_HANDOFF_KEY:}") String handoffKey) {
        this.db = db;
        this.flags = flags;
        this.handoffKey = handoffKey.getBytes(StandardCharsets.UTF_8);
        if (flags.dispatchAvailable() && this.handoffKey.length < 32) {
            throw new IllegalStateException("Delivery dispatch requires a configured handoff secret");
        }
    }

    @Transactional
    public void search(UUID sender, UUID partner, UUID id) {
        requireDispatch();
        var trip = lock(id);
        if (!senderScope(trip, sender, partner)) {
            throw missing();
        }
        if (trip.state() == DeliveryState.CREATED) {
            trip = transition(trip, SYSTEM, SEARCH, sender, null);
            db.update("update transactions.deliveries set search_started_at = statement_timestamp() where id = ?", id);
        }
        if (trip.state() != DeliveryState.SEARCHING_COURIER) {
            return;
        }
        db.update("""
                update transactions.delivery_offers set state = 'EXPIRED'
                where delivery_id = ? and state = 'PENDING' and expires_at <= statement_timestamp()
                """, id);
        if (exists("""
                select search_started_at <= statement_timestamp() - interval '2 minutes'
                from transactions.deliveries where id = ?
                """, id)) {
            transition(trip, SYSTEM, EXPIRE, sender, null);
            db.update("update transactions.delivery_offers set state = 'EXPIRED' where delivery_id = ? and state = 'PENDING'", id);
            return;
        }
        if (exists("select exists(select 1 from transactions.delivery_offers where delivery_id = ? and state = 'PENDING')", id)) {
            return;
        }
        Point pickup = tripPickup(id);
        var candidates = db.query("""
                select c.user_id, c.latitude, c.longitude
                from transactions.delivery_couriers c join identity.users u on u.id = c.user_id
                cross join transactions.delivery_quotes q
                where q.id = ? and c.user_id <> ?
                  and not exists (select 1 from transactions.delivery_offers o
                                  where o.delivery_id = ? and o.courier_id = c.user_id)
                """ + AVAILABLE, (rs, row) -> new Candidate(rs.getObject("user_id", UUID.class),
                        RideMatching.distanceMeters(pickup, new Point(rs.getDouble("latitude"), rs.getDouble("longitude")))),
                trip.quote(), trip.sender(), id);
        candidates.stream().filter(candidate -> candidate.distance() <= 5000)
                .min(Comparator.comparingDouble(Candidate::distance).thenComparing(Candidate::id))
                .ifPresent(candidate -> db.update("""
                        insert into transactions.delivery_offers(delivery_id, courier_id, expires_at)
                        values (?, ?, statement_timestamp() + interval '25 seconds')
                        """, id, candidate.id()));
    }

    private Point tripPickup(UUID id) {
        return db.queryForObject("""
                select q.pickup_latitude, q.pickup_longitude from transactions.deliveries d
                join transactions.delivery_quotes q on q.id = d.quote_id where d.id = ?
                """, (rs, row) -> new Point(rs.getDouble(1), rs.getDouble(2)), id);
    }

    public List<Offer> offers(UUID courier) {
        if (!flags.dispatchAvailable()) {
            return List.of();
        }
        return db.query("""
                select o.id, o.delivery_id, o.expires_at, q.parcel_type, q.weight_grams, q.length_cm, q.width_cm,
                    q.height_cm, q.distance_meters, q.synthetic_route
                from transactions.delivery_offers o join transactions.deliveries d on d.id = o.delivery_id
                join transactions.delivery_couriers c on c.user_id = o.courier_id
                join identity.users u on u.id = c.user_id join transactions.delivery_quotes q on q.id = d.quote_id
                where o.courier_id = ? and o.state = 'PENDING' and o.expires_at > statement_timestamp()
                    and d.status = 'SEARCHING_COURIER'
                """ + AVAILABLE + " order by o.expires_at, o.id limit 30", (rs, row) ->
                new Offer(rs.getObject("id", UUID.class), rs.getObject("delivery_id", UUID.class),
                        rs.getObject("expires_at", OffsetDateTime.class), rs.getString("parcel_type"),
                        rs.getInt("weight_grams"), rs.getInt("length_cm"), rs.getInt("width_cm"),
                        rs.getInt("height_cm"), rs.getInt("distance_meters"), rs.getBoolean("synthetic_route")), courier);
    }

    @Transactional
    public void respond(UUID courier, UUID offerId, boolean accept) {
        UUID id = db.query("select delivery_id from transactions.delivery_offers where id = ? and courier_id = ?",
                (rs, row) -> rs.getObject(1, UUID.class), offerId, courier).stream().findFirst()
                .orElseThrow(DeliveryDispatch::missing);
        var trip = lock(id);
        var state = db.queryForObject("select state from transactions.delivery_offers where id = ?", String.class, offerId);
        if ((accept && "ACCEPTED".equals(state)) || (!accept && "REJECTED".equals(state))) {
            return;
        }
        requireDispatch();
        if (trip.state() != DeliveryState.SEARCHING_COURIER || !"PENDING".equals(state) || !unexpired(offerId)) {
            throw conflict("DELIVERY_OFFER_UNAVAILABLE");
        }
        if (!accept) {
            db.update("update transactions.delivery_offers set state = 'REJECTED' where id = ?", offerId);
            search(trip.sender(), trip.partner(), id);
            return;
        }
        db.queryForObject("select id from identity.users where id = ? for no key update", UUID.class, courier);
        db.queryForObject("select user_id from transactions.delivery_couriers where user_id = ? for update", UUID.class, courier);
        if (!exists("""
                select exists (select 1 from transactions.delivery_couriers c join identity.users u on u.id = c.user_id
                    cross join transactions.delivery_quotes q where c.user_id = ? and q.id = ?
                """ + AVAILABLE + ")", courier, trip.quote()) || !unexpired(offerId)) {
            throw conflict("DELIVERY_COURIER_UNAVAILABLE");
        }
        db.update("update transactions.deliveries set courier_id = ? where id = ?", courier, id);
        transition(trip, SYSTEM, ASSIGN, courier, null);
        db.update("update transactions.delivery_offers set state = 'ACCEPTED' where id = ?", offerId);
    }

    public List<CourierShipment> shipments(UUID courier) {
        return db.query("""
                select d.id, d.status, d.created_at, q.parcel_type, q.synthetic_route,
                       case when d.status in %s then d.pickup_address end as pickup_address,
                       case when d.status in %s then d.destination_address end as destination_address,
                       case when d.status in %s then d.courier_note end as courier_note
                from transactions.deliveries d join transactions.delivery_quotes q on q.id = d.quote_id
                where d.courier_id = ?
                order by d.created_at desc, d.id desc limit 100
                """.formatted(ACTIVE_DELIVERY_STATES, ACTIVE_DELIVERY_STATES, ACTIVE_DELIVERY_STATES),
                (rs, row) -> new CourierShipment(rs.getObject("id", UUID.class),
                        DeliveryState.valueOf(rs.getString("status")), rs.getString("parcel_type"),
                        rs.getString("pickup_address"), rs.getString("destination_address"), rs.getString("courier_note"),
                        rs.getBoolean("synthetic_route"), rs.getObject("created_at", OffsetDateTime.class)), courier);
    }

    @Transactional
    public DeliveryState progress(UUID courier, UUID id, DeliveryState.Action action) {
        var trip = assigned(courier, id);
        var renewed = trip.state().transition(COURIER, action);
        if (renewed.isEmpty()) {
            return switch (action) {
                case DEPART -> replay(trip, DeliveryState.COURIER_ARRIVING, courier);
                case ARRIVE -> replay(trip, DeliveryState.COURIER_ARRIVED, courier);
                case PICK_UP -> replay(trip, DeliveryState.PICKED_UP, courier);
                case TRANSIT -> replay(trip, DeliveryState.IN_TRANSIT, courier);
                case COMPLETE -> replay(trip, DeliveryState.COMPLETED, courier);
                case CANCEL -> replay(trip, DeliveryState.CANCELLED_BY_COURIER, courier);
                case FAIL_PICKUP -> replay(trip, DeliveryState.PICKUP_FAILED, courier);
                case FAIL_DELIVERY -> replay(trip, DeliveryState.DELIVERY_FAILED, courier);
                case START_RETURN -> replay(trip, DeliveryState.RETURNING, courier);
                case CONFIRM_RETURN -> replay(trip, DeliveryState.RETURNED_TO_SENDER, courier);
                default -> throw conflict("DELIVERY_TRANSITION_INVALID");
            };
        }
        return transition(trip, COURIER, action, courier, switch (action) {
            case FAIL_PICKUP -> "SENDER_UNAVAILABLE";
            case FAIL_DELIVERY -> "RECIPIENT_UNAVAILABLE";
            default -> null;
        }).state();
    }

    @Transactional
    public DeliveryState requestReturn(UUID admin, UUID id) {
        var trip = lock(id);
        return trip.state() == DeliveryState.DELIVERY_FAILED
                ? transition(trip, ADMIN, REQUEST_RETURN, admin, "RECIPIENT_UNAVAILABLE").state()
                : replay(trip, DeliveryState.RETURN_REQUESTED, admin);
    }

    @Transactional
    public HandoffCode issueCode(UUID sender, UUID partner, UUID id) {
        var trip = lock(id);
        if (!senderScope(trip, sender, partner)) {
            throw missing();
        }
        if (trip.state() != DeliveryState.IN_TRANSIT || handoffKey.length < 32) {
            throw conflict("DELIVERY_HANDOFF_UNAVAILABLE");
        }
        UUID nonce = UUID.randomUUID();
        String code = handoffCode(id, nonce);
        db.update("""
                insert into transactions.delivery_handoff_codes(delivery_id, token_hash, nonce, expires_at)
                values (?, ?, ?, statement_timestamp() + interval '15 minutes')
                on conflict (delivery_id) do update set token_hash = excluded.token_hash,
                    nonce = excluded.nonce, expires_at = excluded.expires_at, failed_attempts = 0
                where transactions.delivery_handoff_codes.used_at is null
                  and transactions.delivery_handoff_codes.expires_at <= statement_timestamp()
                """, id, digest(id + ":" + code), nonce);
        return db.query("""
                select nonce, expires_at from transactions.delivery_handoff_codes where delivery_id = ?
                and nonce is not null and used_at is null and failed_attempts < 5 and expires_at > statement_timestamp()
                """, (rs, row) -> new HandoffCode(handoffCode(id, rs.getObject("nonce", UUID.class)),
                        rs.getObject("expires_at", OffsetDateTime.class), true), id)
                .stream().findFirst().orElseThrow(() -> conflict("DELIVERY_HANDOFF_UNAVAILABLE"));
    }

    private String handoffCode(UUID id, UUID nonce) {
        long entropy = ByteBuffer.wrap(digest("issue:" + id + ":" + nonce)).getLong();
        return String.format(Locale.ROOT, "%08d", Long.remainderUnsigned(entropy, 100_000_000L));
    }

    @Transactional
    public boolean verifyCode(UUID courier, UUID id, String code) {
        var trip = assigned(courier, id);
        if (trip.state() == DeliveryState.DELIVERED || trip.state() == DeliveryState.COMPLETED) {
            return false;
        }
        if (trip.state() != DeliveryState.IN_TRANSIT || handoffKey.length < 32) {
            throw conflict("DELIVERY_HANDOFF_UNAVAILABLE");
        }
        var valid = db.query("""
                select token_hash from transactions.delivery_handoff_codes where delivery_id = ?
                  and used_at is null and failed_attempts < 5 and expires_at > statement_timestamp()
                """, (rs, row) -> rs.getBytes(1), id);
        if (valid.isEmpty()) {
            return false;
        }
        if (!MessageDigest.isEqual(valid.getFirst(), digest(id + ":" + code))) {
            db.update("update transactions.delivery_handoff_codes set failed_attempts = failed_attempts + 1 where delivery_id = ?", id);
            return false;
        }
        db.update("update transactions.delivery_handoff_codes set used_at = statement_timestamp() where delivery_id = ?", id);
        transition(trip, SYSTEM, VERIFY_HANDOFF, courier, "ONE_TIME_CODE");
        return true;
    }

    private byte[] digest(String value) {
        try {
            var mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(handoffKey, "HmacSHA256"));
            return mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
        } catch (java.security.GeneralSecurityException failure) {
            throw new IllegalStateException("Delivery handoff algorithm unavailable", failure);
        }
    }

    private Trip assigned(UUID courier, UUID id) {
        var trip = lock(id);
        if (!courier.equals(trip.courier())) {
            throw missing();
        }
        return trip;
    }

    private Trip lock(UUID id) {
        return db.query("select id, user_id, partner_id, quote_id, courier_id, status from transactions.deliveries where id = ? for update",
                (rs, row) -> new Trip(rs.getObject("id", UUID.class), rs.getObject("user_id", UUID.class),
                        rs.getObject("partner_id", UUID.class), rs.getObject("quote_id", UUID.class), rs.getObject("courier_id", UUID.class),
                        DeliveryState.valueOf(rs.getString("status"))), id)
                .stream().findFirst().orElseThrow(DeliveryDispatch::missing);
    }

    private Trip transition(Trip trip, DeliveryState.Actor role, DeliveryState.Action action, UUID actor, String reason) {
        var state = trip.state().transition(role, action).orElseThrow(() -> conflict("DELIVERY_TRANSITION_INVALID"));
        db.update("update transactions.deliveries set status = cast(? as transactions.delivery_state) where id = ?",
                state.name(), trip.id());
        db.update("""
                insert into transactions.delivery_events(delivery_id, actor_id, status, reason)
                values (?, ?, cast(? as transactions.delivery_state), ?)
                """, trip.id(), actor, state.name(), reason);
        return new Trip(trip.id(), trip.sender(), trip.partner(), trip.quote(), trip.courier(), state);
    }

    private DeliveryState replay(Trip trip, DeliveryState state, UUID actor) {
        if (!exists("""
                select exists (select 1 from transactions.delivery_events
                    where delivery_id = ? and actor_id = ? and status = cast(? as transactions.delivery_state))
                """, trip.id(), actor, state.name())) {
            throw conflict("DELIVERY_TRANSITION_INVALID");
        }
        return trip.state();
    }

    private boolean unexpired(UUID offerId) {
        return exists("select expires_at > statement_timestamp() from transactions.delivery_offers where id = ?", offerId);
    }

    private boolean exists(String sql, Object... args) {
        return Boolean.TRUE.equals(db.queryForObject(sql, Boolean.class, args));
    }

    private void requireDispatch() {
        if (!flags.dispatchAvailable()) {
            throw missing();
        }
    }

    private static ApiException missing() {
        return new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_DISPATCH_NOT_FOUND", "Delivery operation unavailable");
    }

    private static ApiException conflict(String code) {
        return new ApiException(HttpStatus.CONFLICT, code, "Delivery operation conflicts with current state");
    }

    private record Candidate(UUID id, double distance) {}
    private record Trip(UUID id, UUID sender, UUID partner, UUID quote, UUID courier, DeliveryState state) {}

    private static boolean senderScope(Trip trip, UUID actor, UUID partner) {
        return partner == null ? trip.partner() == null && actor.equals(trip.sender()) : partner.equals(trip.partner());
    }
    public record Offer(UUID id, UUID deliveryId, OffsetDateTime expiresAt, String parcelType, int weightGrams,
            int lengthCm, int widthCm, int heightCm, int distanceMeters, boolean syntheticRoute) {}
    public record CourierShipment(UUID id, DeliveryState status, String parcelType, String pickupAddress,
            String destinationAddress, String courierNote, boolean syntheticRoute, OffsetDateTime createdAt) {}
    public record HandoffCode(String code, OffsetDateTime expiresAt, boolean devManualRelay) {
        @Override
        public String toString() {
            return "HandoffCode[expiresAt=" + expiresAt + ", devManualRelay=" + devManualRelay + "]";
        }
    }
}
