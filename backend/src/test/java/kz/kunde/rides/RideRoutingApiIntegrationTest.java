package kz.kunde.rides;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-rides-only-for-integration-tests",
        "app.rides.enabled=true",
        "app.rides.consumer-enabled=true"
})
@AutoConfigureMockMvc
class RideRoutingApiIntegrationTest {
    private static final String PREVIEW = "/api/v1/rides/route-preview";
    private static final String ROUTE = """
            {"pickup":{"latitude":43.24,"longitude":76.92},"destination":{"latitude":43.25,"longitude":76.94}}
            """;

    @Autowired
    MockMvc http;

    @Test
    void rejectsAnonymousAndWrongClient() throws Exception {
        http.perform(post(PREVIEW).contentType(MediaType.APPLICATION_JSON).content(ROUTE))
                .andExpect(status().isUnauthorized());
        http.perform(post(PREVIEW).with(client("other-client")).contentType(MediaType.APPLICATION_JSON).content(ROUTE))
                .andExpect(status().isForbidden());
    }

    @Test
    void validatesCoordinatesAndReportsUnconfiguredProvider() throws Exception {
        http.perform(post(PREVIEW).with(client("kunde-consumer")).contentType(MediaType.APPLICATION_JSON)
                        .content(ROUTE.replace("43.24", "91")))
                .andExpect(status().isBadRequest());
        http.perform(post(PREVIEW).with(client("kunde-consumer")).contentType(MediaType.APPLICATION_JSON).content(ROUTE))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("RIDES_ROUTING_UNAVAILABLE"));
        http.perform(post("/api/v1/rides/address-search").with(client("kunde-consumer"))
                        .contentType(MediaType.APPLICATION_JSON).content("""
                                {"query":"Алматы","language":"ru"}
                                """))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("RIDES_ROUTING_UNAVAILABLE"));
    }

    private static RequestPostProcessor client(String clientId) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject("synthetic-rider")
                .claim("typ", "Bearer").claim("azp", clientId).claim("scope", "kunde.consumer"));
    }
}
