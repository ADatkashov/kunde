package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "app.security.oidc.issuer-uri=",
        "app.cors.allowed-origins=https://consumer.example.test",
        "app.security.rate-limit.requests=2",
        "app.security.rate-limit.window-seconds=60",
        "app.security.rate-limit.max-clients=2"
})
@org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate
class ApiRateLimitHttpIntegrationTest {
    @Autowired TestRestTemplate http;
    @Autowired ObjectMapper json;
    @LocalServerPort int port;

    @Test
    void realHttpEnforcesRateBeforeSecurityAndPreservesHealthAndErrorContract() throws Exception {
        String base = "http://localhost:" + port;
        assertThat(http.getForEntity(base + "/api/v1/categories", String.class).getStatusCode().value()).isEqualTo(200);
        assertThat(http.getForEntity(base + "/api/v1/me", String.class).getStatusCode().value()).isEqualTo(503);
        var headers = new HttpHeaders();
        headers.set("X-Forwarded-For", "192.0.2.123");
        headers.set("Forwarded", "for=192.0.2.124");
        headers.set("X-Correlation-ID", "rate-limit-http-check");
        headers.set("Origin", "https://consumer.example.test");
        var denied = http.exchange(base + "/api/v1/categories", HttpMethod.GET,
                new HttpEntity<>(headers), String.class);
        assertThat(denied.getStatusCode().value()).isEqualTo(429);
        assertThat(Long.parseLong(denied.getHeaders().getFirst("Retry-After"))).isBetween(1L, 60L);
        assertThat(denied.getHeaders().getFirst("Cache-Control")).isEqualTo("no-store");
        assertThat(denied.getHeaders().getFirst("X-Content-Type-Options")).isEqualTo("nosniff");
        assertThat(denied.getHeaders().getFirst("X-Correlation-ID")).isEqualTo("rate-limit-http-check");
        assertThat(denied.getHeaders().getFirst("Set-Cookie")).isNull();
        assertThat(denied.getHeaders().getFirst("Access-Control-Allow-Origin")).isEqualTo("https://consumer.example.test");
        assertThat(denied.getHeaders().getFirst("Access-Control-Expose-Headers")).contains("Retry-After");
        var body = json.readTree(denied.getBody());
        assertThat(body.get("code").asText()).isEqualTo("RATE_LIMITED");
        assertThat(body.get("timestamp").isTextual()).isTrue();
        assertThat(body.get("correlationId").asText()).isEqualTo("rate-limit-http-check");
        assertThat(http.getForEntity(java.net.URI.create(base + "/%61pi/v1/categories"), String.class)
                .getStatusCode().value()).isEqualTo(429);
        assertThat(http.getForEntity(base + "/api/v1/health", String.class).getStatusCode().value()).isEqualTo(200);
        assertThat(http.getForEntity(base + "/actuator/health/liveness", String.class).getStatusCode().value()).isEqualTo(200);
    }
}
