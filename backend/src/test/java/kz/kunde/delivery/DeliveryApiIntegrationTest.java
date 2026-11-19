package kz.kunde.delivery;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-delivery-only-for-integration-tests",
        "app.delivery.enabled=true",
        "app.delivery.consumer-enabled=true",
        "app.delivery.synthetic-routing-enabled=true",
        "app.delivery.base-kzt=400",
        "app.delivery.per-km-kzt=200",
        "app.delivery.per-kg-kzt=100"
})
@AutoConfigureMockMvc
@Transactional
class DeliveryApiIntegrationTest {
    private static final String PATH = "/api/v1/deliveries";
    private static final String QUOTE = """
            {"parcelType":"DOCUMENTS","weightGrams":500,"lengthCm":30,"widthCm":20,"heightCm":2,
             "pickup":{"latitude":43.24,"longitude":76.92},"destination":{"latitude":43.25,"longitude":76.94}}
            """;

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @Test
    void ownerCanUseQuoteOnceAndReplayOrCancelWithoutDuplicatingDelivery() throws Exception {
        var quoted = http.perform(post(PATH + "/quotes").with(customer("owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.amountKzt").value(1050))
                .andExpect(jsonPath("$.syntheticRoute").value(true))
                .andReturn().getResponse().getContentAsString();
        String quote = JsonPath.read(quoted, "$.id");
        String request = """
                {"quoteId":"%s","pickupAddress":"[TEST] From","destinationAddress":"[TEST] To",
                 "recipientName":"Synthetic Recipient","recipientPhone":"+77000000000",
                 "description":"Documents","allowedGoodsConfirmed":true}
                """.formatted(quote);
        String key = UUID.randomUUID().toString();
        http.perform(post(PATH).with(customer("other")).header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isConflict());
        var created = http.perform(post(PATH).with(customer("owner")).header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("CREATED"))
                .andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(created, "$.id");
        http.perform(post(PATH).with(customer("owner")).header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id));
        http.perform(post(PATH).with(customer("owner")).header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(request.replace("Documents", "Books")))
                .andExpect(status().isConflict());
        http.perform(get(PATH + "/" + id).with(customer("other"))).andExpect(status().isNotFound());

        for (int retry = 0; retry < 2; retry++) {
            http.perform(post(PATH + "/" + id + "/cancel").with(customer("owner")))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED_BY_CUSTOMER"));
        }
        http.perform(get(PATH).with(customer("owner")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1));
        assertThat(db.queryForList("select status from transactions.delivery_events where delivery_id = ? order by id",
                String.class, UUID.fromString(id))).containsExactly("CREATED", "CANCELLED_BY_CUSTOMER");
    }

    @Test
    void rejectsOversizeAndUnknownSyntheticRoute() throws Exception {
        http.perform(post(PATH + "/quotes").with(customer("owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE.replace("500", "5100")))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("DELIVERY_LIMIT_EXCEEDED"));
        http.perform(post(PATH + "/quotes").with(customer("owner"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE.replace("43.25", "42.25")))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("DELIVERY_ROUTE_NOT_FOUND"));
    }

    private static RequestPostProcessor customer(String subject) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer"));
    }
}
