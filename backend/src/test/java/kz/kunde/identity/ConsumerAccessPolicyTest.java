package kz.kunde.identity;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class ConsumerAccessPolicyTest {
    private static JwtAuthenticationToken token(Map<String, Object> extra) {
        Map<String, Object> claims = new HashMap<>(Map.of("sub", "user-1", "iss", "https://idp.example.test"));
        claims.putAll(extra);
        Jwt jwt = new Jwt("t", Instant.now(), Instant.now().plusSeconds(300), Map.of("alg", "RS256"), claims);
        return new JwtAuthenticationToken(jwt, java.util.List.of());
    }

    @Test
    void keycloakProfileKeepsExistingRules() {
        var policy = new ConsumerAccessPolicy("kunde-consumer", "keycloak");
        Map<String, Object> ok = Map.of("typ", "Bearer", "azp", "kunde-consumer", "scope", "openid kunde.consumer");
        assertTrue(policy.allowed(token(ok)));
        assertFalse(policy.allowed(token(Map.of("typ", "Bearer", "azp", "kunde-consumer", "scope", "openid"))));
        assertFalse(policy.allowed(token(Map.of("typ", "ID", "azp", "kunde-consumer", "scope", "kunde.consumer"))));
        assertFalse(policy.allowed(token(Map.of("typ", "Bearer", "azp", "other", "scope", "kunde.consumer"))));
        assertFalse(policy.allowed(token(Map.of("client_id", "kunde-consumer"))));
    }

    @Test
    void zitadelProfileRequiresClientIdAndRejectsIdTokens() {
        var policy = new ConsumerAccessPolicy("kunde-client-123", "zitadel");
        assertTrue(policy.allowed(token(Map.of("client_id", "kunde-client-123"))));
        assertFalse(policy.allowed(token(Map.of("client_id", "someone-else"))));
        assertFalse(policy.allowed(token(Map.of())));
        assertFalse(policy.allowed(token(Map.of("client_id", "kunde-client-123", "nonce", "n"))));
        assertFalse(policy.allowed(token(Map.of("client_id", "kunde-client-123", "at_hash", "h"))));
        // Keycloak-shaped claims alone must not pass under the ZITADEL profile.
        assertFalse(policy.allowed(token(Map.of("typ", "Bearer", "azp", "kunde-client-123", "scope", "kunde.consumer"))));
    }

    @Test
    void rejectsBlankOrOversizedSubjectAndNonJwtAuthentication() {
        var policy = new ConsumerAccessPolicy("c", "zitadel");
        assertFalse(policy.allowed(token(Map.of("client_id", "c", "sub", " "))));
        assertFalse(policy.allowed(token(Map.of("client_id", "c", "sub", "x".repeat(256)))));
        assertFalse(policy.allowed(null));
    }

    @Test
    void rejectsUnknownProfileAndBlankClient() {
        assertThrows(IllegalArgumentException.class, () -> new ConsumerAccessPolicy("c", "auth0"));
        assertThrows(IllegalArgumentException.class, () -> new ConsumerAccessPolicy(" ", "keycloak"));
    }
}
