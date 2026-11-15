package kz.kunde.admin;

import java.util.Arrays;
import kz.kunde.identity.ConsumerAccessPolicy;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/** ADR-018: a valid own-auth token that also carries {@code kunde.admin}; the database grant is checked per request. */
@Component("adminAccessPolicy")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class AdminAccessPolicy {
    private final ConsumerAccessPolicy consumer;

    public AdminAccessPolicy(ConsumerAccessPolicy consumer) {
        this.consumer = consumer;
    }

    public boolean allowed(Authentication authentication) {
        if (!consumer.allowed(authentication)) return false;
        Object scope = ((JwtAuthenticationToken) authentication).getToken().getClaims().get("scope");
        return scope instanceof String scopes && Arrays.asList(scopes.split("\\s+")).contains("kunde.admin");
    }
}
