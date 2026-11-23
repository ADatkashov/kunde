package kz.kunde.delivery;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.geo.Coordinates;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeliveryTracking {
    private static final String TRACKABLE = """
            ('COURIER_ASSIGNED','COURIER_ARRIVING','COURIER_ARRIVED','PICKED_UP','IN_TRANSIT','RETURNING')
            """;
    private final JdbcTemplate db;

    public DeliveryTracking(JdbcTemplate db) {
        this.db = db;
    }

    @Transactional
    public void publish(UUID courier, UUID delivery, Coordinates point) {
        var locked = db.query("""
                select id from transactions.deliveries
                where id = ? and courier_id = ? and status in %s for update
                """.formatted(TRACKABLE), (rs, row) -> rs.getObject(1, UUID.class), delivery, courier);
        if (locked.isEmpty()) {
            throw notFound();
        }
        db.update("""
                insert into transactions.delivery_locations(delivery_id, latitude, longitude)
                values (?, ?, ?)
                on conflict (delivery_id) do update set latitude = excluded.latitude, longitude = excluded.longitude,
                    observed_at = excluded.observed_at
                where transactions.delivery_locations.observed_at <= statement_timestamp() - interval '5 seconds'
                """, delivery, point.latitude(), point.longitude());
    }

    @Transactional
    public void stop(UUID courier, UUID delivery) {
        var locked = db.query("""
                select id from transactions.deliveries where id = ? and courier_id = ? for update
                """, (rs, row) -> rs.getObject(1, UUID.class), delivery, courier);
        if (locked.isEmpty()) {
            throw notFound();
        }
        db.update("delete from transactions.delivery_locations where delivery_id = ?", delivery);
    }

    public Optional<Location> current(UUID owner, UUID delivery) {
        return db.query("""
                select l.latitude, l.longitude, l.observed_at
                from transactions.deliveries d
                left join transactions.delivery_locations l on l.delivery_id = d.id
                  and d.status in %s and l.observed_at > statement_timestamp() - interval '2 minutes'
                where d.id = ? and d.user_id = ? and d.partner_id is null
                """.formatted(TRACKABLE), (rs, row) -> {
                    var at = rs.getObject("observed_at", OffsetDateTime.class);
                    return at == null ? Optional.<Location>empty()
                            : Optional.of(new Location(rs.getBigDecimal("latitude"), rs.getBigDecimal("longitude"), at));
                }, delivery, owner).stream().findFirst().orElseThrow(DeliveryTracking::notFound);
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "DELIVERY_LOCATION_NOT_FOUND", "Delivery location was not found");
    }

    public record Location(BigDecimal latitude, BigDecimal longitude, OffsetDateTime observedAt) {}
}
