package kz.kunde.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.time.Instant;
import java.net.URI;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.core.env.StandardEnvironment;

class SecurityConfigurationTest {
    @Test
    void insecureHttpIssuerIsOnlyAllowedForExplicitPocLoopback() {
        assertThat(SecurityConfiguration.validatedIssuer("http://localhost:8180/realms/kunde-dev", true))
                .isEqualTo(URI.create("http://localhost:8180/realms/kunde-dev"));
        assertThatThrownBy(() -> SecurityConfiguration.validatedIssuer("http://localhost:8180/realms/kunde-dev", false))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> SecurityConfiguration.validatedIssuer("http://example.com/issuer", true))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(SecurityConfiguration.isLocalHttpIssuerAllowed(true, new StandardEnvironment())).isFalse();
        var pocEnvironment = new StandardEnvironment();
        pocEnvironment.setActiveProfiles("identity-poc");
        assertThat(SecurityConfiguration.isLocalHttpIssuerAllowed(true, pocEnvironment)).isTrue();
        assertThat(SecurityConfiguration.isLocalHttpIssuerAllowed(false, pocEnvironment)).isFalse();
    }

    @Test
    void audienceValidatorAcceptsOnlyTheConfiguredAudience() {
        var validator = SecurityConfiguration.audienceValidator("kunde-api");
        var accepted = jwtWithAudience("kunde-api");
        var rejected = jwtWithAudience("other-api");

        assertThat(validator.validate(accepted).hasErrors()).isFalse();
        assertThat(validator.validate(rejected).getErrors())
                .anySatisfy(error -> assertThat(error.getDescription()).contains("Required audience"));
    }

    @Test
    void issuerConfigurationRequiresAnAudienceBeforeDiscovery() {
        assertThatThrownBy(() -> new SecurityConfiguration()
                .issuerJwtDecoder("https://identity.example.test", " ", false, new StandardEnvironment()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("audience is required");
    }

    @Test
    void defaultIssuerAndTimestampValidatorRejectsWrongIssuerAndExpiredTokens() {
        var validator = JwtValidators.createDefaultWithIssuer("https://identity.example.test");

        assertThat(validator.validate(jwtWithClaims("https://identity.example.test",
                Instant.now().minusSeconds(10), Instant.now().plusSeconds(60))).hasErrors()).isFalse();
        assertThat(validator.validate(jwtWithClaims("https://other.example.test",
                Instant.now().minusSeconds(10), Instant.now().plusSeconds(60))).hasErrors()).isTrue();
        assertThat(validator.validate(jwtWithClaims("https://identity.example.test",
                Instant.now().minusSeconds(660), Instant.now().minusSeconds(600))).hasErrors()).isTrue();
    }

    @Test
    void productionProfilesCannotEnablePocHttpEvenWhenCombined() {
        for (String production : java.util.List.of("prod", "production")) {
            var environment = new StandardEnvironment();
            environment.setActiveProfiles(production, "identity-poc");
            assertThat(SecurityConfiguration.isLocalHttpIssuerAllowed(true, environment)).isFalse();
            var context = new org.springframework.context.annotation.AnnotationConfigApplicationContext();
            context.getEnvironment().setActiveProfiles(production, "identity-poc");
            context.register(IdentityPocSecurityConfiguration.class, kz.kunde.platform.IdentityPocController.class);
            context.refresh();
            try {
                assertThat(context.getBeansOfType(IdentityPocSecurityConfiguration.class)).isEmpty();
                assertThat(context.getBeansOfType(kz.kunde.platform.IdentityPocController.class)).isEmpty();
            } finally {
                context.close();
            }
        }
    }

    private Jwt jwtWithAudience(String audience) {
        return Jwt.withTokenValue("test-token")
                .header("alg", "none")
                .audience(List.of(audience))
                .build();
    }

    private Jwt jwtWithClaims(String issuer, Instant issuedAt, Instant expiresAt) {
        return Jwt.withTokenValue("test-token")
                .header("alg", "none")
                .issuer(issuer)
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .build();
    }
}
