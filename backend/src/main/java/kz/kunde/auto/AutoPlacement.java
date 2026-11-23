package kz.kunde.auto;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of a roadside job: its own root, the city of the breakdown location. */
@Configuration(proxyBeanMethods = false)
class AutoPlacement {
    @Bean
    PlacementLocator autoJobPlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("auto.job", "auto", "select city_id from transactions.auto_jobs where id = ?", db);
    }
}
