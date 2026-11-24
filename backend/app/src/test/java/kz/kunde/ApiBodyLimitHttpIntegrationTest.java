package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayInputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "app.security.oidc.issuer-uri=",
        "app.security.max-body-bytes=64",
        "app.cors.allowed-origins=https://consumer.example.test"
})
@Import(ApiBodyLimitHttpIntegrationTest.BodyEcho.class)
class ApiBodyLimitHttpIntegrationTest {
    @LocalServerPort int port;
    @Autowired ObjectMapper json;

    private HttpResponse<String> send(String path, int size, boolean chunked) throws Exception {
        byte[] body = new byte[size];
        java.util.Arrays.fill(body, (byte) 'x');
        return send(path, body, chunked, "GET");
    }

    private HttpResponse<String> send(String path, byte[] body, boolean chunked, String method) throws Exception {
        var publisher = chunked
                ? HttpRequest.BodyPublishers.ofInputStream(() -> new ByteArrayInputStream(body))
                : HttpRequest.BodyPublishers.ofByteArray(body);
        var request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
                .timeout(Duration.ofSeconds(10))
                .header("Content-Type", "application/json")
                .header("Origin", "https://consumer.example.test")
                .header("X-Correlation-ID", "body-limit-http-check")
                .method(method, publisher).build();
        try (var client = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(5)).build()) {
            return client.send(request, HttpResponse.BodyHandlers.ofString());
        }
    }

    @Test
    void boundedJsonReachesTheActualMessageConverterUnchanged() throws Exception {
        byte[] body = "{\"name\":\"Күнде\"}".getBytes(StandardCharsets.UTF_8);
        for (boolean chunked : new boolean[]{false, true}) {
            var result = send("/api/v1/categories", body, chunked, "POST");
            assertThat(result.statusCode()).isEqualTo(200);
            assertThat(json.readTree(result.body()).get("name").asText()).isEqualTo("Күнде");
        }
        assertThat(send("/api/v1/me", body, false, "GET").statusCode()).isEqualTo(503);
    }

    @TestConfiguration(proxyBeanMethods = false)
    @RestController
    static class BodyEcho {
        @PostMapping("/api/v1/categories")
        Echo echo(@RequestBody Echo body) { return body; }
    }

    record Echo(String name) {}

    @Test
    void boundaryBodiesRemainAcceptedWithAndWithoutContentLength() throws Exception {
        assertThat(send("/api/v1/categories", 64, false).statusCode()).isEqualTo(200);
        assertThat(send("/api/v1/categories", 64, true).statusCode()).isEqualTo(200);
    }

    @Test
    void oversizedKnownAndChunkedBodiesFailBeforeRoutingWithSafeCorsError() throws Exception {
        for (boolean chunked : new boolean[]{false, true}) {
            var denied = send("/%61pi/v1/categories", 65, chunked);
            assertThat(denied.statusCode()).isEqualTo(413);
            assertThat(denied.headers().firstValue("Cache-Control")).contains("no-store");
            assertThat(denied.headers().firstValue("Access-Control-Allow-Origin"))
                    .contains("https://consumer.example.test");
            assertThat(denied.headers().firstValue("X-Correlation-ID")).contains("body-limit-http-check");
            var error = json.readTree(denied.body());
            assertThat(error.get("code").asText()).isEqualTo("PAYLOAD_TOO_LARGE");
            assertThat(error.get("correlationId").asText()).isEqualTo("body-limit-http-check");
        }
        assertThat(send("/api/v1/health", 0, false).statusCode()).isEqualTo(200);
    }
}
