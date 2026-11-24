package kz.kunde.leisure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

/** The EVENTS switch is independent of LEISURE: Events sales stop, Leisure keeps working. */
@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true",
        "app.auth.phone.dev-otp.skip-throttle=true",
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000541",
        "app.security.rate-limit.requests=100000",
        "app.security.authenticated-rate-limit.requests=100000",
        "app.events.enabled=false"
})
@AutoConfigureMockMvc
class EventsFlagOffIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired PhoneAuthProperties auth;
    @Autowired Environment env;
    LeisureTestSupport t;

    @BeforeEach
    void setUp() {
        t = new LeisureTestSupport(http, db);
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000541')");
        new LeisureDemoSeeder(db, auth, env).seed();
    }

    @Test
    void switchingEventsOffBlocksNewSalesButNotLeisure() throws Exception {
        t.send("GET", "/api/v1/capabilities", null, null, null).andExpect(jsonPath("$.eventsEnabled").value(false)).andExpect(jsonPath("$.leisureEnabled").value(true));
        t.send("GET", "/api/v1/events/categories", null, null, null).andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        t.send("GET", "/api/v1/events", null, null, null).andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events?limit=50", null, null, null)), "$")).isNotEmpty();
        String alice = t.login("+77000000541");
        UUID film = t.event("Демо-фильм");
        UUID session = t.firstSession(film);
        UUID std = t.ticketType(film, "Стандарт");
        t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice,
                "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "D", 5) + "\"]}]}", null)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("EVENTS_DISABLED"));
        // Leisure keeps selling: a bowling lane hold is not refused by the Events switch
        UUID bowling = db.queryForObject("select id from marketplace.leisure_events where category_code = 'BOWLING' limit 1", UUID.class);
        UUID lane = t.firstSession(bowling);
        UUID laneType = db.queryForObject("select id from marketplace.leisure_ticket_types where event_id = ? limit 1", UUID.class, bowling);
        t.send("POST", "/api/v1/leisure/sessions/" + lane + "/holds", alice, "{\"lines\":[{\"ticketTypeId\":\"" + laneType + "\",\"quantity\":1}]}", null)
                .andExpect(status().isCreated());
    }
}
