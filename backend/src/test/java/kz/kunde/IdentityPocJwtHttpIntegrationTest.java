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
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/** Exercises the real Spring Security HTTP filter chain against a deterministic local OIDC/JWKS server. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.identity.consumer-enabled=true")
@org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate
@ActiveProfiles("identity-poc")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class IdentityPocJwtHttpIntegrationTest {
    private static final RSAKey KEY_1;
    private static final RSAKey WRONG_KEY;
    private static final String ISSUER;
    private static final HttpServer OIDC_SERVER;
    private static final AtomicReference<JWKSet> PUBLISHED_KEYS = new AtomicReference<>();
    private static final AtomicInteger JWKS_REQUESTS = new AtomicInteger();
    private static final ObjectMapper JSON = new ObjectMapper();

    static {
        try {
            KEY_1 = new RSAKeyGenerator(2048).keyID("poc-key-1").generate();
            WRONG_KEY = new RSAKeyGenerator(2048).keyID("poc-key-1").generate();
            PUBLISHED_KEYS.set(new JWKSet(KEY_1.toPublicJWK()));
            OIDC_SERVER = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            ISSUER = "http://localhost:" + OIDC_SERVER.getAddress().getPort();
            OIDC_SERVER.createContext("/.well-known/openid-configuration", exchange -> writeJson(exchange,
                    Map.of("issuer", ISSUER, "jwks_uri", ISSUER + "/jwks",
                            "authorization_endpoint", ISSUER + "/authorize", "token_endpoint", ISSUER + "/token")));
            OIDC_SERVER.createContext("/jwks", exchange -> {
                JWKS_REQUESTS.incrementAndGet();
                writeJson(exchange, PUBLISHED_KEYS.get().toJSONObject());
            });
            OIDC_SERVER.start();
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate http;

    @DynamicPropertySource
    static void oidcProperties(DynamicPropertyRegistry registry) {
        registry.add("app.security.oidc.issuer-uri", () -> ISSUER);
        registry.add("app.security.oidc.audience", () -> "kunde-api");
        registry.add("app.security.oidc.allow-insecure-http-issuer", () -> "true");
        registry.add("spring.datasource.url", () -> System.getenv().getOrDefault(
                "DB_URL", "jdbc:postgresql://localhost:5544/kunde_identity_poc"));
        registry.add("spring.datasource.username", () -> System.getenv().getOrDefault("DB_USERNAME", "kunde_poc"));
        registry.add("spring.datasource.password", () -> System.getenv().getOrDefault("DB_PASSWORD", ""));
    }

    @Test
    @Order(1)
    void validSignedAccessTokenIsAcceptedAndReturnsValidatedClaims() throws Exception {
        ResponseEntity<Map> response = call(signedToken(KEY_1, ISSUER, "kunde-api", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5)));

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).containsEntry("issuer", ISSUER).containsEntry("authenticated", true);
        assertThat(JWKS_REQUESTS.get()).isPositive();
    }

    @Test
    @Order(2)
    void missingBearerTokenIsRejected() {
        ResponseEntity<String> response = http.getForEntity(url(), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(401);
    }

    @Test
    @Order(3)
    void invalidSignatureAndWrongIssuerAreRejected() throws Exception {
        assertThat(call(signedToken(WRONG_KEY, ISSUER, "kunde-api", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5)))
                .getStatusCode().value()).isEqualTo(401);
        assertThat(call(signedToken(KEY_1, ISSUER + "/wrong", "kunde-api", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5)))
                .getStatusCode().value()).isEqualTo(401);
    }

    @Test
    @Order(4)
    void wrongAudienceExpiredAndNotYetValidTokensAreRejected() throws Exception {
        assertThat(call(signedToken(KEY_1, ISSUER, "kunde-consumer-poc", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5)))
                .getStatusCode().value()).isEqualTo(401);
        assertThat(call(signedToken(KEY_1, ISSUER, "kunde-api", "kunde.poc",
                Instant.now().minusSeconds(300), Instant.now().minusSeconds(120), Instant.now().minusSeconds(300)))
                .getStatusCode().value()).isEqualTo(401);
        assertThat(call(signedToken(KEY_1, ISSUER, "kunde-api", "kunde.poc",
                Instant.now().plusSeconds(120), Instant.now().plusSeconds(300), Instant.now().plusSeconds(120)))
                .getStatusCode().value()).isEqualTo(401);
    }

    @Test
    @Order(5)
    void idTokenAudienceIsNotAcceptedAsAnApiAccessTokenAndScopeIsEnforced() throws Exception {
        assertThat(call(signedToken(KEY_1, ISSUER, "kunde-consumer-poc", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5)))
                .getStatusCode().value()).isEqualTo(401);
        assertThat(call(signedToken(KEY_1, ISSUER, "kunde-api", "profile",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5)))
                .getStatusCode().value()).isEqualTo(403);
    }

    @Test
    @Order(6)
    void jwksAreCachedAndUnknownKeyIdTriggersRotationRefresh() throws Exception {
        String firstToken = signedToken(KEY_1, ISSUER, "kunde-api", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5));
        assertThat(call(firstToken).getStatusCode().value()).isEqualTo(200);
        int afterFirst = JWKS_REQUESTS.get();
        assertThat(call(firstToken).getStatusCode().value()).isEqualTo(200);
        assertThat(JWKS_REQUESTS.get()).isEqualTo(afterFirst);

        RSAKey rotatedKey = new RSAKeyGenerator(2048).keyID("poc-key-2").generate();
        PUBLISHED_KEYS.set(new JWKSet(java.util.List.of(KEY_1.toPublicJWK(), rotatedKey.toPublicJWK())));
        String rotatedToken = signedToken(rotatedKey, ISSUER, "kunde-api", "kunde.poc",
                Instant.now().minusSeconds(5), Instant.now().plusSeconds(120), Instant.now().minusSeconds(5));
        assertThat(call(rotatedToken).getStatusCode().value()).isEqualTo(200);
        assertThat(JWKS_REQUESTS.get()).isGreaterThan(afterFirst);
    }

    @Test
    @Order(7)
    void malformedAndSymmetricAlgorithmConfusionTokensAreRejected() throws Exception {
        assertThat(call("not-a-jwt").getStatusCode().value()).isEqualTo(401);
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .issuer(ISSUER).subject("synthetic-algorithm-test").audience("kunde-api")
                .issueTime(Date.from(Instant.now().minusSeconds(5)))
                .expirationTime(Date.from(Instant.now().plusSeconds(120)))
                .claim("scope", "kunde.poc").build();
        SignedJWT token = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.HS256)
                .keyID("poc-key-1").build(), claims);
        token.sign(new com.nimbusds.jose.crypto.MACSigner(new byte[32]));
        assertThat(call(token.serialize()).getStatusCode().value()).isEqualTo(401);
    }

    @Test
    @Order(8)
    void missingExpirySubjectAndFutureIssuedAtAreRejected() throws Exception {
        for (String invalid : java.util.List.of("exp", "sub", "iat", "numeric-sub")) {
            var claims = new JWTClaimsSet.Builder().issuer(ISSUER).audience("kunde-api")
                    .claim("scope", "kunde.poc");
            if (!invalid.equals("sub")) claims.subject("synthetic-required-claims");
            if (!invalid.equals("exp")) claims.expirationTime(Date.from(Instant.now().plusSeconds(600)));
            claims.issueTime(Date.from(Instant.now().plusSeconds(invalid.equals("iat") ? 300 : -5)));
            var raw = claims.build().toJSONObject();
            if (invalid.equals("numeric-sub")) raw.put("sub", 42);
            var token = new com.nimbusds.jose.JWSObject(
                    new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(KEY_1.getKeyID()).build(),
                    new com.nimbusds.jose.Payload(JSON.writeValueAsString(raw)));
            token.sign(new RSASSASigner(KEY_1.toPrivateKey()));
            assertThat(call(token.serialize()).getStatusCode().value()).isEqualTo(401);
        }
    }

    @Test
    @Order(9)
    void signedConsumerTokensPassTheProductionChainAndInvalidAuthorizationIsForbidden() throws Exception {
        for (String invalid : java.util.List.of("valid", "azp", "scope", "typ")) {
            var claims = new JWTClaimsSet.Builder().issuer(ISSUER).audience("kunde-api")
                    .subject("signed-consumer-" + java.util.UUID.randomUUID())
                    .issueTime(Date.from(Instant.now().minusSeconds(5)))
                    .expirationTime(Date.from(Instant.now().plusSeconds(300)))
                    .claim("azp", invalid.equals("azp") ? "other-client" : "kunde-consumer")
                    .claim("typ", invalid.equals("typ") ? "ID" : "Bearer")
                    .claim("scope", invalid.equals("scope") ? "openid" : "openid kunde.consumer").build();
            var token = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(KEY_1.getKeyID()).build(), claims);
            token.sign(new RSASSASigner(KEY_1.toPrivateKey()));
            var headers = new HttpHeaders();
            headers.setBearerAuth(token.serialize());
            var response = http.exchange("http://localhost:" + port + "/api/v1/me", HttpMethod.GET,
                    new HttpEntity<>(headers), Map.class);
            assertThat(response.getStatusCode().value()).isEqualTo(invalid.equals("valid") ? 200 : 403);
            if (invalid.equals("valid")) assertThat(response.getBody()).containsKeys("id", "version");
            else assertThat(response.getBody()).containsEntry("code", "FORBIDDEN");
        }
    }

    private ResponseEntity<Map> call(String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        return http.exchange(url(), HttpMethod.GET, new HttpEntity<>(headers), Map.class);
    }

    private String url() {
        return "http://localhost:" + port + "/api/v1/poc/whoami";
    }

    private static String signedToken(RSAKey key, String issuer, String audience, String scope,
            Instant issuedAt, Instant expiresAt, Instant notBefore) throws Exception {
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .issuer(issuer)
                .subject("synthetic-identity-poc")
                .audience(audience)
                .issueTime(Date.from(issuedAt))
                .expirationTime(Date.from(expiresAt))
                .notBeforeTime(Date.from(notBefore))
                .claim("scope", scope)
                .build();
        SignedJWT jwt = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).keyID(key.getKeyID()).build(), claims);
        jwt.sign(new RSASSASigner(key.toPrivateKey()));
        return jwt.serialize();
    }

    private static void writeJson(com.sun.net.httpserver.HttpExchange exchange, Object body) throws IOException {
        byte[] bytes = JSON.writeValueAsString(body).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(200, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        }
    }
}
