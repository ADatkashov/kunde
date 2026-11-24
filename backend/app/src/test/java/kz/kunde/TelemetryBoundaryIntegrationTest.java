package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import kz.kunde.platform.ApiExceptionHandler;

/**
 * TASK-047 verification of the implemented telemetry boundary: correlation identifiers on every
 * response class, structured error logs without request secrets, and minimal Actuator exposure.
 * Synthetic values only. Alert owners, SLOs, dashboards and exporters are NOT covered here.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class TelemetryBoundaryIntegrationTest {
    private static final Pattern UUID_PATTERN =
            Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    @Autowired MockMvc mockMvc;
    @Autowired ApiExceptionHandler exceptionHandler;
    @Autowired ObjectMapper objectMapper;

    @Test
    void everyResponseClassCarriesAGeneratedCorrelationIdAndErrorBodiesMatchIt() throws Exception {
        List<MvcResult> results = List.of(
                mockMvc.perform(get("/api/v1/health")).andReturn(),
                mockMvc.perform(get("/api/v1/search").param("q", "x".repeat(201))).andReturn(),
                mockMvc.perform(post("/api/v1/protected-test")).andReturn(),
                mockMvc.perform(get("/api/v1/no-such-route")).andReturn(),
                mockMvc.perform(options("/api/v1/capabilities")
                        .header("Origin", "https://untrusted.example.test")
                        .header("Access-Control-Request-Method", "GET")).andReturn());

        for (MvcResult result : results) {
            String header = result.getResponse().getHeader("X-Correlation-ID");
            assertThat(header).as("correlation header for status %d", result.getResponse().getStatus())
                    .matches(UUID_PATTERN);
            String body = result.getResponse().getContentAsString();
            if (body.startsWith("{") && body.contains("\"correlationId\"")) {
                assertThat(objectMapper.readTree(body).get("correlationId").asText()).isEqualTo(header);
            }
        }
        assertThat(results.stream().map(r -> r.getResponse().getHeader("X-Correlation-ID")).distinct().count())
                .as("each request gets its own identifier").isEqualTo(results.size());
    }

    @Test
    void safeCallerIdIsEchoedAndUnsafeOrOversizedIdsAreReplaced() throws Exception {
        assertThat(mockMvc.perform(get("/api/v1/health").header("X-Correlation-ID", "ep047-check_1.2"))
                .andReturn().getResponse().getHeader("X-Correlation-ID")).isEqualTo("ep047-check_1.2");

        for (String unsafe : List.of("has space", "a".repeat(65), "semi;colon", "<script>", "")) {
            String returned = mockMvc.perform(get("/api/v1/health").header("X-Correlation-ID", unsafe))
                    .andReturn().getResponse().getHeader("X-Correlation-ID");
            assertThat(returned).as("replacement for [%s]", unsafe).matches(UUID_PATTERN);
        }
    }

    @Test
    void actuatorExposesOnlyHealthWithoutDatabaseOrComponentDetail() throws Exception {
        MvcResult health = mockMvc.perform(get("/actuator/health")).andReturn();
        assertThat(health.getResponse().getStatus()).isEqualTo(200);
        JsonNode body = objectMapper.readTree(health.getResponse().getContentAsString());
        assertThat(body.fieldNames()).toIterable().isSubsetOf("status", "groups");
        assertThat(body.get("groups")).extracting(JsonNode::asText).containsExactlyInAnyOrder("liveness", "readiness");
        for (String probe : List.of("liveness", "readiness")) {
            JsonNode probeBody = objectMapper.readTree(mockMvc.perform(get("/actuator/health/" + probe))
                    .andReturn().getResponse().getContentAsString());
            assertThat(probeBody.fieldNames()).toIterable().as("%s probe fields", probe).containsExactly("status");
        }

        for (String endpoint : List.of("env", "metrics", "prometheus", "info", "beans", "loggers",
                "heapdump", "configprops", "mappings", "threaddump", "httpexchanges")) {
            int status = mockMvc.perform(get("/actuator/" + endpoint)).andReturn().getResponse().getStatus();
            assertThat(status).as("/actuator/%s must not be served", endpoint).isNotEqualTo(200);
        }
    }

    @Test
    void unhandledFailureIsLoggedAsStructuredJsonWithoutMessageStackOrRequestSecrets(CapturedOutput output)
            throws Exception {
        String secret = "synthetic-bearer-secret-sentinel";
        MDC.put("correlationId", "ep047-log-check");
        try {
            exceptionHandler.handleUnexpected(
                    new IllegalStateException("Authorization: Bearer " + secret), new MockHttpServletRequest());
        } finally {
            MDC.remove("correlationId");
        }

        List<String> lines = output.getAll().lines().filter(line -> line.contains("ep047-log-check")).toList();
        assertThat(lines).as("the failure produced a structured log line").hasSize(1);
        JsonNode event = objectMapper.readTree(lines.get(0));
        assertThat(event.get("level").asText()).isEqualTo("ERROR");
        assertThat(event.get("correlationId").asText()).isEqualTo("ep047-log-check");
        assertThat(event.get("message").asText()).contains("IllegalStateException");
        assertThat(event.has("stack_trace")).isFalse();
        assertThat(output.getAll()).doesNotContain(secret);
    }
}
