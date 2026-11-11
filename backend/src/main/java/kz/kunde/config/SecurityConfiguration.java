package kz.kunde.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtValidators;
import java.net.URI;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import kz.kunde.platform.ApiSecurityErrorWriter;
import org.springframework.http.HttpStatus;

@Configuration
@EnableMethodSecurity
public class SecurityConfiguration {
    @Bean
    @ConditionalOnExpression("'${app.security.oidc.issuer-uri:}' != ''")
    JwtDecoder issuerJwtDecoder(@Value("${app.security.oidc.issuer-uri}") String issuerUri,
            @Value("${app.security.oidc.audience:}") String audience,
            @Value("${app.security.oidc.allow-insecure-http-issuer:false}") boolean allowInsecureHttpIssuer,
            Environment environment) {
        if (audience.isBlank()) {
            throw new IllegalArgumentException("OIDC audience is required when an issuer is configured");
        }
        boolean allowLocalHttp = isLocalHttpIssuerAllowed(allowInsecureHttpIssuer, environment);
        URI issuer = validatedIssuer(issuerUri, allowLocalHttp);
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withIssuerLocation(issuerUri).build();
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(issuerUri), audienceValidator(audience)));
        return decoder;
    }

    static boolean isLocalHttpIssuerAllowed(boolean propertyEnabled, Environment environment) {
        return propertyEnabled && environment.acceptsProfiles(Profiles.of("identity-poc"))
                && !environment.acceptsProfiles(Profiles.of("prod", "production"));
    }

    static URI validatedIssuer(String issuerUri, boolean allowLocalHttp) {
        URI issuer = URI.create(issuerUri);
        boolean secure = "https".equalsIgnoreCase(issuer.getScheme());
        String host = issuer.getHost();
        boolean loopback = host != null && (host.equalsIgnoreCase("localhost") || host.endsWith(".localhost") ||
                host.equals("127.0.0.1") || host.equals("::1"));
        boolean allowedLocalHttp = allowLocalHttp && "http".equalsIgnoreCase(issuer.getScheme()) && loopback;
        if ((!secure && !allowedLocalHttp) || host == null || issuer.getUserInfo() != null || issuer.getFragment() != null) {
            throw new IllegalArgumentException("OIDC issuer must use HTTPS; HTTP is allowed only for loopback in the identity-poc profile");
        }
        return issuer;
    }

    static OAuth2TokenValidator<Jwt> audienceValidator(String audience) {
        return jwt -> jwt.getAudience() != null && jwt.getAudience().contains(audience)
                ? OAuth2TokenValidatorResult.success()
                : OAuth2TokenValidatorResult.failure(
                        new OAuth2Error("invalid_token", "Required audience is missing", null));
    }

    @Bean
    @Order(1)
    @ConditionalOnExpression("'${app.security.oidc.issuer-uri:}' != ''")
    SecurityFilterChain oidcApi(HttpSecurity http, ApiSecurityErrorWriter errors, JwtDecoder issuerJwtDecoder) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(Customizer.withDefaults())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/api/v1/health", "/api/v1/capabilities", "/api/v1/categories", "/api/v1/search", "/api/v1/openapi.yaml",
                                "/actuator/health", "/actuator/health/**")
                        .permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint((request, response, failure) -> errors.write(
                                request, response, HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "Authentication is required"))
                        .accessDeniedHandler((request, response, failure) -> errors.write(
                                request, response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed")))
                .oauth2ResourceServer(oauth2 -> oauth2
                        .authenticationEntryPoint((request, response, failure) -> errors.write(
                                request, response, HttpStatus.UNAUTHORIZED,
                                "UNAUTHENTICATED", "A valid bearer token is required"))
                        .jwt(jwt -> jwt.decoder(issuerJwtDecoder)))
                .build();
    }

    @Bean
    @Order(2)
    @ConditionalOnExpression("'${app.security.oidc.issuer-uri:}' == ''")
    SecurityFilterChain foundationOnlyApi(HttpSecurity http, ApiSecurityErrorWriter errors) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(Customizer.withDefaults())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/api/v1/health", "/api/v1/capabilities", "/api/v1/categories", "/api/v1/search", "/api/v1/openapi.yaml",
                                "/actuator/health", "/actuator/health/**")
                        .permitAll()
                        .anyRequest().denyAll())
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint((request, response, failure) -> errors.write(
                                request, response, HttpStatus.SERVICE_UNAVAILABLE,
                                "AUTHENTICATION_NOT_CONFIGURED", "Protected API routes are not enabled"))
                        .accessDeniedHandler((request, response, failure) -> errors.write(
                                request, response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed")))
                .build();
    }
}
