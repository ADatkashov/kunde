package kz.kunde.rides;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-rides-only-for-integration-tests",
        "app.rides.enabled=true",
        "app.rides.consumer-enabled=true",
        "app.rides.pricing.tariffs.economy.version=test-v1",
        "app.rides.pricing.tariffs.economy.base-kzt=200",
        "app.rides.pricing.tariffs.economy.per-kilometer-kzt=80",
        "app.rides.pricing.tariffs.economy.per-minute-kzt=10",
        "app.rides.pricing.tariffs.economy.minimum-kzt=400",
        "app.rides.pricing.tariffs.economy.fixed-fee-kzt=0"
})
@AutoConfigureMockMvc
@Import(RideQuoteApiIntegrationTest.Fixture.class)
@Transactional
class RideQuoteApiIntegrationTest {
    private static final String QUOTE = """
            {"rideClass":"ECONOMY","pickup":{"latitude":43.24,"longitude":76.92},
             "destination":{"latitude":43.25,"longitude":76.94}}
            """;

    @Autowired MockMvc http;

    @Test
    void issuesServerPricedQuoteAndOnlyOwnerCanUseIt() throws Exception {
        var response = http.perform(post("/api/v1/rides/quotes").with(customer("quote-owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.estimateKzt").value(500))
                .andExpect(jsonPath("$.tariffVersion").value("test-v1"))
                .andReturn().getResponse().getContentAsString();
        String quoteId = JsonPath.read(response, "$.id");
        String requestKey = java.util.UUID.randomUUID().toString();
        var request = "{\"quoteId\":\"" + quoteId + "\"}";

        http.perform(post("/api/v1/rides").with(customer("another-customer"))
                        .header("Idempotency-Key", requestKey).contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isConflict());
        http.perform(post("/api/v1/rides").with(customer("quote-owner"))
                        .header("Idempotency-Key", requestKey).contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.estimateKzt").value(500));
    }

    @Test
    void rejectsUnconfiguredTariffAndUnknownRoute() throws Exception {
        http.perform(post("/api/v1/rides/quotes").with(customer("quote-owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE.replace("ECONOMY", "BUSINESS")))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("RIDE_CLASS_UNAVAILABLE"));
        http.perform(post("/api/v1/rides/quotes").with(customer("quote-owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE.replace("43.25", "42.25")))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("RIDE_ROUTE_NOT_FOUND"));
    }

    private static RequestPostProcessor customer(String subject) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer"));
    }

    @TestConfiguration
    static class Fixture {
        @Bean
        RideRouting testRouting() {
            return new FixtureRideRouting();
        }
    }
}
