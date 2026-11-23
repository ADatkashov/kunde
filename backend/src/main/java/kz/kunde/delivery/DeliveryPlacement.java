package kz.kunde.delivery;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of a delivery: its own root, the city of its pickup point. */
@Configuration(proxyBeanMethods = false)
class DeliveryPlacement {
    @Bean
    PlacementLocator deliveryRecordPlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("delivery.delivery", "delivery",
                "select city_id from transactions.deliveries where id = ?", db);
    }
}
