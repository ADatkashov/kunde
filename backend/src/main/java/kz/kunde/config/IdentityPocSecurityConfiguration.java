package kz.kunde.config;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import kz.kunde.platform.ApiSecurityErrorWriter;
import kz.kunde.platform.ApiRateLimitFilter;
import org.springframework.web.filter.CorsFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.security.web.SecurityFilterChain;

/** Development-only protected endpoint used to compare local OIDC providers. */
@Configuration
@Profile("identity-poc & !prod & !production")
public class IdentityPocSecurityConfiguration {
    private static final String POC_AUTHORITY = "SCOPE_kunde.poc";

    @Bean
    @Order(0)
    SecurityFilterChain identityPocApi(HttpSecurity http, ApiSecurityErrorWriter errors, JwtDecoder issuerJwtDecoder,
            ApiRateLimitFilter limiter,
            @Value("${app.security.oidc.audience}") String audience,
            @Value("${app.security.oidc.poc-zitadel-organization:}") String zitadelOrganization)
            throws Exception {
        JwtAuthenticationConverter pocAuthorities = new JwtAuthenticationConverter();
        if (zitadelOrganization.isBlank()) {
            pocAuthorities.setJwtGrantedAuthoritiesConverter(new JwtGrantedAuthoritiesConverter());
        } else {
            pocAuthorities.setJwtGrantedAuthoritiesConverter(jwt -> zitadelAuthorities(jwt, audience, zitadelOrganization));
        }
        return http
                .securityMatcher("/api/v1/poc/**")
                .csrf(AbstractHttpConfigurer::disable)
                .addFilterAfter(limiter, CorsFilter.class)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .anyRequest().hasAuthority(POC_AUTHORITY))
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint((request, response, failure) -> errors.write(
                                request, response, HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "A valid bearer token is required"))
                        .accessDeniedHandler((request, response, failure) -> errors.write(
                                request, response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Required POC scope is missing")))
                .oauth2ResourceServer(oauth2 -> oauth2
                        .authenticationEntryPoint((request, response, failure) -> errors.write(
                                request, response, HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "A valid bearer token is required"))
                        .jwt(jwt -> jwt.decoder(issuerJwtDecoder).jwtAuthenticationConverter(pocAuthorities)))
                .build();
    }

    static Collection<GrantedAuthority> zitadelAuthorities(Jwt jwt, String project, String organization) {
        Object claim = jwt.getClaims().get("urn:zitadel:iam:org:project:" + project + ":roles");
        // ZITADEL 4.19.5 places jti on JWT access tokens. Its ID tokens can share the project audience.
        if (jwt.getId() != null && !jwt.getId().isBlank()
                && claim instanceof Map<?, ?> roles
                && roles.get("kunde.poc") instanceof Map<?, ?> grants
                && grants.get(organization) instanceof String domain && !domain.isBlank()) {
            return List.of(new SimpleGrantedAuthority(POC_AUTHORITY));
        }
        return List.of();
    }
}
