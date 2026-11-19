package kz.kunde.delivery;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.regex.Pattern;
import kz.kunde.delivery.DeliveryController.CreateRequest;
import kz.kunde.delivery.DeliveryController.QuoteRequest;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideRouting;
import kz.kunde.rides.SyntheticRideRouting;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeliveryService {
    private static final RideRouting TEST_ROUTING = new SyntheticRideRouting();
    private static final Pattern REQUEST_KEY = Pattern.compile("[A-Za-z0-9_-]{16,64}");
    private static final String ORDERS = """
            select d.*, q.parcel_type, q.amount_kzt, q.synthetic_route, c.display_name as courier_name, c.vehicle
            from transactions.deliveries d
            join transactions.delivery_quotes q on q.id = d.quote_id
            left join transactions.delivery_couriers c on c.user_id = d.courier_id
            """;
    private final JdbcTemplate db;
    private final DeliveryProperties settings;
    private final ObjectProvider<RideRouting> routing;

    public DeliveryService(JdbcTemplate db, DeliveryProperties settings, ObjectProvider<RideRouting> routing) {
        this.db = db;
        this.settings = settings;
        this.routing = routing;
    }

    public Quote quote(UUID user, QuoteRequest request) {
        requireIntake();
        if (request.weightGrams() > settings.maxWeightGrams()
                || Math.max(request.lengthCm(), Math.max(request.widthCm(), request.heightCm())) > settings.maxSideCm()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "DELIVERY_LIMIT_EXCEEDED",
                    "Parcel exceeds the configured weight or dimensions");
        }
        var provider = routing.getIfAvailable(() -> settings.syntheticRoutingEnabled() ? TEST_ROUTING : null);
        if (provider == null) {
            throw routingUnavailable();
        }
        RideRouting.Route route;
        try {
            route = provider.route(request.pickup().point(), request.destination().point()).orElseThrow(() ->
                    new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "DELIVERY_ROUTE_NOT_FOUND", "No route found"));
        } catch (RideRouting.Unavailable failure) {
            throw routingUnavailable();
        }
        if (route.synthetic() && !settings.syntheticRoutingEnabled()) {
            throw routingUnavailable();
        }
        var amount = settings.baseKzt()
                .add(settings.perKmKzt().multiply(BigDecimal.valueOf(route.distanceMeters(), 3)))
                .add(settings.perKgKzt().multiply(BigDecimal.valueOf(request.weightGrams(), 3)))
                .max(settings.minimumKzt())
                .setScale(2, RoundingMode.HALF_UP);
        if (amount.precision() > 14) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "DELIVERY_PRICE_OUT_OF_RANGE",
                    "Route cannot be quoted");
        }
        return db.queryForObject("""
                insert into transactions.delivery_quotes
                    (user_id, parcel_type, weight_grams, length_cm, width_cm, height_cm, pickup_latitude,
                     pickup_longitude, destination_latitude, destination_longitude, distance_meters, duration_seconds,
                     synthetic_route, tariff_version, amount_kzt, created_at, expires_at)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, statement_timestamp(),
                        statement_timestamp() + (? * interval '1 second'))
                returning id, created_at, expires_at
                """, (rs, row) -> new Quote(rs.getObject("id", UUID.class), settings.tariffVersion(), amount, "KZT",
                        route.distanceMeters(), route.durationSeconds(), route.synthetic(),
                        rs.getObject("created_at", OffsetDateTime.class), rs.getObject("expires_at", OffsetDateTime.class)),
                user, request.parcelType().name(), request.weightGrams(), request.lengthCm(), request.widthCm(),
                request.heightCm(), request.pickup().latitude(), request.pickup().longitude(),
                request.destination().latitude(), request.destination().longitude(), route.distanceMeters(),
                route.durationSeconds(), route.synthetic(), settings.tariffVersion(), amount, settings.quoteLifetimeSeconds());
    }

    @Transactional
    public Creation create(UUID user, String key, CreateRequest request) {
        if (key == null || !REQUEST_KEY.matcher(key).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_IDEMPOTENCY_KEY", "Invalid Idempotency-Key");
        }
        var prior = replay(user, key, request);
        if (prior != null) {
            return prior;
        }
        requireIntake();
        var inserted = db.query("""
                insert into transactions.deliveries
                    (user_id, quote_id, request_key, pickup_address, destination_address, recipient_name,
                     recipient_phone, description, courier_note, status)
                select user_id, id, ?, ?, ?, ?, ?, ?, ?, 'CREATED'
                from transactions.delivery_quotes
                where user_id = ? and id = ? and expires_at > statement_timestamp()
                    and (not synthetic_route or ?)
                on conflict do nothing
                returning id
                """, (rs, row) -> rs.getObject("id", UUID.class), key, request.pickupAddress(),
                request.destinationAddress(), request.recipientName(), request.recipientPhone(), request.description(),
                request.courierNote(), user, request.quoteId(), settings.syntheticRoutingEnabled());
        if (inserted.isEmpty()) {
            prior = replay(user, key, request);
            if (prior != null) {
                return prior;
            }
            throw new ApiException(HttpStatus.CONFLICT, "DELIVERY_QUOTE_UNAVAILABLE",
                    "Quote is unavailable for this request");
        }
        UUID id = inserted.getFirst();
        recordState(id, user, DeliveryState.CREATED);
        return new Creation(get(user, id), true);
    }

    private Creation replay(UUID user, String key, CreateRequest request) {
        var previous = db.query(ORDERS + " where d.user_id = ? and d.request_key = ?",
                DeliveryService::readOrder, user, key);
        if (previous.isEmpty()) {
            return null;
        }
        var order = previous.getFirst();
        if (!order.quoteId().equals(request.quoteId()) || !order.pickupAddress().equals(request.pickupAddress())
                || !order.destinationAddress().equals(request.destinationAddress())
                || !order.recipientName().equals(request.recipientName())
                || !order.recipientPhone().equals(request.recipientPhone())
                || !order.description().equals(request.description())
                || !Objects.equals(order.courierNote(), request.courierNote())) {
            throw new ApiException(HttpStatus.CONFLICT, "DELIVERY_IDEMPOTENCY_CONFLICT",
                    "Idempotency-Key was already used for different delivery details");
        }
        return new Creation(order, false);
    }

    public List<Order> list(UUID user, int limit, int offset) {
        return db.query(ORDERS + " where d.user_id = ? order by d.created_at desc, d.id desc limit ? offset ?",
                DeliveryService::readOrder, user, limit, offset);
    }

    public Order get(UUID user, UUID id) {
        return db.query(ORDERS + " where d.user_id = ? and d.id = ?", DeliveryService::readOrder, user, id)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_NOT_FOUND",
                        "Delivery was not found"));
    }

    @Transactional
    public Order cancel(UUID user, UUID id) {
        int changed = db.update("""
                update transactions.deliveries set status = 'CANCELLED_BY_CUSTOMER'
                where id = ? and user_id = ? and status in ('CREATED', 'SEARCHING_COURIER', 'COURIER_ASSIGNED', 'COURIER_ARRIVING', 'COURIER_ARRIVED')
                """, id, user);
        if (changed == 1) {
            recordState(id, user, DeliveryState.CANCELLED_BY_CUSTOMER);
        }
        var order = get(user, id);
        if (order.status() != DeliveryState.CANCELLED_BY_CUSTOMER) {
            throw new ApiException(HttpStatus.CONFLICT, "DELIVERY_CANNOT_CANCEL", "Delivery cannot be cancelled");
        }
        return order;
    }

    private void recordState(UUID id, UUID user, DeliveryState status) {
        db.update("insert into transactions.delivery_events (delivery_id, actor_id, status) values (?, ?, cast(? as transactions.delivery_state))",
                id, user, status.name());
    }

    private static Order readOrder(ResultSet rs, int row) throws SQLException {
        return new Order(rs.getObject("id", UUID.class), rs.getObject("quote_id", UUID.class),
                DeliveryState.valueOf(rs.getString("status")), rs.getString("parcel_type"),
                rs.getString("pickup_address"), rs.getString("destination_address"), rs.getString("recipient_name"),
                rs.getString("recipient_phone"), rs.getString("description"), rs.getString("courier_note"),
                rs.getBigDecimal("amount_kzt"), "KZT", rs.getBoolean("synthetic_route"),
                rs.getObject("created_at", OffsetDateTime.class), rs.getString("courier_name") == null ? null
                        : new AssignedCourier(rs.getString("courier_name"), rs.getString("vehicle")));
    }

    private void requireIntake() {
        if (!settings.consumerAvailable()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_UNAVAILABLE", "New deliveries are unavailable");
        }
    }

    private static ApiException routingUnavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "DELIVERY_ROUTING_UNAVAILABLE",
                "Delivery routing is unavailable");
    }

    public record Quote(UUID id, String tariffVersion, BigDecimal amountKzt, String currency, int distanceMeters,
            int durationSeconds, boolean syntheticRoute, OffsetDateTime createdAt, OffsetDateTime expiresAt) {}

    public record Order(UUID id, UUID quoteId, DeliveryState status, String parcelType, String pickupAddress,
            String destinationAddress, String recipientName, String recipientPhone, String description,
            String courierNote, BigDecimal amountKzt, String currency, boolean syntheticRoute,
            OffsetDateTime createdAt, AssignedCourier courier) {}

    public record AssignedCourier(String name, String vehicle) {}

    public record Creation(Order order, boolean created) {}
}
