package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;

/** TASK-037 / SUP-001: consumer support cases. Synthetic identities only. */
@SpringBootTest(properties = {
        "app.identity.consumer-enabled=true",
        "app.security.oidc.issuer-uri=https://identity.example.test",
        "app.security.oidc.audience=kunde-api"
})
@AutoConfigureMockMvc
class SupportCaseHttpIntegrationTest {
    private static final String BASE = "/api/v1/me/support/cases";
    private static final String BODY = "{\"category\":\"GENERAL\",\"message\":\"Synthetic question\"}";

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired ObjectMapper json;
    @MockitoBean JwtDecoder issuerJwtDecoder;

    private String auth() {
        String token = UUID.randomUUID().toString();
        Jwt jwt = Jwt.withTokenValue("fixture").header("alg", "RS256")
                .issuer("https://identity.example.test").subject(UUID.randomUUID().toString())
                .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(300))
                .audience(List.of("kunde-api")).claim("typ", "Bearer")
                .claim("azp", "kunde-consumer").claim("scope", "openid kunde.consumer").build();
        when(issuerJwtDecoder.decode(token)).thenReturn(jwt);
        return "Bearer " + token;
    }

    private static String key() {
        return UUID.randomUUID().toString();
    }

    private ResultActions open(String auth, String key, String body) throws Exception {
        var request = post(BASE).header("Authorization", auth).contentType(MediaType.APPLICATION_JSON).content(body);
        return http.perform(key == null ? request : request.header("Idempotency-Key", key));
    }

    private String openAndGetId(String auth) throws Exception {
        MvcResult result = open(auth, key(), BODY).andExpect(status().isCreated()).andReturn();
        JsonNode node = json.readTree(result.getResponse().getContentAsString());
        return node.get("id").asText();
    }

    @Test
    void ownerOpensCaseWithoutTransactionLinkAndSeesItInList() throws Exception {
        String auth = auth();
        open(auth, key(), BODY).andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("OPEN"))
                .andExpect(jsonPath("$.category").value("GENERAL"))
                .andExpect(jsonPath("$.message").value("Synthetic question"))
                .andExpect(header().string("Cache-Control", "no-store"));
        http.perform(get(BASE).header("Authorization", auth)).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1));
    }

    @Test
    void sameKeyAndPayloadReplaysWithoutDuplicateOtherPayloadConflicts() throws Exception {
        String auth = auth();
        String key = key();
        open(auth, key, BODY).andExpect(status().isCreated());
        open(auth, key, BODY).andExpect(status().isOk());
        open(auth, key, "{\"category\":\"GENERAL\",\"message\":\"Different\"}")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REUSED"));
        http.perform(get(BASE).header("Authorization", auth)).andExpect(jsonPath("$.length()").value(1));
        assertThat(db.queryForObject("""
                select count(*) from support.case_events e join support.cases c on c.id = e.case_id
                where c.idempotency_key = ?""", Integer.class, key)).isEqualTo(1);
    }

    @Test
    void otherUsersCaseIsNotFoundAndCannotBeEscalated() throws Exception {
        String owner = auth();
        String stranger = auth();
        String id = openAndGetId(owner);
        http.perform(get(BASE + "/" + id).header("Authorization", stranger))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("CASE_NOT_FOUND"));
        http.perform(post(BASE + "/" + id + "/escalation").header("Authorization", stranger))
                .andExpect(status().isNotFound());
        http.perform(get(BASE).header("Authorization", stranger)).andExpect(jsonPath("$.length()").value(0));
        http.perform(get(BASE + "/" + id).header("Authorization", owner))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("OPEN"));
    }

    @Test
    void escalationIsRecordedOnceAndRepeatsAreHarmless() throws Exception {
        String auth = auth();
        String id = openAndGetId(auth);
        for (int i = 0; i < 2; i++) {
            http.perform(post(BASE + "/" + id + "/escalation").header("Authorization", auth))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ESCALATION_REQUESTED"));
        }
        assertThat(db.queryForObject("""
                select count(*) from support.case_events where case_id = ?::uuid and event_type = 'ESCALATION_REQUESTED'
                """, Integer.class, id)).isEqualTo(1);
    }

    @Test
    void rejectsBadInputAndAnonymousAccess() throws Exception {
        String auth = auth();
        open(auth, null, BODY).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_IDEMPOTENCY_KEY"));
        open(auth, "short", BODY).andExpect(status().isBadRequest());
        open(auth, key(), "{\"category\":\"GENERAL\",\"message\":\"   \"}").andExpect(status().isBadRequest());
        open(auth, key(), "{\"category\":\"GENERAL\",\"message\":\"" + "x".repeat(2001) + "\"}")
                .andExpect(status().isBadRequest());
        open(auth, key(), "{\"category\":\"ORDER\",\"message\":\"x\"}").andExpect(status().isBadRequest());
        http.perform(get(BASE).header("Authorization", auth).param("limit", "101")).andExpect(status().isBadRequest());
        http.perform(get(BASE)).andExpect(status().isUnauthorized());
        http.perform(post(BASE).contentType(MediaType.APPLICATION_JSON).content(BODY)
                .header("Idempotency-Key", key())).andExpect(status().isUnauthorized());
    }

    @Test
    void activeCaseLimitStopsFloodingWithoutAffectingOtherUsers() throws Exception {
        String auth = auth();
        for (int i = 0; i < 10; i++) {
            open(auth, key(), BODY).andExpect(status().isCreated());
        }
        open(auth, key(), BODY).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("CASE_LIMIT_REACHED"));
        open(auth(), key(), BODY).andExpect(status().isCreated());
    }
}
