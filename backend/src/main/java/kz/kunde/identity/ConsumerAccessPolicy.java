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
        String subject = jwt.getSubject();
        String scope = jwt.getClaimAsString("scope");
        String type = jwt.getClaimAsString("typ");
        String authorizedParty = jwt.getClaimAsString("azp");
        return subject != null && !subject.isBlank()
                && "Bearer".equals(type)
                && consumerClientId.equals(authorizedParty)
                && scope != null && java.util.Arrays.asList(scope.split("\\s+")).contains("kunde.consumer");
    }
}
