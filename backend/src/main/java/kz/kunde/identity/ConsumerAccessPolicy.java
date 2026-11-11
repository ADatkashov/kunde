package kz.kunde.identity;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/** Restricts consumer profile endpoints to access tokens issued for the consumer client. */
@Component("consumerAccessPolicy")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerAccessPolicy {
    private final String consumerClientId;

    public ConsumerAccessPolicy(@Value("${app.identity.consumer-client-id:kunde-consumer}") String consumerClientId) {
        this.consumerClientId = consumerClientId;
    }

    public boolean allowed(Authentication authentication) {
        if (!(authentication instanceof JwtAuthenticationToken token) || !token.isAuthenticated()) return false;
        var jwt = token.getToken();
        Object subject = jwt.getClaims().get("sub");
        Object scope = jwt.getClaims().get("scope");
        Object type = jwt.getClaims().get("typ");
        Object authorizedParty = jwt.getClaims().get("azp");
        return subject instanceof String value && !value.isBlank() && value.length() <= 255
                && "Bearer".equals(type)
                && consumerClientId.equals(authorizedParty)
                && scope instanceof String scopes
                && java.util.Arrays.asList(scopes.split("\\s+")).contains("kunde.consumer");
    }
}
