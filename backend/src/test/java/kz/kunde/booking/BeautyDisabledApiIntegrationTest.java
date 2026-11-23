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

/** With BEAUTY_ENABLED unset (the default) the Beauty API is hidden and the capability is false. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.booking.enabled=true",
        "app.security.rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class BeautyDisabledApiIntegrationTest {
    @Autowired MockMvc http;

    @Test
    void categoriesAreNotFoundAndCapabilityIsFalseByDefault() throws Exception {
        http.perform(get("/api/v1/beauty/categories"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("BEAUTY_DISABLED"));
        http.perform(get("/api/v1/capabilities")).andExpect(jsonPath("$.beautyEnabled").value(false));
    }
}
