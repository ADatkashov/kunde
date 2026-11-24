package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class AuthenticatedRateLimitFilterTest {
    private final AtomicLong time = new AtomicLong();
    private final SimpleMeterRegistry metrics = new SimpleMeterRegistry();
    private final ApiSecurityErrorWriter errors = new ApiSecurityErrorWriter(new ObjectMapper().findAndRegisterModules());

    private AuthenticatedRateLimitFilter limiter(int requests, int capacity) {
        return new AuthenticatedRateLimitFilter(errors, metrics, requests, 10, capacity, time::get);
    }

    private JwtAuthenticationToken identity(String issuer, String subject, String tokenValue) {
        var builder = Jwt.withTokenValue(tokenValue).header("alg", "RS256")
                .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(300));
        if (issuer != null) builder.claim("iss", issuer);
        if (subject != null) builder.claim("sub", subject);
        return new JwtAuthenticationToken(builder.build(), List.of());
    }

    private MockHttpServletResponse call(AuthenticatedRateLimitFilter filter, Authentication authentication,
            String ip) throws Exception {
        var request = new MockHttpServletRequest("GET", "/api/v1/categories");
        request.setServletPath("/api/v1/categories");
        request.setRemoteAddr(ip);
        request.addHeader("X-User-ID", java.util.UUID.randomUUID().toString());
        request.addHeader("X-Device-ID", java.util.UUID.randomUUID().toString());
        request.addHeader(RequestCorrelationFilter.HEADER, "principal-quota-check");
        var response = new MockHttpServletResponse();
        SecurityContextHolder.getContext().setAuthentication(authentication);
        try {
            new RequestCorrelationFilter().doFilter(request, response,
                    (req, res) -> filter.doFilter(req, res,
                            (accepted, output) -> ((jakarta.servlet.http.HttpServletResponse) output).setStatus(204)));
        } finally {
            SecurityContextHolder.clearContext();
        }
        return response;
    }

    @Test
    void tokenAndIpChangesDoNotResetTheVerifiedIdentityBudget() throws Exception {
        var filter = limiter(2, 8);
        assertThat(call(filter, identity("https://issuer.test", "one", "token-a"), "192.0.2.1").getStatus()).isEqualTo(204);
        assertThat(call(filter, identity("https://issuer.test", "one", "token-b"), "192.0.2.2").getStatus()).isEqualTo(204);
        var denied = call(filter, identity("https://issuer.test", "one", "token-c"), "192.0.2.3");
        assertThat(denied.getStatus()).isEqualTo(429);
        assertThat(denied.getHeader("Retry-After")).isEqualTo("10");
        assertThat(denied.getHeader("Cache-Control")).isEqualTo("no-store");
        var body = new ObjectMapper().readTree(denied.getContentAsString());
        assertThat(body.get("code").asText()).isEqualTo("RATE_LIMITED");
        assertThat(body.get("correlationId").asText()).isEqualTo("principal-quota-check");
        assertThat(metrics.get("kunde.api.authenticated_rate_limit.denied").counter().count()).isEqualTo(1);
        assertThat(metrics.get("kunde.api.authenticated_rate_limit.denied").counter().getId().getTags()).isEmpty();
    }

    @Test
    void issuerAndSubjectAreIndependentTupleComponents() throws Exception {
        var filter = limiter(1, 8);
        assertThat(call(filter, identity("https://issuer.test/a", "b", "t"), "same-peer").getStatus()).isEqualTo(204);
        assertThat(call(filter, identity("https://issuer.test", "a/b", "t"), "same-peer").getStatus()).isEqualTo(204);
        assertThat(call(filter, identity("https://issuer.test/a", "c", "t"), "same-peer").getStatus()).isEqualTo(204);
        assertThat(call(filter, identity("https://issuer.test/a", "b", "t"), "other-peer").getStatus()).isEqualTo(429);
    }

    @Test
    void anonymousAndUnauthenticatedContextsCannotAllocatePrincipalEntries() throws Exception {
        var filter = limiter(1, 1);
        var unverified = identity("https://issuer.test", "unverified", "t");
        unverified.setAuthenticated(false);
        for (int i = 0; i < 3; i++) {
            assertThat(call(filter, null, "peer").getStatus()).isEqualTo(204);
            assertThat(call(filter, unverified, "peer").getStatus()).isEqualTo(204);
        }
        assertThat(call(filter, identity("https://issuer.test", "verified", "t"), "peer").getStatus()).isEqualTo(204);
    }

    @Test
    void malformedTrustedPrincipalFailsClosedInsteadOfBorrowingAnotherBudget() throws Exception {
        var filter = limiter(1, 1);
        for (var invalid : List.of(identity(null, "one", "t"), identity("https://issuer.test", null, "t"),
                identity("https://issuer.test", " ", "t"))) {
            var response = call(filter, invalid, "peer");
            assertThat(response.getStatus()).isEqualTo(401);
            assertThat(response.getHeader("WWW-Authenticate")).isEqualTo("Bearer");
        }
        assertThat(call(filter, identity("https://issuer.test", "one", "t"), "peer").getStatus()).isEqualTo(204);
    }

    @Test
    void expiryReleasesBudgetAndRetryAfterRoundsUp() throws Exception {
        var filter = limiter(1, 1);
        var user = identity("https://issuer.test", "one", "t");
        call(filter, user, "peer");
        time.set(TimeUnit.MILLISECONDS.toNanos(8500));
        assertThat(call(filter, user, "peer").getHeader("Retry-After")).isEqualTo("2");
        time.set(TimeUnit.SECONDS.toNanos(10));
        assertThat(call(filter, user, "peer").getStatus()).isEqualTo(204);
    }

    @Test
    void saturationDoesNotEvictActiveIdentitiesOrSpendTheirRemainingRequests() throws Exception {
        var filter = limiter(2, 1);
        var one = identity("https://issuer.test", "one", "t");
        var two = identity("https://issuer.test", "two", "t");
        assertThat(call(filter, one, "peer").getStatus()).isEqualTo(204);
        assertThat(call(filter, two, "peer").getStatus()).isEqualTo(429);
        assertThat(call(filter, one, "peer").getStatus()).isEqualTo(204);
        assertThat(call(filter, one, "peer").getStatus()).isEqualTo(429);
        time.set(TimeUnit.SECONDS.toNanos(10));
        assertThat(call(filter, two, "peer").getStatus()).isEqualTo(204);
    }

    @Test
    void concurrentAuthenticatedRequestsCannotOverspendQuota() throws Exception {
        var filter = limiter(3, 8);
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(8)) {
            var futures = new ArrayList<java.util.concurrent.Future<Integer>>();
            for (int i = 0; i < 20; i++) futures.add(executor.submit(() -> {
                if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Start timeout");
                return call(filter, identity("https://issuer.test", "one", "t"), "peer").getStatus();
            }));
            start.countDown();
            int accepted = 0;
            for (var future : futures) {
                int status = future.get(10, TimeUnit.SECONDS);
                assertThat(status).isIn(204, 429);
                if (status == 204) accepted++;
            }
            assertThat(accepted).isEqualTo(3);
        }
    }

    @Test
    void invalidConfigurationCannotDisableAuthenticatedProtection() {
        assertThatThrownBy(() -> limiter(0, 1)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> limiter(1, 0)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new AuthenticatedRateLimitFilter(errors, metrics, 1, 0, 1, time::get))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
