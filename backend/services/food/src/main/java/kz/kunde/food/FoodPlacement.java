package kz.kunde.food;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of Food aggregates: the restaurant is the root (city_id); an order inherits it. */
@Configuration(proxyBeanMethods = false)
class FoodPlacement {
    @Bean
    PlacementLocator foodRestaurantPlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("food.restaurant", "food",
                "select city_id from marketplace.food_restaurants where id = ?", db);
    }

    @Bean
    PlacementLocator foodOrderPlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("food.order", "food", """
                select r.city_id from transactions.food_orders o
                join marketplace.food_restaurants r on r.id = o.restaurant_id where o.id = ?""", db);
    }
}
