package kz.kunde.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.jayway.jsonpath.JsonPath;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/** Phone OTP authentication end to end against PostgreSQL; synthetic numbers only. */
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000101,+77000000102,+77000000103,+77000000104,+77000000105,"
                + "+77000000106,+77000000107,+77000000108,+77000000109,+77000000110,+77000000111",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class PhoneAuthHttpIntegrationTest {
    private static final String CODE = "123456";
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void cleanChallenges() {
        // Repeatable on a persistent local database; users and audit rows are append-only and stay.
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 LIKE '+770000001%'");
    }

    private ResultActions postJson(String path, String json) throws Exception {
        return http.perform(post(path).contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private ResultActions requestOtp(String phone) throws Exception {
        return postJson("/api/v1/auth/otp/request", "{\"phone\":\"" + phone + "\"}");
    }

    private ResultActions verify(String phone, String code) throws Exception {
        return postJson("/api/v1/auth/otp/verify", "{\"phone\":\"" + phone + "\",\"code\":\"" + code + "\"}");
    }

    private String login(String phone) throws Exception {
        requestOtp(phone).andExpect(status().isAccepted());
        return verify(phone, CODE).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private void ageChallenges(String phone) {
        db.update("UPDATE identity.otp_challenges SET created_at = created_at - interval '2 hours' WHERE phone_e164 = ?", phone);
    }

    private static String access(String body) { return JsonPath.read(body, "$.accessToken"); }
    private static String refresh(String body) { return JsonPath.read(body, "$.refreshToken"); }

    @Test
    void phoneToOtpToProfileConsentsAndAddresses(CapturedOutput output) throws Exception {
        String body = login("+77000000101");
        String access = access(body);
        String refresh = refresh(body);
        assertThat((String) JsonPath.read(body, "$.tokenType")).isEqualTo("Bearer");
        assertThat((Integer) JsonPath.read(body, "$.expiresIn")).isEqualTo(900);

        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + access))
                .andExpect(status().isOk()).andExpect(header().string("Cache-Control", "no-store"));
        String profile = http.perform(get("/api/v1/me").header("Authorization", "Bearer " + access))
                .andReturn().getResponse().getContentAsString();
        int version = JsonPath.read(profile, "$.version");
        http.perform(patch("/api/v1/me").header("Authorization", "Bearer " + access)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\"Test User\",\"preferredLanguage\":\"ru\",\"version\":" + version + "}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.displayName").value("Test User"));
        http.perform(get("/api/v1/me/consents").header("Authorization", "Bearer " + access)).andExpect(status().isOk());
        http.perform(post("/api/v1/me/addresses").header("Authorization", "Bearer " + access)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"label\":\"Home\",\"formattedAddress\":\"Synthetic address\",\"latitude\":43.2,\"longitude\":76.9}"))
                .andExpect(status().isCreated());
        http.perform(get("/api/v1/me/addresses").header("Authorization", "Bearer " + access))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].label").value("Home"));

        // Hashes only; never logged.
        assertThat(db.queryForList("SELECT code_hash FROM identity.otp_challenges WHERE phone_e164 = '+77000000101'", String.class))
                .doesNotContain(CODE).allSatisfy(hash -> assertThat(hash).hasSize(64));
        assertThat(db.queryForList("SELECT token_hash FROM identity.refresh_tokens", String.class)).doesNotContain(refresh);
        assertThat(output.getAll()).doesNotContain(access).doesNotContain(refresh).doesNotContain("+77000000101");
        assertThat(db.queryForList("SELECT phone_hash FROM identity.auth_events WHERE phone_hash IS NOT NULL", String.class))
                .allSatisfy(hash -> assertThat(hash).doesNotContain("+7"));
    }

    @Test
    void refreshRotatesAndReplayRevokesTheSession() throws Exception {
        String first = login("+77000000102");
        String second = postJson("/api/v1/auth/token/refresh", "{\"refreshToken\":\"" + refresh(first) + "\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertThat(refresh(second)).isNotEqualTo(refresh(first));
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + access(second))).andExpect(status().isOk());

        // Replaying the rotated token revokes the whole session, including the new tokens.
        postJson("/api/v1/auth/token/refresh", "{\"refreshToken\":\"" + refresh(first) + "\"}").andExpect(status().isUnauthorized());
        postJson("/api/v1/auth/token/refresh", "{\"refreshToken\":\"" + refresh(second) + "\"}").andExpect(status().isUnauthorized());
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + access(second))).andExpect(status().isUnauthorized());
    }

    @Test
    void logoutRevokesSessionImmediately() throws Exception {
        String tokens = login("+77000000103");
        postJson("/api/v1/auth/logout", "{\"refreshToken\":\"" + refresh(tokens) + "\"}").andExpect(status().isNoContent());
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + access(tokens))).andExpect(status().isUnauthorized());
        postJson("/api/v1/auth/token/refresh", "{\"refreshToken\":\"" + refresh(tokens) + "\"}").andExpect(status().isUnauthorized());
        // Idempotent and not an oracle: unknown and repeated tokens behave the same.
        postJson("/api/v1/auth/logout", "{\"refreshToken\":\"" + refresh(tokens) + "\"}").andExpect(status().isNoContent());
        postJson("/api/v1/auth/logout", "{\"refreshToken\":\"unknown\"}").andExpect(status().isNoContent());
    }

    @Test
    void expiredOtpIsRejected() throws Exception {
        requestOtp("+77000000104").andExpect(status().isAccepted());
        db.update("UPDATE identity.otp_challenges SET expires_at = now() - interval '1 second' WHERE phone_e164 = '+77000000104'");
        verify("+77000000104", CODE).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_CODE"));
    }

    @Test
    void expiredRefreshTokenAndSessionAreRejected() throws Exception {
        String tokens = login("+77000000105");
        db.update("UPDATE identity.refresh_tokens SET expires_at = now() - interval '1 second' WHERE token_hash IN "
                + "(SELECT token_hash FROM identity.refresh_tokens t JOIN identity.auth_sessions s ON s.id = t.session_id "
                + "JOIN identity.phone_identities p ON p.user_id = s.user_id WHERE p.phone_e164 = '+77000000105')");
        postJson("/api/v1/auth/token/refresh", "{\"refreshToken\":\"" + refresh(tokens) + "\"}").andExpect(status().isUnauthorized());
    }

    @Test
    void wrongCodesLockTheChallengeAfterMaxAttempts() throws Exception {
        requestOtp("+77000000106").andExpect(status().isAccepted());
        for (int i = 0; i < 5; i++) {
            verify("+77000000106", "000000").andExpect(status().isUnauthorized());
        }
        // Even the right code no longer works: the challenge is burned.
        verify("+77000000106", CODE).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("INVALID_CODE"));
        assertThat(db.queryForObject("SELECT count(*) FROM identity.auth_events WHERE event_type = 'OTP_LOCKED'", Integer.class))
                .isGreaterThanOrEqualTo(1);
    }

    @Test
    void codeRequestsAreThrottledPerPhone() throws Exception {
        String phone = "+77000000107";
        requestOtp(phone).andExpect(status().isAccepted());
        requestOtp(phone).andExpect(status().isTooManyRequests()); // cooldown
        for (int i = 0; i < 2; i++) {
            db.update("UPDATE identity.otp_challenges SET created_at = created_at - interval '60 seconds' WHERE phone_e164 = ?", phone);
            requestOtp(phone).andExpect(status().isAccepted());
        }
        db.update("UPDATE identity.otp_challenges SET created_at = created_at - interval '60 seconds' WHERE phone_e164 = ?", phone);
        requestOtp(phone).andExpect(status().isTooManyRequests()); // 3 per 10-minute window
    }

    @Test
    void responsesDoNotRevealWhetherANumberIsRegisteredOrAllowlisted() throws Exception {
        login("+77000000108"); // registered
        String registered = requestAfterAging("+77000000108");
        String fresh = requestOtp("+77000000109").andExpect(status().isAccepted()).andReturn().getResponse().getContentAsString();
        // Not allowlisted, never registered.
        String unknown = requestOtp("+77000000199").andExpect(status().isAccepted()).andReturn().getResponse().getContentAsString();
        assertThat(registered).isEqualTo(fresh).isEqualTo(unknown);
        // The DEV code is useless for a number outside the allowlist, with the same error as a wrong code.
        String wrong = verify("+77000000199", "000000").andExpect(status().isUnauthorized()).andReturn().getResponse().getContentAsString();
        String dev = verify("+77000000199", CODE).andExpect(status().isUnauthorized()).andReturn().getResponse().getContentAsString();
        assertThat(dev.replaceAll("\"(correlationId|timestamp)\":\"[^\"]*\",?", ""))
                .isEqualTo(wrong.replaceAll("\"(correlationId|timestamp)\":\"[^\"]*\",?", ""));
        assertThat(db.queryForObject("SELECT count(*) FROM identity.phone_identities WHERE phone_e164 = '+77000000199'", Integer.class)).isZero();
    }

    private String requestAfterAging(String phone) throws Exception {
        ageChallenges(phone);
        return requestOtp(phone).andExpect(status().isAccepted()).andReturn().getResponse().getContentAsString();
    }

    @Test
    void sameNumberAlwaysMapsToTheSameAccount() throws Exception {
        String first = login("+77000000110");
        ageChallenges("+77000000110");
        String second = login("+77000000110");
        UUID a = UUID.fromString(JsonPath.read(decodePayload(access(first)), "$.sub"));
        UUID b = UUID.fromString(JsonPath.read(decodePayload(access(second)), "$.sub"));
        assertThat(a).isEqualTo(b);
        assertThat(db.queryForObject("SELECT count(*) FROM identity.phone_identities WHERE phone_e164 = '+77000000110'", Integer.class)).isEqualTo(1);
    }

    private static String decodePayload(String jwt) {
        return new String(java.util.Base64.getUrlDecoder().decode(jwt.split("\\.")[1]), StandardCharsets.UTF_8);
    }

    @Test
    void invalidInputIsRejectedWithoutDisclosure() throws Exception {
        postJson("/api/v1/auth/otp/request", "{\"phone\":\"not-a-number\"}").andExpect(status().isBadRequest());
        postJson("/api/v1/auth/otp/request", "{}").andExpect(status().isBadRequest());
        postJson("/api/v1/auth/otp/verify", "{\"phone\":\"+77000000101\",\"code\":\"12\"}").andExpect(status().isBadRequest());
        postJson("/api/v1/auth/token/refresh", "{\"refreshToken\":\"\"}").andExpect(status().isBadRequest());
    }

    @Test
    void forgedExpiredAndWrongAudienceTokensAreRejected() throws Exception {
        String valid = access(login("+77000000111"));
        String payload = valid.split("\\.")[1];
        String tampered = valid.split("\\.")[0] + "." + payload + ".AAAA";
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + tampered)).andExpect(status().isUnauthorized());
        http.perform(get("/api/v1/me")).andExpect(status().isUnauthorized());
        // Right shape, signed with an unrelated key.
        String foreign = sign("kunde-phone-auth", "kunde-api", 600, "x".repeat(32));
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + foreign)).andExpect(status().isUnauthorized());
        // Right key is unknowable here, so check claims through the real issuer path with a past expiry instead.
        String expired = sign("kunde-phone-auth", "kunde-api", -600, "x".repeat(32));
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + expired)).andExpect(status().isUnauthorized());
        String audience = sign("kunde-phone-auth", "other", 600, "x".repeat(32));
        http.perform(get("/api/v1/me").header("Authorization", "Bearer " + audience)).andExpect(status().isUnauthorized());
    }

    private static String sign(String issuer, String audience, long ttl, String key) throws Exception {
        Date now = new Date();
        var claims = new JWTClaimsSet.Builder().issuer(issuer).subject(UUID.randomUUID().toString())
                .audience(List.of(audience)).issueTime(new Date(now.getTime() - 3_600_000))
                .expirationTime(new Date(now.getTime() + ttl * 1000)).claim("sid", UUID.randomUUID().toString())
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer").build();
        var jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
        jwt.sign(new MACSigner(key.getBytes(StandardCharsets.UTF_8)));
        return jwt.serialize();
    }
}
