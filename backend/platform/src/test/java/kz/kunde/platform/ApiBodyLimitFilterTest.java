package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import jakarta.servlet.ServletInputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class ApiBodyLimitFilterTest {
    private final SimpleMeterRegistry metrics = new SimpleMeterRegistry();
    private final ApiSecurityErrorWriter errors = new ApiSecurityErrorWriter(new ObjectMapper().findAndRegisterModules());
    private final ApiBodyLimitFilter filter = new ApiBodyLimitFilter(errors, metrics, 8);

    private MockHttpServletRequest request(byte[] body, long length) {
        var request = new MockHttpServletRequest("PATCH", "/api/v1/me") {
            @Override public long getContentLengthLong() { return length; }
        };
        request.setServletPath("/api/v1/me");
        request.setContent(body);
        request.setCharacterEncoding(StandardCharsets.UTF_8.name());
        return request;
    }

    @Test
    void excessiveDeclaredLengthIsRejectedWithoutOpeningInputOrCallingDownstream() throws Exception {
        var request = new MockHttpServletRequest("PATCH", "/api/v1/me") {
            @Override public long getContentLengthLong() { return Long.MAX_VALUE; }
            @Override public ServletInputStream getInputStream() { throw new AssertionError("Body must not be read"); }
        };
        request.setServletPath("/api/v1/me");
        var response = new MockHttpServletResponse();
        filter.doFilter(request, response, (req, res) -> { throw new AssertionError("Downstream must not run"); });
        assertThat(response.getStatus()).isEqualTo(413);
        assertThat(response.getContentAsString()).contains("PAYLOAD_TOO_LARGE");
        assertThat(metrics.get("kunde.api.body_limit.denied").counter().count()).isEqualTo(1);
    }

    @Test
    void absentOrUnderstatedLengthCannotBypassActualByteLimit() throws Exception {
        for (long length : new long[]{-1, 0, 1, 8}) {
            var response = new MockHttpServletResponse();
            filter.doFilter(request(new byte[9], length), response,
                    (req, res) -> { throw new AssertionError("Oversized body reached downstream"); });
            assertThat(response.getStatus()).isEqualTo(413);
        }
    }

    @Test
    void unboundedStreamReadsOnlyLimitPlusOneBytes() throws Exception {
        var consumed = new AtomicInteger();
        var stream = new ServletInputStream() {
            @Override public int read() {
                if (consumed.incrementAndGet() > 9) throw new AssertionError("Unbounded read");
                return 'x';
            }
            @Override public boolean isFinished() { return false; }
            @Override public boolean isReady() { return true; }
            @Override public void setReadListener(jakarta.servlet.ReadListener listener) { throw new UnsupportedOperationException(); }
        };
        var request = new MockHttpServletRequest("PATCH", "/api/v1/me") {
            @Override public long getContentLengthLong() { return -1; }
            @Override public ServletInputStream getInputStream() { return stream; }
        };
        request.setServletPath("/api/v1/me");
        var response = new MockHttpServletResponse();
        filter.doFilter(request, response, (req, res) -> { throw new AssertionError("Downstream must not run"); });
        assertThat(response.getStatus()).isEqualTo(413);
        assertThat(consumed.get()).isEqualTo(9);
    }

    @Test
    void boundaryAndEmptyBodiesPreserveBytesForDownstream() throws Exception {
        for (byte[] body : new byte[][]{new byte[0], "12345678".getBytes(StandardCharsets.UTF_8)}) {
            var reached = new AtomicBoolean();
            filter.doFilter(request(body, -1), new MockHttpServletResponse(), (req, res) -> {
                reached.set(true);
                assertThat(req.getInputStream().readAllBytes()).containsExactly(body);
                assertThat(req.getInputStream().read()).isEqualTo(-1);
                assertThatThrownBy(req::getReader).isInstanceOf(IllegalStateException.class);
            });
            assertThat(reached.get()).isTrue();
        }
    }

    @Test
    void utf8ReaderPreservesTextAndLimitCountsBytesRatherThanCharacters() throws Exception {
        byte[] boundary = "қазақ".substring(0, 4).getBytes(StandardCharsets.UTF_8);
        assertThat(boundary).hasSize(8);
        filter.doFilter(request(boundary, 8), new MockHttpServletResponse(), (req, res) -> {
            assertThat(req.getReader().readLine()).isEqualTo("қазақ".substring(0, 4));
            assertThatThrownBy(req::getInputStream).isInstanceOf(IllegalStateException.class);
        });
        var response = new MockHttpServletResponse();
        filter.doFilter(request("қазақ".getBytes(StandardCharsets.UTF_8), -1), response,
                (req, res) -> { throw new AssertionError("UTF-8 body exceeds byte limit"); });
        assertThat(response.getStatus()).isEqualTo(413);
    }

    @Test
    void nonApiRequestsAreNotConsumed() throws Exception {
        var request = request(new byte[9], 9);
        request.setServletPath("/actuator/health");
        filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> assertThat(req).isSameAs(request));
    }

    @Test
    void invalidLimitsCannotDisableProtection() {
        for (int invalid : new int[]{0, -1, 1048577, Integer.MAX_VALUE}) {
            assertThatThrownBy(() -> new ApiBodyLimitFilter(errors, metrics, invalid))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }
}
