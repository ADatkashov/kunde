package kz.kunde.flowers;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

/** With FLOWERS_ENABLED unset (the default) the Flowers API is hidden and the capability is false. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.security.rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FlowersDisabledApiIntegrationTest {
    @Autowired MockMvc http;

    @Test
    void everyEndpointIsNotFoundAndCapabilityIsFalseByDefault() throws Exception {
        for (String path : new String[] {"/categories", "/shops", "/shops/00000000-0000-0000-0000-000000000000", "/products/popular"}) {
            http.perform(get("/api/v1/flowers" + path)).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("FLOWERS_DISABLED"));
        }
        http.perform(get("/api/v1/capabilities")).andExpect(jsonPath("$.flowersEnabled").value(false));
    }
}
