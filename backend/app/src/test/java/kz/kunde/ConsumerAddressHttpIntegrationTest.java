package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = {
        "app.identity.consumer-enabled=true",
        "app.security.oidc.issuer-uri=https://identity.example.test",
        "app.security.oidc.audience=kunde-api"
})
@AutoConfigureMockMvc
class ConsumerAddressHttpIntegrationTest {
    @Autowired MockMvc http;
    @Autowired ConsumerIdentityService identity;
    @MockitoBean JwtDecoder issuerJwtDecoder;

    private Jwt jwt(String subject) {
        return Jwt.withTokenValue("fixture").header("alg", "RS256")
                .issuer("https://identity.example.test").subject(subject)
                .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(300))
                .audience(List.of("kunde-api")).claim("typ", "Bearer")
                .claim("azp", "kunde-consumer").claim("scope", "openid kunde.consumer").build();
    }

    private String auth() {
        String token = UUID.randomUUID().toString();
        when(issuerJwtDecoder.decode(token)).thenReturn(jwt(UUID.randomUUID().toString()));
        return token;
    }

    @Test
    void ownerCanCreateAndListButServiceabilityIsNotAssumed() throws Exception {
        String token = auth();
        http.perform(post("/api/v1/me/addresses").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"label":"Home","formattedAddress":"Synthetic address",
                         "latitude":43.238949,"longitude":76.889709}
                        """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.serviceable").value(false))
                .andExpect(jsonPath("$.version").value(0))
                .andExpect(header().string("Cache-Control", "no-store"));
        http.perform(get("/api/v1/me/addresses").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].label").value("Home"))
                .andExpect(jsonPath("$[0].serviceable").value(false));
    }

    @Test
    void rejectsInvalidCoordinatesAndAnonymousAccess() throws Exception {
        String token = auth();
        http.perform(post("/api/v1/me/addresses").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"label":"Home","formattedAddress":"Synthetic address",
                         "latitude":100,"longitude":76.889709}
                        """))
                .andExpect(status().isBadRequest());
        http.perform(get("/api/v1/me/addresses")).andExpect(status().isUnauthorized());
    }

    @Test
    void anotherUserCannotDeleteAnAddress() throws Exception {
        String owner = auth();
        String other = auth();
        String json = http.perform(post("/api/v1/me/addresses").header("Authorization", "Bearer " + owner)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"label":"Private","formattedAddress":"Synthetic address",
                         "latitude":43.238949,"longitude":76.889709}
                        """))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        String id = new com.fasterxml.jackson.databind.ObjectMapper().readTree(json).get("id").asText();
        http.perform(delete("/api/v1/me/addresses/" + id).header("Authorization", "Bearer " + other)
                .param("version", "0")).andExpect(status().isConflict());
        http.perform(get("/api/v1/me/addresses").header("Authorization", "Bearer " + owner))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].id").value(id));
        http.perform(delete("/api/v1/me/addresses/" + id).header("Authorization", "Bearer " + owner)
                .param("version", "0")).andExpect(status().isNoContent());
        http.perform(get("/api/v1/me/addresses").header("Authorization", "Bearer " + owner))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
    }
}
