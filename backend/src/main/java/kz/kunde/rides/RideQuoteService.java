package kz.kunde.rides;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.rides.RideMatching.RideClass;
import kz.kunde.rides.RideRoutingController.Coordinates;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class RideQuoteService {
    private final JdbcTemplate db;
    private final RidesFlags flags;
    private final RidePricingProperties pricing;
    private final ObjectProvider<RideRouting> routing;

    public RideQuoteService(JdbcTemplate db, RidesFlags flags, RidePricingProperties pricing,
            ObjectProvider<RideRouting> routing) {
        this.db = db;
        this.flags = flags;
        this.pricing = pricing;
        this.routing = routing;
    }

    public Quote issue(UUID customer, RideClass rideClass, Coordinates pickup, Coordinates destination) {
        if (!flags.consumerAvailable()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RIDES_UNAVAILABLE", "New rides are currently unavailable");
        }
        var tariff = pricing.tariffs().get(rideClass);
        if (tariff == null) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "RIDE_CLASS_UNAVAILABLE", "Ride class is unavailable");
        }
        var provider = routing.getIfAvailable();
        if (provider == null) {
            throw routingUnavailable();
        }
        RideRouting.Route route;
        try {
            route = provider.route(pickup.point(), destination.point()).orElseThrow(() ->
                    new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "RIDE_ROUTE_NOT_FOUND",
                            "No road route was found for these points"));
        } catch (RideRouting.Unavailable failure) {
            throw routingUnavailable();
        }

        var fare = tariff.estimateKzt(route.distanceMeters(), route.durationSeconds());
        if (fare.precision() > 14) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "RIDE_FARE_OUT_OF_RANGE", "Route cannot be quoted");
        }
        return db.queryForObject("""
                insert into transactions.ride_fare_quotes
                    (user_id, ride_class, tariff_version, estimate_kzt, distance_meters, duration_seconds,
                     pickup_latitude, pickup_longitude, destination_latitude, destination_longitude, expires_at)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, statement_timestamp() + (? * interval '1 second'))
                returning id, expires_at
                """, (rs, row) -> new Quote(rs.getObject("id", UUID.class), rideClass, tariff.version(), fare, "KZT",
                        route.distanceMeters(), route.durationSeconds(), rs.getObject("expires_at", OffsetDateTime.class)),
                customer, rideClass.name(), tariff.version(), fare, route.distanceMeters(), route.durationSeconds(),
                pickup.latitude(), pickup.longitude(), destination.latitude(), destination.longitude(),
                pricing.quoteLifetimeSeconds());
    }

    private static ApiException routingUnavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "RIDES_ROUTING_UNAVAILABLE",
                "Road routing is currently unavailable");
    }

    public record Quote(UUID id, RideClass rideClass, String tariffVersion, BigDecimal estimateKzt, String currency,
            int distanceMeters, int durationSeconds, OffsetDateTime expiresAt) {}
}
