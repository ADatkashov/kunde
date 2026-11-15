package kz.kunde.partner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jwt.SignedJWT;
import java.util.UUID;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.partner.PartnerVerification.Decision;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * ADR-018 step 3: partner offerings over HTTP (CRUD, publish only for APPROVED partners, IDOR, roles, audit).
 * Synthetic numbers only; the whole test rolls back, so no partner, category or offering rows remain.
 */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000101,+77000000102,+77000000103,+77000000104,+77000000105,"
                + "+77000000106,+77000000107,+77000000108,+77000000109,+77000000110,+77000000111,"
                + "+77000000112,+77000000113,+77000000114,+77000000115,+77000000116",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class PartnerOfferingApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PartnerService service;

    @BeforeEach
    void clean() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000114', '+77000000115', '+77000000116')");
    }

    private ResultActions send(String method, String path, String token, String json) throws Exception {
        var request = (method.equals("PATCH") ? patch(path) : post(path)).contentType(MediaType.APPLICATION_JSON).content(json);
        return http.perform(token == null ? request : request.header("Authorization", "Bearer " + token));
    }

    private ResultActions fetch(String path, String token) throws Exception {
        return http.perform(get(path).header("Authorization", "Bearer " + token));
    }

    private String login(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}").andExpect(status().isAccepted());
        return send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private String refreshed(String loginBody) throws Exception {
        return JsonPath.read(send("POST", "/api/v1/auth/token/refresh", null,
                "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(), "$.accessToken");
    }

    private static UUID user(String loginBody) throws Exception {
        return UUID.fromString(SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    private UUID category(String status) {
        return db.queryForObject("""
                INSERT INTO marketplace.categories (code, name_ru, name_kk, status, published_at)
                VALUES ('off-' || substr(gen_random_uuid()::text, 1, 8), 'К', 'К', ?, CASE WHEN ? = 'PUBLISHED' THEN now() END)
                RETURNING id""", UUID.class, status, status);
    }

    /** Applies as the user and returns the partner id; the token must be refreshed afterwards to carry kunde.partner. */
    private UUID apply(String loginBody, String name) throws Exception {
        String token = JsonPath.read(loginBody, "$.accessToken");
        return UUID.fromString(JsonPath.read(send("POST", "/api/v1/partner/applications", token, "{\"displayName\":\"" + name + "\"}")
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id"));
    }

    private static String offeringJson(UUID category, Object price) {
        return "{\"categoryId\":\"" + category + "\",\"kind\":\"SERVICE\",\"nameRu\":\"  Уборка \",\"nameKk\":\"Тазалау\","
                + "\"priceMinor\":" + price + ",\"availability\":\"AVAILABLE\"}";
    }

    private String createOffering(String token, UUID partner, UUID category, Object price) throws Exception {
        return send("POST", "/api/v1/partner/partners/" + partner + "/offerings", token, offeringJson(category, price))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
    }

    @Test
    void publishNeedsAnApprovedPartnerAndAPriceAndWithdrawalHidesTheOffering() throws Exception {
        String loginA = login("+77000000114");
        String loginB = login("+77000000115");
        UUID partner = apply(loginA, "Offer Cafe");
        String token = refreshed(loginA);
        UUID category = category("PUBLISHED");

        String created = createOffering(token, partner, category, 250050);
        UUID id = UUID.fromString(JsonPath.read(created, "$.id"));
        assertThat((String) JsonPath.read(created, "$.status")).isEqualTo("DRAFT");
        assertThat((String) JsonPath.read(created, "$.nameRu")).isEqualTo("Уборка");
        assertThat((String) JsonPath.read(created, "$.currency")).isEqualTo("KZT");
        assertThat(db.queryForObject("SELECT partner_id FROM marketplace.offerings WHERE id = ?", UUID.class, id)).isEqualTo(partner);

        String base = "/api/v1/partner/partners/" + partner + "/offerings/" + id;
        // Partner is still PENDING_REVIEW: publishing is refused and the public catalog shows nothing.
        send("POST", base + "/publish", token, "{\"version\":0}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PARTNER_NOT_APPROVED"));
        http.perform(get("/api/v1/offerings/" + id)).andExpect(status().isNotFound());

        // A KUNDE reviewer (not staff of the partner) approves; now publishing works and consumers see price and partner.
        service.reviewVerification(user(loginB), partner, Decision.APPROVE, null, 0);
        send("POST", base + "/publish", token, "{\"version\":1}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        send("POST", base + "/publish", token, "{\"version\":0}").andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PUBLISHED")).andExpect(jsonPath("$.version").value(1));
        http.perform(get("/api/v1/offerings/" + id)).andExpect(status().isOk())
                .andExpect(jsonPath("$.priceMinor").value(250050)).andExpect(jsonPath("$.currency").value("KZT"))
                .andExpect(jsonPath("$.available").value(true)).andExpect(jsonPath("$.partnerId").value(partner.toString()));

        // A published offering keeps its price; withdrawal hides it again.
        send("PATCH", base, token, "{\"nameRu\":\"Уборка\",\"nameKk\":\"Тазалау\",\"availability\":\"AVAILABLE\",\"version\":1}")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("PRICE_REQUIRED"));
        send("POST", base + "/unpublish", token, "{\"version\":1}").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("DRAFT"));
        http.perform(get("/api/v1/offerings/" + id)).andExpect(status().isNotFound());
        assertThat(db.queryForList("SELECT event_type FROM marketplace.offering_events WHERE offering_id = ? ORDER BY id", String.class, id))
                .containsExactly("CREATED", "PUBLISHED", "UNPUBLISHED");
    }

    @Test
    void draftWithoutPriceCannotBePublishedEvenForAnApprovedPartner() throws Exception {
        String loginA = login("+77000000114");
        String loginB = login("+77000000115");
        UUID partner = apply(loginA, "No Price Cafe");
        String token = refreshed(loginA);
        service.reviewVerification(user(loginB), partner, Decision.APPROVE, null, 0);
        String created = createOffering(token, partner, category("PUBLISHED"), "null");
        assertThat((Object) JsonPath.read(created, "$.priceMinor")).isNull();
        assertThat((String) JsonPath.read(created, "$.availability")).isEqualTo("AVAILABLE");
        send("POST", "/api/v1/partner/partners/" + partner + "/offerings/" + JsonPath.read(created, "$.id") + "/publish", token, "{\"version\":0}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("PRICE_REQUIRED"));
    }

    @Test
    void anotherPartnersOfferingsCannotBeReadChangedOrPublished() throws Exception {
        String loginA = login("+77000000114");
        String loginB = login("+77000000115");
        UUID partnerA = apply(loginA, "Partner A");
        UUID partnerB = apply(loginB, "Partner B");
        String tokenA = refreshed(loginA);
        String tokenB = refreshed(loginB);
        UUID category = category("PUBLISHED");
        UUID offeringA = UUID.fromString(JsonPath.read(createOffering(tokenA, partnerA, category, 1000), "$.id"));
        createOffering(tokenB, partnerB, category, 2000);

        // B under A's partner path: same 404 as an unknown partner. B under its own path with A's offering id: 404 too.
        String underA = "/api/v1/partner/partners/" + partnerA + "/offerings";
        String underB = "/api/v1/partner/partners/" + partnerB + "/offerings";
        fetch(underA, tokenB).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("PARTNER_NOT_FOUND"));
        fetch(underA + "/" + offeringA, tokenB).andExpect(status().isNotFound());
        send("PATCH", underA + "/" + offeringA, tokenB, "{\"nameRu\":\"X\",\"nameKk\":\"X\",\"version\":0}").andExpect(status().isNotFound());
        send("POST", underA, tokenB, offeringJson(category, 1)).andExpect(status().isNotFound());
        fetch(underB + "/" + offeringA, tokenB).andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("OFFERING_NOT_FOUND"));
        send("PATCH", underB + "/" + offeringA, tokenB, "{\"nameRu\":\"X\",\"nameKk\":\"X\",\"version\":0}")
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("OFFERING_NOT_FOUND"));
        send("POST", underB + "/" + offeringA + "/publish", tokenB, "{\"version\":0}").andExpect(status().isNotFound());
        send("POST", underB + "/" + offeringA + "/unpublish", tokenB, "{\"version\":0}").andExpect(status().isNotFound());

        fetch(underB, tokenB).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1));
        assertThat(db.queryForObject("SELECT name_ru || version FROM marketplace.offerings WHERE id = ?", String.class, offeringA)).isEqualTo("Уборка0");
    }

    @Test
    void operatorsReadButCannotWriteAndInputIsValidated() throws Exception {
        String loginA = login("+77000000114");
        String loginC = login("+77000000116");
        UUID partner = apply(loginA, "Role Cafe");
        service.grantStaff(user(loginA), partner, user(loginC), Role.OPERATOR);
        String tokenA = refreshed(loginA);
        String tokenC = refreshed(loginC);
        UUID category = category("DRAFT");
        UUID id = UUID.fromString(JsonPath.read(createOffering(tokenA, partner, category, 500), "$.id"));
        String base = "/api/v1/partner/partners/" + partner + "/offerings";

        fetch(base, tokenC).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1));
        fetch(base + "/" + id, tokenC).andExpect(status().isOk());
        send("POST", base, tokenC, offeringJson(category, 1)).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("PARTNER_ROLE_FORBIDDEN"));
        send("PATCH", base + "/" + id, tokenC, "{\"nameRu\":\"X\",\"nameKk\":\"X\",\"version\":0}").andExpect(status().isForbidden());
        send("POST", base + "/" + id + "/publish", tokenC, "{\"version\":0}").andExpect(status().isForbidden());

        String ok = "\"nameRu\":\"A\",\"nameKk\":\"B\"";
        send("POST", base, tokenA, "{\"categoryId\":\"" + category + "\",\"kind\":\"VOUCHER\"," + ok + "}").andExpect(status().isBadRequest());
        send("POST", base, tokenA, "{\"categoryId\":\"" + UUID.randomUUID() + "\",\"kind\":\"SERVICE\"," + ok + "}")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_CATEGORY"));
        send("POST", base, tokenA, "{\"categoryId\":\"" + category + "\",\"kind\":\"SERVICE\",\"nameRu\":\" \",\"nameKk\":\"B\"}").andExpect(status().isBadRequest());
        send("POST", base, tokenA, offeringJson(category, -1)).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_PRICE"));
        send("POST", base, tokenA, offeringJson(category, PartnerOfferingService.MAX_PRICE_MINOR + 1)).andExpect(status().isBadRequest());
        send("POST", base, tokenA, "{\"categoryId\":\"" + category + "\",\"kind\":\"SERVICE\"," + ok + ",\"availability\":\"MAYBE\"}")
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_AVAILABILITY"));
        send("PATCH", base + "/" + id, tokenA, "{\"nameRu\":\"Новое\",\"nameKk\":\"Жаңа\",\"priceMinor\":700,\"version\":0}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1)).andExpect(jsonPath("$.priceMinor").value(700));
        send("PATCH", base + "/" + id, tokenA, "{\"nameRu\":\"Старое\",\"nameKk\":\"Ескі\",\"version\":0}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("VERSION_CONFLICT"));
        // Category and kind are fixed at creation; the offering stays a draft inside an unpublished category (ADR-014).
        assertThat(db.queryForObject("SELECT category_id FROM marketplace.offerings WHERE id = ?", UUID.class, id)).isEqualTo(category);
        http.perform(get("/api/v1/offerings/" + id)).andExpect(status().isNotFound());
    }

    @Test
    void offeringsPerPartnerAreCapped() throws Exception {
        String loginA = login("+77000000114");
        UUID partner = apply(loginA, "Big Cafe");
        String token = refreshed(loginA);
        UUID category = category("DRAFT");
        db.update("""
                INSERT INTO marketplace.offerings (category_id, kind, name_ru, name_kk, partner_id)
                SELECT ?, 'SERVICE', 'n' || g, 'n' || g, ? FROM generate_series(1, ?) g""", category, partner,
                PartnerOfferingService.MAX_OFFERINGS_PER_PARTNER);
        send("POST", "/api/v1/partner/partners/" + partner + "/offerings", token, offeringJson(category, 1))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("OFFERING_LIMIT"));
    }

    @Test
    void categoryOptionsListDraftAndPublishedButNotRetiredCategories() throws Exception {
        String loginA = login("+77000000114");
        apply(loginA, "Category Cafe");
        String token = refreshed(loginA);
        UUID draft = category("DRAFT");
        UUID published = category("PUBLISHED");
        UUID retired = category("RETIRED");
        String body = fetch("/api/v1/partner/categories", token).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertThat((java.util.List<String>) JsonPath.read(body, "$[*].id")).contains(draft.toString(), published.toString())
                .doesNotContain(retired.toString());
        fetch("/api/v1/partner/categories", JsonPath.read(loginA, "$.accessToken")).andExpect(status().isForbidden());
    }

    @Test
    void anonymousAndConsumerOnlyTokensAreRejected() throws Exception {
        String loginA = login("+77000000114");
        UUID partner = apply(loginA, "Auth Cafe");
        String stale = JsonPath.read(loginA, "$.accessToken");
        http.perform(get("/api/v1/partner/partners/" + partner + "/offerings")).andExpect(status().isUnauthorized());
        // Issued before the application: no kunde.partner scope yet.
        fetch("/api/v1/partner/partners/" + partner + "/offerings", stale).andExpect(status().isForbidden());
    }
}
