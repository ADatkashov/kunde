package kz.kunde.rides;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of a ride: a ride is its own root and keeps the city of its pickup point for life. */
@Configuration(proxyBeanMethods = false)
class RidesPlacement {
    @Bean
    PlacementLocator ridePlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("rides.ride", "rides", "select city_id from transactions.rides where id = ?", db);
    }
}
