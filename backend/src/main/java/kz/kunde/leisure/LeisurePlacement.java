package kz.kunde.leisure;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of Leisure aggregates: the venue is the root (city_id); orders inherit it. */
@Configuration(proxyBeanMethods = false)
class LeisurePlacement {
    @Bean
    PlacementLocator leisureVenuePlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("leisure.venue", "leisure",
                "select city_id from marketplace.leisure_venues where id = ?", db);
    }

    @Bean
    PlacementLocator leisureOrderPlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("leisure.order", "leisure", """
                select v.city_id from transactions.leisure_orders o
                join marketplace.leisure_venues v on v.id = o.venue_id where o.id = ?""", db);
    }
}
