package kz.kunde.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

class IdentityPocSecurityConfigurationTest {
    private static final String PROJECT = "poc-project";
    private static final String ORGANIZATION = "poc-organization";
    private static final String ROLE_CLAIM = "urn:zitadel:iam:org:project:" + PROJECT + ":roles";
    private static final Map<String, Object> ROLE = Map.of("kunde.poc", Map.of(ORGANIZATION, "poc.localhost"));

    @Test
    void assignedRoleInExpectedProjectAndOrganizationGrantsPocAccess() {
        var token = token().jti("access-token-id").claim(ROLE_CLAIM, ROLE).build();

        assertThat(IdentityPocSecurityConfiguration.zitadelAuthorities(token, PROJECT, ORGANIZATION))
                .extracting(GrantedAuthority::getAuthority)
                .containsExactly("SCOPE_kunde.poc");
    }

    @Test
    void requestedScopeAndRoleFromOtherProjectsOrOrganizationsGrantNoAccess() {
        var requestedScope = token().jti("access-token-id")
                .claim("scope", "kunde.poc urn:zitadel:iam:org:project:role:kunde.poc").build();
        var otherProject = token().jti("access-token-id")
                .claim("urn:zitadel:iam:org:project:other:roles", ROLE).build();
        var otherOrganization = token().jti("access-token-id")
                .claim(ROLE_CLAIM, Map.of("kunde.poc", Map.of("other", "other.localhost"))).build();
        var malformedRole = token().jti("access-token-id").claim(ROLE_CLAIM, "kunde.poc").build();

        for (Jwt token : new Jwt[] {requestedScope, otherProject, otherOrganization, malformedRole}) {
            assertThat(IdentityPocSecurityConfiguration.zitadelAuthorities(token, PROJECT, ORGANIZATION)).isEmpty();
        }
    }

    @Test
    void tokenWithoutAccessTokenIdentifierGrantsNoAccessEvenWithRoleClaim() {
        var token = token().claim(ROLE_CLAIM, ROLE).build();

        assertThat(IdentityPocSecurityConfiguration.zitadelAuthorities(token, PROJECT, ORGANIZATION)).isEmpty();
    }

    private static Jwt.Builder token() {
        return Jwt.withTokenValue("fixture").header("alg", "RS256").subject("synthetic-user");
    }
}
