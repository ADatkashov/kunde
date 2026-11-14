package kz.kunde.config;

import java.util.Set;
import java.util.UUID;
import kz.kunde.auth.AccessTokenIssuer;
import kz.kunde.auth.AuthKeys;
import kz.kunde.auth.DevOtpProvider;
import kz.kunde.auth.DisabledOtpProvider;
import kz.kunde.auth.OtpDeliveryProvider;
import kz.kunde.auth.PhoneAuthGuard;
import kz.kunde.auth.PhoneAuthProperties;
import kz.kunde.auth.PhoneAuthService;
import kz.kunde.platform.ApiBodyLimitFilter;
import kz.kunde.platform.ApiRateLimitFilter;
import kz.kunde.platform.ApiSecurityErrorWriter;
import kz.kunde.platform.AuthenticatedRateLimitFilter;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.filter.CorsFilter;

/**
 * Own phone-OTP authentication (ADR-015 amended 2026-11-14). The Spring resource-server boundary
 * stays fail-closed: HS256 signature, exact issuer, audience, time claims, a live server-side
 * session and the existing consumer access policy are all required.
 */
@Configuration
@EnableConfigurationProperties(PhoneAuthProperties.class)
public class PhoneAuthConfiguration {
    /** Runs on every start, including when the feature is off, so unsafe flag combinations abort startup. */
    @Bean
    PhoneAuthStartupCheck phoneAuthStartupCheck(PhoneAuthProperties props, Environment env) {
        PhoneAuthGuard.validate(props, env);
        return new PhoneAuthStartupCheck();
    }

    public static final class PhoneAuthStartupCheck {}

    @Bean
    @ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
    AuthKeys phoneAuthKeys(PhoneAuthProperties props, PhoneAuthStartupCheck check) {
        return new AuthKeys(props.secret());
    }

    @Bean
    @ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
    OtpDeliveryProvider otpDeliveryProvider(PhoneAuthProperties props, PhoneAuthStartupCheck check) {
        // No real SMS/WhatsApp provider is connected: anything but the guarded DEV provider fails closed.
        return props.devOtp().enabled() ? new DevOtpProvider(Set.copyOf(props.devOtp().allowedPhones()))
                : new DisabledOtpProvider();
    }

    @Bean
    @ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
    AccessTokenIssuer accessTokenIssuer(PhoneAuthProperties props, AuthKeys keys) {
        return new AccessTokenIssuer(props, keys);
    }

    @Bean
    @ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
    PhoneAuthService phoneAuthService(JdbcTemplate db, PlatformTransactionManager tx, PhoneAuthProperties props,
            AuthKeys keys, AccessTokenIssuer issuer, OtpDeliveryProvider provider) {
        return new PhoneAuthService(db, tx, props, keys, issuer, provider);
    }

    @Bean
    @ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
    JwtDecoder phoneJwtDecoder(PhoneAuthProperties props, AuthKeys keys, PhoneAuthService auth) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder
                .withSecretKey(new SecretKeySpec(keys.jwtKey(), "HmacSHA256"))
                .macAlgorithm(MacAlgorithm.HS256).build();
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(props.issuer()),
                SecurityConfiguration.audienceValidator(props.audience()),
                SecurityConfiguration.requiredClaimsValidator(),
                liveSession(auth)));
        return decoder;
    }

    static OAuth2TokenValidator<Jwt> liveSession(PhoneAuthService auth) {
        return jwt -> {
            try {
                if (jwt.getClaims().get("sid") instanceof String sid && auth.sessionActive(UUID.fromString(sid))) {
                    return OAuth2TokenValidatorResult.success();
                }
            } catch (IllegalArgumentException malformed) {
                // fall through to failure
            }
            return OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "Session is not active", null));
        };
    }

    @Bean
    @Order(1)
    @ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
    SecurityFilterChain phoneAuthApi(HttpSecurity http, ApiSecurityErrorWriter errors, JwtDecoder phoneJwtDecoder,
            ApiRateLimitFilter limiter, ApiBodyLimitFilter bodies, AuthenticatedRateLimitFilter authenticated)
            throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(Customizer.withDefaults())
                .addFilterAfter(limiter, CorsFilter.class)
                .addFilterAfter(bodies, ApiRateLimitFilter.class)
                .addFilterAfter(authenticated, BearerTokenAuthenticationFilter.class)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/api/v1/health", "/api/v1/capabilities", "/api/v1/categories",
                                "/api/v1/categories/*/offerings", "/api/v1/offerings/*", "/api/v1/search",
                                "/api/v1/search/offerings", "/api/v1/openapi.yaml",
                                "/actuator/health", "/actuator/health/**")
                        .permitAll()
                        .requestMatchers(org.springframework.http.HttpMethod.POST, "/api/v1/auth/otp/request",
                                "/api/v1/auth/otp/verify", "/api/v1/auth/token/refresh", "/api/v1/auth/logout")
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
                        .jwt(jwt -> jwt.decoder(phoneJwtDecoder)))
                .build();
    }
}
