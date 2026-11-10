package kz.kunde.platform;

import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Returns a minimal token-validation result only in the isolated identity POC profile. */
@RestController
@Profile("identity-poc")
@RequestMapping("/api/v1/poc")
public class IdentityPocController {
    private static final Logger log = LoggerFactory.getLogger(IdentityPocController.class);

    @GetMapping("/whoami")
    Map<String, Object> whoAmI(@AuthenticationPrincipal Jwt jwt) {
        String scopeClaim = jwt.getClaimAsString("scope");
        List<String> scopes = scopeClaim == null || scopeClaim.isBlank()
                ? List.of()
                : List.of(scopeClaim.split("\\s+"));
        log.info("Validated identity POC token claims issuerPresent={} subjectPresent={} audienceCount={} scopePresent={} claimNames={}",
                jwt.getIssuer() != null, jwt.getSubject() != null,
                jwt.getAudience() == null ? 0 : jwt.getAudience().size(),
                scopeClaim != null, jwt.getClaims().keySet());
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("issuer", jwt.getIssuer() == null ? null : jwt.getIssuer().toString());
        result.put("subject", jwt.getSubject());
        result.put("audience", jwt.getAudience());
        result.put("scopes", scopes);
        result.put("authenticated", true);
        return result;
    }
}
