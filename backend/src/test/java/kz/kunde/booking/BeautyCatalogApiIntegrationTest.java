package kz.kunde.booking;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

/** Beauty category taxonomy over HTTP against PostgreSQL: localized, ordered, paginated, featured filter. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.beauty.enabled=true",
        "app.security.rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class BeautyCatalogApiIntegrationTest {
    @Autowired MockMvc http;

    @Test
    void homeGridHasEightFeaturedCategoriesInOrderWithAllThreeLanguages() throws Exception {
        http.perform(get("/api/v1/beauty/categories?featured=true"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(8))
                .andExpect(jsonPath("$[0].code").value("SALONS"))
                .andExpect(jsonPath("$[0].nameRu").value("Салоны"))
                .andExpect(jsonPath("$[0].nameKk").value("Салондар"))
                .andExpect(jsonPath("$[0].nameEn").value("Salons"))
                .andExpect(jsonPath("$[7].code").value("BROWS_LASHES"));
    }

    @Test
    void moreCategoriesArePaginatedAndExcludeFeaturedWhenAskedFor() throws Exception {
        http.perform(get("/api/v1/beauty/categories?featured=false"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(4))
                .andExpect(jsonPath("$[0].code").value("MAKEUP"));
        http.perform(get("/api/v1/beauty/categories?limit=2&offset=1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].code").value("BARBERSHOPS"));
        http.perform(get("/api/v1/beauty/categories?limit=0")).andExpect(status().isBadRequest());
    }

    @Test
    void capabilityReportsBeautyEnabled() throws Exception {
        http.perform(get("/api/v1/capabilities")).andExpect(jsonPath("$.beautyEnabled").value(true));
    }
}
