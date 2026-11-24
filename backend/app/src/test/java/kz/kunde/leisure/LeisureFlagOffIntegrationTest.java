package kz.kunde.leisure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

/** Switch off (backend decides, not the app): no catalogue, no new hold/order/session, but a booking made earlier stays readable and cancellable. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.leisure.enabled=false",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000531",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class LeisureFlagOffIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @Test
    void newOperationsAreRefusedButExistingOrdersRemain() throws Exception {
        var t = new LeisureTestSupport(http, db);
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000531')");
        t.send("GET", "/api/v1/capabilities", null, null, null).andExpect(jsonPath("$.leisureEnabled").value(false));
        t.send("GET", "/api/v1/leisure/categories", null, null, null).andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        t.send("GET", "/api/v1/leisure/events", null, null, null).andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        String alice = t.login("+77000000531");
        t.send("POST", "/api/v1/leisure/sessions/" + UUID.randomUUID() + "/holds", alice, "{\"lines\":[{\"ticketTypeId\":\"" + UUID.randomUUID() + "\",\"quantity\":1}]}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("LEISURE_DISABLED"));
        t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + UUID.randomUUID() + "\"}", "flag-off-key-0000001").andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("LEISURE_DISABLED"));
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/orders", alice, null, null).andExpect(status().isOk())), "$")).isEmpty();
    }
}
