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
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Admission for verified external identities; business account ownership stays in its domain. */
@Component
public class AuthenticatedRateLimitFilter extends OncePerRequestFilter {
    private final ApiSecurityErrorWriter errors;
    private final Counter denied;
    private final FixedWindowQuota<IdentityKey> quota;

    @Autowired
    public AuthenticatedRateLimitFilter(ApiSecurityErrorWriter errors, MeterRegistry metrics,
            @Value("${app.security.authenticated-rate-limit.requests:60}") int requests,
            @Value("${app.security.authenticated-rate-limit.window-seconds:60}") int windowSeconds,
            @Value("${app.security.authenticated-rate-limit.max-identities:4096}") int maxIdentities) {
        this(errors, metrics, requests, windowSeconds, maxIdentities, System::nanoTime);
    }

    AuthenticatedRateLimitFilter(ApiSecurityErrorWriter errors, MeterRegistry metrics, int requests,
            int windowSeconds, int maxIdentities, LongSupplier clock) {
        this.errors = errors;
        this.denied = metrics.counter("kunde.api.authenticated_rate_limit.denied");
        this.quota = new FixedWindowQuota<>(requests, windowSeconds, maxIdentities, clock);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return !(path.equals("/api/v1") || path.startsWith("/api/v1/")) || path.equals("/api/v1/health");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        var authentication = SecurityContextHolder.getContext().getAuthentication();
        if (!(authentication instanceof JwtAuthenticationToken token) || !token.isAuthenticated()) {
            chain.doFilter(request, response);
            return;
        }
        // Spring's bearer filter must have verified signature/issuer/audience/time first.
        // Never parse Authorization or trust caller-supplied account/device identifiers here.
        var claims = token.getToken().getClaims();
        if (!(claims.get("iss") instanceof String issuer) || issuer.isBlank()
                || !(claims.get("sub") instanceof String subject) || subject.isBlank()) {
            errors.write(request, response, HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED",
                    "A valid authenticated identity is required");
            return;
        }
        long retryAfter = quota.acquire(new IdentityKey(issuer, subject));
        if (retryAfter > 0) {
            denied.increment();
            response.setHeader("Retry-After", Long.toString(retryAfter));
            response.setHeader("Cache-Control", "no-store");
            errors.write(request, response, HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED",
                    "Too many API requests for this authenticated identity; retry later");
            return;
        }
        chain.doFilter(request, response);
    }

    private record IdentityKey(String issuer, String subject) {}
}
