package kz.kunde.delivery;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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
        "app.delivery.executor-enabled=true",
        "app.delivery.dispatch-enabled=true",
        "app.delivery.partner-enabled=true",
        "DELIVERY_HANDOFF_KEY=synthetic-handoff-fixture-only-000000000",
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

    @Test
    void approvedCourierCanCompleteOnlyAfterOneTimeHandoff() throws Exception {
        var courier = customer("delivery-courier");
        var owner = customer("delivery-owner");
        var admin = jwt().jwt(token -> token.issuer("https://identity.example.test").subject("delivery-reviewer")
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer kunde.admin"));
        UUID reviewer = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        db.update("insert into identity.external_bindings (issuer, subject, user_id) values (?, ?, ?)",
                "https://identity.example.test", "delivery-reviewer", reviewer);
        db.update("insert into profile.consumer_profiles (user_id) values (?)", reviewer);
        db.update("insert into identity.admin_grants (user_id, permission, reason) values (?, 'DELIVERY_OPERATIONS', 'test')",
                reviewer);

        String executor = "/api/v1/executor/deliveries";
        String registered = http.perform(post(executor + "/profile").with(courier)
                        .contentType(MediaType.APPLICATION_JSON).content("""
                                {"name":"Synthetic Courier","vehicle":"BICYCLE"}
                                """))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"))
                .andReturn().getResponse().getContentAsString();
        String courierId = JsonPath.read(registered, "$.userId");
        String review = "/api/v1/admin/deliveries/couriers/" + courierId + "/decision";
        String decision = """
                {"decision":"APPROVED","maxGrams":3000,"maxSideCm":40,"reason":"Synthetic onboarding"}
                """;
        http.perform(post(review).with(owner).contentType(MediaType.APPLICATION_JSON).content(decision))
                .andExpect(status().isForbidden());
        http.perform(post(review).with(admin).contentType(MediaType.APPLICATION_JSON).content(decision))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("APPROVED"));
        http.perform(put(executor + "/availability").with(courier).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"online\":true}")).andExpect(status().isOk());
        http.perform(put(executor + "/location").with(courier).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"latitude\":43.24,\"longitude\":76.92}")).andExpect(status().isNoContent());

        String quoteResponse = http.perform(post(PATH + "/quotes").with(owner).contentType(MediaType.APPLICATION_JSON)
                        .content(QUOTE)).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String quoteId = JsonPath.read(quoteResponse, "$.id");
        String created = http.perform(post(PATH).with(owner).header("Idempotency-Key", UUID.randomUUID().toString())
                        .contentType(MediaType.APPLICATION_JSON).content("""
                        {"quoteId":"%s","pickupAddress":"[TEST] Pickup","destinationAddress":"[TEST] Destination",
                         "recipientName":"Test Recipient","recipientPhone":"+77000000000",
                         "description":"Documents","allowedGoodsConfirmed":true}
                        """.formatted(quoteId))).andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(created, "$.id");
        http.perform(post(PATH + "/" + id + "/dispatch").with(owner))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SEARCHING_COURIER"));
        String offers = http.perform(get(executor + "/offers").with(courier))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].deliveryId").value(id))
                .andReturn().getResponse().getContentAsString();
        String offer = JsonPath.read(offers, "$[0].id");
        http.perform(post(executor + "/offers/" + offer + "/response").with(courier)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"accept\":true}"))
                .andExpect(status().isNoContent());

        String progress = executor + "/" + id + "/progress";
        for (String action : new String[] {"DEPART", "ARRIVE", "PICK_UP", "TRANSIT"}) {
            http.perform(post(progress).with(courier).contentType(MediaType.APPLICATION_JSON)
                            .content("{\"action\":\"%s\"}".formatted(action))).andExpect(status().isOk());
        }
        http.perform(post(progress).with(courier).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"action\":\"COMPLETE\"}")).andExpect(status().isConflict());
        String issued = http.perform(post(PATH + "/" + id + "/handoff-code").with(owner))
                .andExpect(status().isCreated()).andExpect(header().string("Cache-Control", "no-store"))
                .andReturn().getResponse().getContentAsString();
        String code = JsonPath.read(issued, "$.code");
        String handoff = executor + "/" + id + "/handoff";
        String body = "{\"code\":\"%s\"}".formatted(code);
        http.perform(post(handoff).with(owner).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isNotFound());
        http.perform(post(handoff).with(courier).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isNoContent());
        http.perform(post(handoff).with(courier).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnprocessableEntity());
        http.perform(post(progress).with(courier).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"action\":\"COMPLETE\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        http.perform(get(PATH + "/" + id).with(owner)).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("COMPLETED"));

        String support = "/api/v1/me/support/cases";
        String note = """
                {"category":"GENERAL","message":"Synthetic delivery issue","deliveryId":"%s"}
                """.formatted(id);
        String complaint = http.perform(post(support).with(owner)
                        .header("Idempotency-Key", UUID.randomUUID().toString())
                        .contentType(MediaType.APPLICATION_JSON).content(note))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.deliveryId").value(id))
                .andReturn().getResponse().getContentAsString();
        http.perform(post(support).with(courier).header("Idempotency-Key", UUID.randomUUID().toString())
                        .contentType(MediaType.APPLICATION_JSON).content(note))
                .andExpect(status().isNotFound());
        String complaints = "/api/v1/admin/deliveries/complaints";
        http.perform(get(complaints).with(owner)).andExpect(status().isForbidden());
        String complaintId = JsonPath.read(complaint, "$.id");
        http.perform(get(complaints).with(admin))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].id").value(complaintId));
        for (int replay = 0; replay < 2; replay++) {
            http.perform(post(complaints + "/" + complaintId + "/resolve").with(admin))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("RESOLVED"));
        }
        http.perform(get("/api/v1/admin/deliveries/" + id + "/audit").with(admin))
                .andExpect(status().isOk()).andExpect(jsonPath("$[7].status").value("DELIVERED"));
    }

    @Test
    void organizationCannotUseAnotherOrganizationsQuoteOrReadItsShipments() throws Exception {
        UUID owner = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        UUID coworker = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        UUID outsider = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        UUID first = organization(owner, "First synthetic partner");
        UUID second = organization(outsider, "Second synthetic partner");
        db.update("""
                insert into marketplace.partner_staff(partner_id, user_id, role, granted_by_user_id)
                values (?, ?, 'OPERATOR', ?), (?, ?, 'MANAGER', ?)
                """, first, coworker, owner, second, owner, outsider);
        String path = "/api/v1/partner/partners/" + first + "/deliveries";
        String otherPath = "/api/v1/partner/partners/" + second + "/deliveries";
        var quote = http.perform(post(path + "/quotes").with(partner(owner))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String quoteId = JsonPath.read(quote, "$.id");
        String create = """
                {"quoteId":"%s","pickupAddress":"[TEST] Warehouse","destinationAddress":"[TEST] Recipient",
                 "recipientName":"Test Recipient","recipientPhone":"+77000000000",
                 "description":"Documents","allowedGoodsConfirmed":true}
                """.formatted(quoteId);
        String key = UUID.randomUUID().toString();
        http.perform(post(otherPath).with(partner(owner)).header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(create)).andExpect(status().isConflict());
        var created = http.perform(post(path).with(partner(owner)).header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(create))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(created, "$.id");
        http.perform(get(path + "/" + id).with(partner(outsider))).andExpect(status().isNotFound());
        http.perform(get(otherPath + "/" + id).with(partner(owner))).andExpect(status().isNotFound());
        http.perform(get(path + "/" + id).with(partner(coworker))).andExpect(status().isOk());
        http.perform(get(path + "/totals").with(partner(owner))).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].quotedTotalKzt").value(1050));
        http.perform(post(path + "/" + id + "/cancel").with(partner(coworker)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED_BY_CUSTOMER"));
    }

    private UUID organization(UUID owner, String name) {
        UUID id = db.queryForObject("""
                insert into marketplace.partners(display_name, created_by_user_id, verification_status)
                values (?, ?, 'APPROVED') returning id
                """, UUID.class, name, owner);
        db.update("""
                insert into marketplace.partner_staff(partner_id, user_id, role, granted_by_user_id)
                values (?, ?, 'OWNER', ?)
                """, id, owner, owner);
        return id;
    }

    private static RequestPostProcessor partner(UUID user) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(user.toString())
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer kunde.partner"));
    }

    private static RequestPostProcessor customer(String subject) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer"));
    }
}
