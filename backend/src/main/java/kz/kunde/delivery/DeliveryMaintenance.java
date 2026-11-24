package kz.kunde.delivery;

import kz.kunde.platform.FeatureToggles;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;

@Configuration
@EnableScheduling
@ConditionalOnProperty(name = "app.delivery.enabled", havingValue = "true")
class DeliveryMaintenance {
    private static final Logger LOG = LoggerFactory.getLogger(DeliveryMaintenance.class);
    private final JdbcTemplate db;
    private final DeliveryDispatch dispatch;
    private final FeatureToggles toggles;

    DeliveryMaintenance(JdbcTemplate db, DeliveryDispatch dispatch, FeatureToggles toggles) {
        this.db = db;
        this.dispatch = dispatch;
        this.toggles = toggles;
    }

    @Scheduled(fixedDelay = 5000)
    void updateSearches() {
        if (!DeliveryProperties.live(toggles).dispatchAvailable()) {
            return;
        }
        var pending = db.query("""
                select user_id, partner_id, id from transactions.deliveries
                where status = 'SEARCHING_COURIER' order by search_started_at, id limit 100
                """, (rs, row) -> new Search(rs.getObject(1, UUID.class), rs.getObject(2, UUID.class),
                        rs.getObject(3, UUID.class)));
        for (var search : pending) {
            try {
                dispatch.search(search.sender(), search.partner(), search.delivery());
            } catch (ApiException failure) {
                LOG.debug("Delivery dispatch skipped with code {}", failure.code());
            }
        }
    }

    @Scheduled(fixedDelay = 60000)
    void expireLocations() {
        db.update("delete from transactions.delivery_locations where observed_at < statement_timestamp() - interval '2 minutes'");
        db.update("""
                update transactions.delivery_couriers set latitude = null, longitude = null, observed_at = null
                where observed_at < statement_timestamp() - interval '2 minutes'
                """);
    }

    private record Search(UUID sender, UUID partner, UUID delivery) {}
}
