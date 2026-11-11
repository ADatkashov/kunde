package kz.kunde.config;

import kz.kunde.platform.ApiSecurityErrorWriter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import java.util.ArrayList;
import java.util.Collection;
import java.util.stream.Stream;
import org.springframework.security.web.SecurityFilterChain;

/** Development-only protected endpoint used to compare local OIDC providers. */
@Configuration
@Profile("identity-poc & !prod & !production")
public class IdentityPocSecurityConfiguration {
    @Bean
    @Order(0)
    SecurityFilterChain identityPocApi(HttpSecurity http, ApiSecurityErrorWriter errors, JwtDecoder issuerJwtDecoder)
            throws Exception {
        JwtGrantedAuthoritiesConverter defaultScopes = new JwtGrantedAuthoritiesConverter();
        JwtAuthenticationConverter pocAuthorities = new JwtAuthenticationConverter();
        pocAuthorities.setJwtGrantedAuthoritiesConverter(jwt -> {
            Collection<org.springframework.security.core.GrantedAuthority> mapped =
                    new ArrayList<>(defaultScopes.convert(jwt));
            String scopeClaim = jwt.getClaimAsString("scope");
            boolean hasPocRoleScope = scopeClaim != null && Stream.of(scopeClaim.split("\\s+"))
                    .anyMatch(scope -> scope.equals("kunde.poc") ||
                            scope.equals("urn:zitadel:iam:org:project:role:kunde.poc"));
            if (hasPocRoleScope) mapped.add(new SimpleGrantedAuthority("SCOPE_kunde.poc"));
            return mapped;
        });
        return http
                .securityMatcher("/api/v1/poc/**")
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .anyRequest().hasAuthority("SCOPE_kunde.poc"))
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
}
