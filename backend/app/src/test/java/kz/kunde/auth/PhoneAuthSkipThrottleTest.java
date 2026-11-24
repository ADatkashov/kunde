package kz.kunde.auth;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

/** DEV pilot switch: allowlisted synthetic numbers are not throttled when skip-throttle is on; the default stays throttled. */
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000501",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class PhoneAuthSkipThrottleTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void clean() {
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 = '+77000000501'");
    }

    @Test
    void allowlistedSyntheticNumberCanRequestCodesRepeatedly() throws Exception {
        for (int i = 0; i < 14; i++) {
            http.perform(post("/api/v1/auth/otp/request").contentType(MediaType.APPLICATION_JSON)
                    .content("{\"phone\":\"+77000000501\"}")).andExpect(status().isAccepted());
        }
    }
}
