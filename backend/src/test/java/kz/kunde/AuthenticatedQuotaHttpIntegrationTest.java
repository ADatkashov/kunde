package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.gen.RSAKeyGenerator;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.time.Instant;
import java.util.Date;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/** Local signed-JWT/JWKS fixture; this is not live IdP or native Consumer E2E evidence. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "app.security.oidc.audience=kunde-api",
        "app.security.oidc.allow-insecure-http-issuer=true",
        "app.security.authenticated-rate-limit.requests=2",
        "app.security.authenticated-rate-limit.window-seconds=60",
        "app.security.authenticated-rate-limit.max-identities=32",
        "app.cors.allowed-origins=https://consumer.example.test"
})
@org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate
@ActiveProfiles("identity-poc")
class AuthenticatedQuotaHttpIntegrationTest {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final RSAKey KEY;
    private static final RSAKey WRONG_KEY;
    private static final HttpServer OIDC;
    private static final String ISSUER;

    static {
        try {
            KEY = new RSAKeyGenerator(2048).keyID("quota-fixture").generate();
            WRONG_KEY = new RSAKeyGenerator(2048).keyID("quota-fixture").generate();
            OIDC = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            ISSUER = "http://localhost:" + OIDC.getAddress().getPort();
            OIDC.createContext("/.well-known/openid-configuration", exchange -> {
                byte[] bytes = JSON.writeValueAsBytes(Map.of("issuer", ISSUER, "jwks_uri", ISSUER + "/jwks",
                        "authorization_endpoint", ISSUER + "/authorize", "token_endpoint", ISSUER + "/token"));
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, bytes.length);
                try (var output = exchange.getResponseBody()) { output.write(bytes); }
            });
            OIDC.createContext("/jwks", exchange -> {
                byte[] bytes = JSON.writeValueAsBytes(new JWKSet(KEY.toPublicJWK()).toJSONObject());
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, bytes.length);
                try (var output = exchange.getResponseBody()) { output.write(bytes); }
            });
            OIDC.start();
        } catch (Exception error) {
            throw new ExceptionInInitializerError(error);
        }
    }

    @LocalServerPort int port;
    @Autowired TestRestTemplate http;

    @DynamicPropertySource
    static void issuer(DynamicPropertyRegistry properties) {
        properties.add("app.security.oidc.issuer-uri", () -> ISSUER);
    }

    @AfterAll
    static void stopFixture() { OIDC.stop(0); }

    private String token(String subject, RSAKey key) throws Exception {
        Instant now = Instant.now();
        var claims = new JWTClaimsSet.Builder().issuer(ISSUER).subject(subject).audience("kunde-api")
                .issueTime(Date.from(now)).expirationTime(Date.from(now.plusSeconds(300)))
                .jwtID(UUID.randomUUID().toString()).claim("scope", "kunde.poc kunde.consumer").build();
        var signed = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(key.getKeyID()).build(), claims);
        signed.sign(new RSASSASigner(key));
        return signed.serialize();
    }

    private ResponseEntity<String> call(String path, String token) {
        var headers = new HttpHeaders();
        if (token != null) headers.setBearerAuth(token);
        headers.set("Origin", "https://consumer.example.test");
        headers.set("X-Correlation-ID", "identity-quota-http-check");
        headers.set("X-User-ID", UUID.randomUUID().toString());
        headers.set("X-Device-ID", UUID.randomUUID().toString());
        return http.exchange(java.net.URI.create("http://localhost:" + port + path),
                HttpMethod.GET, new HttpEntity<>(headers), String.class);
    }

    @Test
    void rotatedSignedTokensShareQuotaAndOtherIdentitiesRemainIndependent() throws Exception {
        String subject = UUID.randomUUID().toString();
        String first = token(subject, KEY);
        String rotated = token(subject, KEY);
        // On failure report only a boolean, never serialized bearer values.
        assertThat(first.equals(rotated)).isFalse();
        assertThat(call("/api/v1/categories", first).getStatusCode().value()).isEqualTo(200);
        assertThat(call("/api/v1/categories", rotated).getStatusCode().value()).isEqualTo(200);
        var denied = call("/%61pi/v1/categories", token(subject, KEY));
        assertThat(denied.getStatusCode().value()).isEqualTo(429);
        assertThat(JSON.readTree(denied.getBody()).get("code").asText()).isEqualTo("RATE_LIMITED");
        assertThat(denied.getHeaders().getFirst("Retry-After")).isNotBlank();
        assertThat(denied.getHeaders().getFirst("Cache-Control")).isEqualTo("no-store");
        assertThat(denied.getHeaders().getFirst("Access-Control-Allow-Origin")).isEqualTo("https://consumer.example.test");
        assertThat(denied.getHeaders().getFirst("X-Correlation-ID")).isEqualTo("identity-quota-http-check");
        assertThat(call("/api/v1/categories", token(UUID.randomUUID().toString(), KEY)).getStatusCode().value()).isEqualTo(200);
        assertThat(call("/api/v1/health", rotated).getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void invalidSignaturesAndAnonymousCallsCannotConsumeAVictimsQuota() throws Exception {
        String subject = UUID.randomUUID().toString();
        for (int i = 0; i < 3; i++) {
            assertThat(call("/api/v1/categories", token(subject, WRONG_KEY)).getStatusCode().value()).isEqualTo(401);
            assertThat(call("/api/v1/categories", null).getStatusCode().value()).isEqualTo(200);
        }
        String valid = token(subject, KEY);
        assertThat(call("/api/v1/categories", valid).getStatusCode().value()).isEqualTo(200);
        assertThat(call("/api/v1/categories", valid).getStatusCode().value()).isEqualTo(200);
        assertThat(call("/api/v1/categories", valid).getStatusCode().value()).isEqualTo(429);
    }

    @Test
    void authenticatedBudgetIsSharedAcrossProductionAndPocSecurityChains() throws Exception {
        String valid = token(UUID.randomUUID().toString(), KEY);
        assertThat(call("/api/v1/categories", valid).getStatusCode().value()).isEqualTo(200);
        // POC chain does not enable CORS; use a request without Origin for this isolated route.
        var headers = new HttpHeaders();
        headers.setBearerAuth(valid);
        assertThat(http.exchange("http://localhost:" + port + "/api/v1/poc/whoami", HttpMethod.GET,
                new HttpEntity<>(headers), String.class).getStatusCode().value()).isEqualTo(200);
        assertThat(call("/api/v1/categories", valid).getStatusCode().value()).isEqualTo(429);
    }
}
