package kz.kunde.identity;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/**
 * Restricts consumer profile endpoints to access tokens issued for the consumer client.
 *
 * <p>Issuer, signature, time and audience are validated earlier by the JWT decoder. This policy adds the
 * provider-specific shape of a consumer access token. Profile {@code keycloak} (default, unchanged) needs
 * {@code typ=Bearer}, {@code azp} and the {@code kunde.consumer} scope. Profile {@code zitadel} (DEV, ADR-015)
 * needs the {@code client_id} claim; ZITADEL has no custom scopes, so the exact project audience enforced by
 * the decoder carries that boundary, and ID tokens ({@code nonce}/{@code at_hash}) are rejected.
 */
@Component("consumerAccessPolicy")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerAccessPolicy {
    private final String consumerClientId;
    private final boolean zitadel;

    public ConsumerAccessPolicy(@Value("${app.identity.consumer-client-id:kunde-consumer}") String consumerClientId,
            @Value("${app.identity.token-profile:keycloak}") String tokenProfile) {
        if (!"keycloak".equals(tokenProfile) && !"zitadel".equals(tokenProfile)) {
            throw new IllegalArgumentException("app.identity.token-profile must be keycloak or zitadel");
        }
        if (consumerClientId == null || consumerClientId.isBlank()) {
            throw new IllegalArgumentException("app.identity.consumer-client-id must not be blank");
        }
        this.consumerClientId = consumerClientId;
        this.zitadel = "zitadel".equals(tokenProfile);
    }

    public boolean allowed(Authentication authentication) {
        if (!(authentication instanceof JwtAuthenticationToken token) || !token.isAuthenticated()) return false;
        var jwt = token.getToken();
        Object subject = jwt.getClaims().get("sub");
        if (!(subject instanceof String value) || value.isBlank() || value.length() > 255) return false;
        if (zitadel) {
            return consumerClientId.equals(jwt.getClaims().get("client_id"))
                    && !jwt.getClaims().containsKey("nonce")
                    && !jwt.getClaims().containsKey("at_hash");
        }
        Object scope = jwt.getClaims().get("scope");
        return "Bearer".equals(jwt.getClaims().get("typ"))
                && consumerClientId.equals(jwt.getClaims().get("azp"))
                && scope instanceof String scopes
                && java.util.Arrays.asList(scopes.split("\\s+")).contains("kunde.consumer");
    }
}
