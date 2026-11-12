package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class ApiRateLimitFilterTest {
    private final AtomicLong time = new AtomicLong();
    private final SimpleMeterRegistry metrics = new SimpleMeterRegistry();
    private final ApiSecurityErrorWriter errors = new ApiSecurityErrorWriter(new ObjectMapper().findAndRegisterModules());

    private ApiRateLimitFilter limiter(int requests, int clients) {
        return new ApiRateLimitFilter(errors, metrics, requests, 10, clients, time::get);
    }

    private MockHttpServletResponse call(ApiRateLimitFilter filter, String ip, String path) throws Exception {
        var request = new MockHttpServletRequest("GET", path);
        request.setRemoteAddr(ip);
        request.addHeader("X-Forwarded-For", "spoof-" + java.util.UUID.randomUUID());
        request.addHeader("Forwarded", "for=another-client");
        request.addHeader(RequestCorrelationFilter.HEADER, "test-correlation");
        var response = new MockHttpServletResponse();
        new RequestCorrelationFilter().doFilter(request, response,
                (req, res) -> filter.doFilter(req, res, (allowed, result) -> {
                    ((jakarta.servlet.http.HttpServletResponse) result).setStatus(204);
                }));
        return response;
    }

    @Test
    void enforcesLimitAndReturnsSafeCorrelatedErrorDespiteSpoofedHeaders() throws Exception {
        var filter = limiter(2, 10);
        assertThat(call(filter, "one", "/api/v1/search").getStatus()).isEqualTo(204);
        assertThat(call(filter, "one", "/api/v1/categories").getStatus()).isEqualTo(204);
        var denied = call(filter, "one", "/api/v1/me");
        assertThat(denied.getStatus()).isEqualTo(429);
        assertThat(denied.getHeader("Retry-After")).isEqualTo("10");
        assertThat(denied.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(denied.getHeader(RequestCorrelationFilter.HEADER)).isEqualTo("test-correlation");
        var body = new ObjectMapper().readTree(denied.getContentAsString());
        assertThat(body.get("code").asText()).isEqualTo("RATE_LIMITED");
        assertThat(body.get("correlationId").asText()).isEqualTo("test-correlation");
        assertThat(metrics.get("kunde.api.rate_limit.denied").counter().count()).isEqualTo(1);
        assertThat(call(filter, "two", "/api/v1/me").getStatus()).isEqualTo(204);
    }

    @Test
    void roundsRetryUpAndReopensAtWindowBoundary() throws Exception {
        var filter = limiter(1, 10);
        call(filter, "one", "/api/v1/me");
        time.set(TimeUnit.MILLISECONDS.toNanos(8500));
        assertThat(call(filter, "one", "/api/v1/me").getHeader("Retry-After")).isEqualTo("2");
        time.set(TimeUnit.SECONDS.toNanos(10));
        assertThat(call(filter, "one", "/api/v1/me").getStatus()).isEqualTo(204);
    }

    @Test
    void boundedTableRejectsUnknownClientsWithoutEvictingActiveQuota() throws Exception {
        var filter = limiter(1, 1);
        call(filter, "one", "/api/v1/me");
        assertThat(call(filter, "two", "/api/v1/me").getStatus()).isEqualTo(429);
        assertThat(call(filter, "one", "/api/v1/me").getStatus()).isEqualTo(429);
        time.set(TimeUnit.SECONDS.toNanos(10));
        assertThat(call(filter, "two", "/api/v1/me").getStatus()).isEqualTo(204);
    }

    @Test
    void probesRemainAvailableWithoutConsumingClientQuota() throws Exception {
        var filter = limiter(1, 1);
        for (String path : new String[]{"/api/v1/health", "/actuator/health/liveness"}) {
            assertThat(call(filter, "one", path).getStatus()).isEqualTo(204);
            assertThat(call(filter, "one", path).getStatus()).isEqualTo(204);
        }
        assertThat(call(filter, "one", "/api/v1").getStatus()).isEqualTo(204);
        assertThat(call(filter, "one", "/api/v1/me").getStatus()).isEqualTo(429);
    }

    @Test
    void simultaneousRequestsCannotOverspendQuota() throws Exception {
        var filter = limiter(3, 10);
        var start = new CountDownLatch(1);
        try (var pool = Executors.newFixedThreadPool(8)) {
            var futures = new ArrayList<Future<Integer>>();
            for (int i = 0; i < 20; i++) futures.add(pool.submit(() -> {
                if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Start timeout");
                return call(filter, "one", "/api/v1/me").getStatus();
            }));
            start.countDown();
            int allowed = 0;
            for (var future : futures) {
                int status = future.get(10, TimeUnit.SECONDS);
                assertThat(status).isIn(204, 429);
                if (status == 204) allowed++;
            }
            assertThat(allowed).isEqualTo(3);
        }
    }

    @Test
    void invalidConfigurationFailsStartup() {
        assertThatThrownBy(() -> limiter(0, 1)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> limiter(1, 0)).isInstanceOf(IllegalArgumentException.class);
    }
}
