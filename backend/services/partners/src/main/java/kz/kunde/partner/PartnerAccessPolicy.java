package kz.kunde.partner;

import java.util.Arrays;
import java.util.Optional;
import java.util.UUID;
import kz.kunde.identity.ConsumerAccessPolicy;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/**
 * ADR-018: the partner API needs a valid consumer-client token that also carries the {@code kunde.partner} scope.
 * The scope is only an entry gate (derived from partner_staff at token issue); every request additionally
 * re-checks membership and role in {@link PartnerService}, so a revoked member loses access immediately.
 */
@Component("partnerAccessPolicy")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class PartnerAccessPolicy {
    private final ConsumerAccessPolicy consumer;

    public PartnerAccessPolicy(ConsumerAccessPolicy consumer) {
        this.consumer = consumer;
    }

    public boolean allowed(Authentication authentication) {
        if (!consumer.allowed(authentication)) return false;
        Object scope = ((JwtAuthenticationToken) authentication).getToken().getClaims().get("scope");
        return scope instanceof String scopes && Arrays.asList(scopes.split("\\s+")).contains("kunde.partner");
    }

    /** Internal user id from the own-auth token subject; empty when the subject is not a canonical user id. */
    public static Optional<UUID> userId(Jwt jwt) {
        try {
            return Optional.of(UUID.fromString(jwt.getSubject()));
        } catch (IllegalArgumentException | NullPointerException e) {
            return Optional.empty();
        }
    }
}
