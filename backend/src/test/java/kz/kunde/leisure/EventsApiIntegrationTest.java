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

/** KUNDE Events &amp; Tickets as a product view over the shared ticketing engine (synthetic data, rolls back). */
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
        "app.security.authenticated-rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class EventsApiIntegrationTest {
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
    @SuppressWarnings("unchecked")
    void eventsAndLeisureAreSeparateProductsOnOneEngine() throws Exception {
        t.send("GET", "/api/v1/capabilities", null, null, null).andExpect(jsonPath("$.eventsEnabled").value(true)).andExpect(jsonPath("$.leisureEnabled").value(true));
        String cats = t.body(t.send("GET", "/api/v1/events/categories", null, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(cats, "$[*].product")).hasSize(9).containsOnly("EVENTS");
        String leisureCats = t.body(t.send("GET", "/api/v1/leisure/categories", null, null, null));
        assertThat((List<String>) JsonPath.read(leisureCats, "$[*].product")).containsOnly("LEISURE");
        assertThat((List<String>) JsonPath.read(leisureCats, "$[*].code")).doesNotContain("CINEMA", "CONCERT", "THEATER", "SPORT").contains("KARTING", "QUEST");

        String list = t.body(t.send("GET", "/api/v1/events?limit=50", null, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(list, "$[*].categoryCode")).isNotEmpty().isSubsetOf("CINEMA", "CONCERT", "THEATER", "EXHIBITION", "SPORT", "FESTIVAL", "SHOW", "STANDUP", "KIDS_SHOW");
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/events?q=боулинг", null, null, null)), "$")).isEmpty();
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/events?category=CINEMA&available=true&sort=price", null, null, null)), "$")).isNotEmpty();
        assertThat(t.body(t.send("GET", "/api/v1/events/home", null, null, null).andExpect(status().isOk()))).contains("popular", "weekend");

        UUID film = t.event("Демо-фильм");
        String detail = t.body(t.send("GET", "/api/v1/events/" + film, null, null, null).andExpect(status().isOk()));
        assertThat((String) JsonPath.read(detail, "$.product")).isEqualTo("EVENTS");
        assertThat((Boolean) JsonPath.read(detail, "$.bookable")).isTrue();
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", "/api/v1/events/" + film + "/sessions", null, null, null)), "$")).isNotEmpty();
        // one canonical card: the same id on the shared engine reports the same product, and a Leisure offer is not an event
        assertThat((String) JsonPath.read(t.body(t.send("GET", "/api/v1/leisure/events/" + film, null, null, null)), "$.product")).isEqualTo("EVENTS");
        UUID bowling = db.queryForObject("select id from marketplace.leisure_events where category_code = 'BOWLING' limit 1", UUID.class);
        t.send("GET", "/api/v1/events/" + bowling, null, null, null).andExpect(status().isNotFound());
        t.send("GET", "/api/v1/events/" + UUID.randomUUID(), null, null, null).andExpect(status().isNotFound());
    }

    @Test
    void ticketPurchaseStaysOnTheSharedEngine() throws Exception {
        String alice = t.login("+77000000541");
        UUID film = t.event("Демо-фильм");
        UUID session = t.firstSession(film);
        UUID std = t.ticketType(film, "Стандарт");
        String hold = t.body(t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice,
                "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "D", 5) + "\"]}]}", null).andExpect(status().isCreated()));
        assertThat((Long) JsonPath.parse(hold).read("$.totalMinor", Long.class)).isEqualTo(200000L);
    }
}
