package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Arrays;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationContext;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Product profile isolation (ADR-027, scripts/dev/product_profile.py dev-home-services): with only Home Services and its Booking
 * prerequisite switched on, no other product starts a scheduler, a demo seeder or an API surface. The flags below are the
 * profile's, minus the demo seeders (they would write to the shared test database). Does not touch the data.
 */
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.home-services.enabled=true",
        "app.food.enabled=false",
        "app.delivery.enabled=false",
        "app.rides.enabled=false",
        "app.education.enabled=false",
        "app.auto.enabled=false",
        "app.beauty.enabled=false",
        "app.flowers.enabled=false",
        "app.maps.enabled=false"
})
@AutoConfigureMockMvc
class ProductProfileIsolationIntegrationTest {
    @Autowired MockMvc http;
    @Autowired ApplicationContext context;

    @Test
    void onlyHomeServicesAndItsPrerequisitesAreAdvertised() throws Exception {
        http.perform(get("/api/v1/capabilities")).andExpect(status().isOk())
                .andExpect(jsonPath("$.homeServicesEnabled").value(true))
                .andExpect(jsonPath("$.bookingEnabled").value(true))
                .andExpect(jsonPath("$.deliveryEnabled").value(false))
                .andExpect(jsonPath("$.ridesEnabled").value(false))
                .andExpect(jsonPath("$.marketplaceEnabled").value(false))
                .andExpect(jsonPath("$.mapsEnabled").value(false));
    }

    @Test
    void disabledProductsStartNoBackgroundJobsAndNoDemoSeeders() {
        String[] beans = context.getBeanDefinitionNames();
        assertThat(Arrays.stream(beans).filter(n -> n.equalsIgnoreCase("deliveryMaintenance")))
                .as("Delivery scheduler must not exist while DELIVERY_ENABLED=false").isEmpty();
        assertThat(Arrays.stream(beans).filter(n -> n.toLowerCase().endsWith("demoseeder")))
                .as("no demo seeder may run in a profile that switches the seeders off").isEmpty();
        assertThat(Arrays.stream(beans).filter(n -> n.equalsIgnoreCase("outboxRelayJob")))
                .as("the outbox relay stays off (ADR-022) in every profile").isEmpty();
    }
}
