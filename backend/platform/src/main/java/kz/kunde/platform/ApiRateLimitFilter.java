package kz.kunde.platform;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.function.LongSupplier;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Bounded per-process protection; shared edge/account quotas remain separate controls. */
@Component
public class ApiRateLimitFilter extends OncePerRequestFilter {
    private final ApiSecurityErrorWriter errors;
    private final Counter denied;
    private final FixedWindowQuota<String> quota;

    @Autowired
    public ApiRateLimitFilter(ApiSecurityErrorWriter errors, MeterRegistry metrics,
            @Value("${app.security.rate-limit.requests:120}") int requests,
            @Value("${app.security.rate-limit.window-seconds:60}") int windowSeconds,
            @Value("${app.security.rate-limit.max-clients:4096}") int maxClients) {
        this(errors, metrics, requests, windowSeconds, maxClients, System::nanoTime);
    }

    ApiRateLimitFilter(ApiSecurityErrorWriter errors, MeterRegistry metrics, int requests,
            int windowSeconds, int maxClients, LongSupplier clock) {
        this.errors = errors;
        this.denied = metrics.counter("kunde.api.rate_limit.denied");
        this.quota = new FixedWindowQuota<>(requests, windowSeconds, maxClients, clock);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // The container decodes this path just as it does for controller/security routing.
        // Raw requestURI would let an encoded API prefix bypass the quota.
        String path = request.getServletPath();
        return !(path.equals("/api/v1") || path.startsWith("/api/v1/"))
                || path.equals("/api/v1/health");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        // Never trust caller-controlled Forwarded/X-Forwarded-For or token contents here.
        long retryAfter = quota.acquire(request.getRemoteAddr());
        if (retryAfter > 0) {
            denied.increment();
            response.setHeader("Retry-After", Long.toString(retryAfter));
            response.setHeader("Cache-Control", "no-store");
            response.setHeader("X-Content-Type-Options", "nosniff");
            errors.write(request, response, HttpStatus.TOO_MANY_REQUESTS,
                    "RATE_LIMITED", "Too many API requests; retry later");
            return;
        }
        chain.doFilter(request, response);
    }

}
