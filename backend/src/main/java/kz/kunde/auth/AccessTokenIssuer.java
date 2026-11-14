package kz.kunde.auth;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.UUID;

/** Signs short-lived HS256 access JWTs for the consumer client; verified by the local resource server. */
public class AccessTokenIssuer {
    private final PhoneAuthProperties props;
    private final byte[] key;

    public AccessTokenIssuer(PhoneAuthProperties props, AuthKeys keys) {
        this.props = props;
        this.key = keys.jwtKey();
    }

    public String issue(UUID userId, UUID sessionId, Instant now) {
        try {
            JWTClaimsSet claims = new JWTClaimsSet.Builder()
                    .issuer(props.issuer())
                    .subject(userId.toString())
                    .audience(List.of(props.audience()))
                    .issueTime(Date.from(now))
                    .notBeforeTime(Date.from(now))
                    .expirationTime(Date.from(now.plusSeconds(props.accessTtlSeconds())))
                    .jwtID(UUID.randomUUID().toString())
                    .claim("sid", sessionId.toString())
                    .claim("typ", "Bearer")
                    .claim("azp", props.clientId())
                    .claim("scope", "kunde.consumer")
                    .build();
            SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
            jwt.sign(new MACSigner(key));
            return jwt.serialize();
        } catch (JOSEException failure) {
            throw new IllegalStateException("Access token signing failed", failure);
        }
    }

    public int ttlSeconds() { return props.accessTtlSeconds(); }
}
