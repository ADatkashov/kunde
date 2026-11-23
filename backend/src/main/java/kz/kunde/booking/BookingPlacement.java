package kz.kunde.booking;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of Booking aggregates: the venue is the root (city_id); a booking inherits it. */
@Configuration(proxyBeanMethods = false)
class BookingPlacement {
    @Bean
    PlacementLocator bookingVenuePlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("booking.venue", "booking",
                "select city_id from marketplace.booking_venues where id = ?", db);
    }

    @Bean
    PlacementLocator bookingRecordPlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("booking.booking", "booking", """
                select v.city_id from transactions.bookings b
                join marketplace.booking_venues v on v.id = b.venue_id where b.id = ?""", db);
    }
}
