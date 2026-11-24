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
        "app.auth.phone.dev-otp.allowed-phones=+77000000002,+77000000003,+77000000541,+77000000542",
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
        db.update("DELETE FROM identity.otp_challenges WHERE phone_e164 IN ('+77000000002','+77000000003','+77000000541','+77000000542')");
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

    @Test
    @SuppressWarnings("unchecked")
    void partnerSeesEventsAndLeisureApart() throws Exception {
        UUID partner = db.queryForObject("select partner_id from marketplace.leisure_venues where slug = 'demo-leisure-cinema'", UUID.class);
        String owner = t.login("+77000000002");
        String root = "/api/v1/partner/partners/" + partner + "/leisure";
        String events = t.body(t.send("GET", root + "/events?product=EVENTS", owner, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(events, "$[*].categoryCode")).isNotEmpty().isSubsetOf("CINEMA", "CONCERT", "THEATER", "EXHIBITION", "SPORT", "FESTIVAL", "SHOW", "STANDUP", "KIDS_SHOW");
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", root + "/events?product=LEISURE", owner, null, null)), "$")).isNotNull();
        assertThat((List<String>) JsonPath.read(t.body(t.send("GET", root + "/events?product=LEISURE", owner, null, null)), "$[*].categoryCode")).doesNotContain("CINEMA");
        t.send("GET", root + "/stats?product=EVENTS", owner, null, null).andExpect(status().isOk());
        t.send("GET", root + "/orders?product=LEISURE", owner, null, null).andExpect(status().isOk());
        t.send("GET", root + "/events?product=NOPE", owner, null, null).andExpect(status().isBadRequest());
    }

    @Test
    void gateControllerScansOnlyAssignedSessionsAndAdmitsOnce() throws Exception {
        UUID partner = db.queryForObject("select partner_id from marketplace.leisure_venues where slug = 'demo-leisure-cinema'", UUID.class);
        String owner = t.login("+77000000002");
        String gate = t.login("+77000000003");
        String alice = t.login("+77000000541");
        String stranger = t.login("+77000000542");
        UUID film = t.event("Демо-фильм");
        UUID session = t.firstSession(film);
        UUID std = t.ticketType(film, "Стандарт");
        String hold = t.body(t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice,
                "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "E", 3) + "\"]}]}", null).andExpect(status().isCreated()));
        String order = t.body(t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(hold, "$.id") + "\",\"paymentMethod\":\"TEST_CARD\",\"ageConfirmed\":true}",
                "gate-test-key-0000000001").andExpect(status().is2xxSuccessful()));
        String qr = JsonPath.read(order, "$.tickets[0].qr");
        db.update("update marketplace.leisure_sessions set starts_at = now() + interval '30 minutes', ends_at = now() + interval '2 hours' where id = ?", session);
        String scan = "/api/v1/executor/leisure/checkins";
        String body = "{\"code\":\"" + qr + "\"}";
        // not assigned: refused without any detail of the ticket
        t.send("POST", scan, gate, body, null).andExpect(status().isOk()).andExpect(jsonPath("$.result").value("ACCESS_DENIED")).andExpect(jsonPath("$.eventTitle").doesNotExist());
        // the organiser assigns a gate controller; an unrelated user cannot assign
        String assign = "/api/v1/partner/partners/" + partner + "/leisure/sessions/" + session + "/assignments";
        t.send("POST", assign, stranger, "{\"phone\":\"+77000000003\",\"role\":\"GATE\"}", null).andExpect(status().is4xxClientError());
        String assignment = t.body(t.send("POST", assign, owner, "{\"phone\":\"+77000000003\",\"role\":\"GATE\"}", null).andExpect(status().is2xxSuccessful()));
        // an offer alone is not access
        t.send("POST", scan, gate, body, null).andExpect(jsonPath("$.result").value("ACCESS_DENIED"));
        t.send("POST", "/api/v1/executor/leisure/assignments/" + JsonPath.read(assignment, "$.id") + "/step", gate, "{\"step\":\"ACCEPT\"}", null).andExpect(status().isOk());
        t.send("POST", scan, stranger, body, null).andExpect(jsonPath("$.result").value("ACCESS_DENIED"));
        t.send("POST", scan, gate, "{\"code\":\"KT1.not-a-code\"}", null).andExpect(jsonPath("$.result").value("INVALID"));
        t.send("POST", scan, gate, body, null).andExpect(status().isOk()).andExpect(jsonPath("$.result").value("ADMITTED")).andExpect(jsonPath("$.admitted").value(true));
        t.send("POST", scan, gate, body, null).andExpect(jsonPath("$.result").value("DUPLICATE")).andExpect(jsonPath("$.admitted").value(false));
        assertThat(db.queryForObject("select count(*) from transactions.leisure_checkins where result = 'ADMITTED' and session_id = ?", Integer.class, session)).isEqualTo(1);
        assertThat(db.queryForObject("select count(*) from transactions.leisure_checkins where result = 'ACCESS_DENIED'", Integer.class)).isGreaterThanOrEqualTo(3);
    }

    @Test
    void globalSearchRoutesEventsAndLeisureApart() throws Exception {
        String[][] cases = {
                {"концерт", "EVENTS"}, {"Театр", "EVENTS"}, {"кино на вечер", "EVENTS"}, {"cinema", "EVENTS"}, {"футбол матч", "EVENTS"},
                {"квест", "LEISURE"}, {"боулинг", "LEISURE"}, {"VR клуб", "LEISURE"}, {"караоке", "LEISURE"}, {"мастер-класс", "LEISURE"}, {"картинг", "LEISURE"},
                {"zzzzqq", "NONE"}};
        for (String[] c : cases) {
            String r = t.body(t.send("GET", "/api/v1/search/route?q=" + c[0], null, null, null).andExpect(status().isOk()));
            assertThat((String) JsonPath.read(r, "$.route")).as(c[0]).isEqualTo(c[1]);
        }
        // a title found only in a catalogue routes by content
        assertThat((String) JsonPath.read(t.body(t.send("GET", "/api/v1/search/route?q=Ночной экспресс", null, null, null)), "$.route")).isEqualTo("EVENTS");
        assertThat((String) JsonPath.read(t.body(t.send("GET", "/api/v1/search/route", null, null, null).andExpect(status().isOk())), "$.route")).isEqualTo("NONE");
    }

    @Test
    void eventsOperationsGrantSeparatesTheTwoControlCenters() throws Exception {
        UUID film = t.event("Демо-фильм");
        String eventsAdminLogin = t.loginBody("+77000000542");
        UUID eventsAdmin = LeisureTestSupport.subject(eventsAdminLogin);
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'EVENTS_OPERATIONS', 'synthetic DEV admin')", eventsAdmin);
        String token = t.refreshed(eventsAdminLogin);
        String base = "/api/v1/admin/leisure";
        t.send("GET", base + "/summary?product=EVENTS", token, null, null).andExpect(status().isOk());
        t.send("GET", base + "/events?product=EVENTS", token, null, null).andExpect(status().isOk());
        t.send("GET", base + "/orders?product=EVENTS", token, null, null).andExpect(status().isOk());
        t.send("GET", base + "/tickets?product=EVENTS", token, null, null).andExpect(status().isOk());
        t.send("GET", base + "/payments?product=EVENTS", token, null, null).andExpect(status().isOk());
        t.send("GET", base + "/audit", token, null, null).andExpect(status().isOk()); // shared journal
        // the Leisure control center and Leisure data stay closed to an Events administrator
        t.send("GET", base + "/summary?product=LEISURE", token, null, null).andExpect(status().isForbidden());
        t.send("GET", base + "/summary", token, null, null).andExpect(status().isForbidden());
        t.send("GET", base + "/orders?product=LEISURE", token, null, null).andExpect(status().isForbidden());
        t.send("GET", base + "/payments?product=LEISURE", token, null, null).andExpect(status().isForbidden());
        UUID bowling = db.queryForObject("select id from marketplace.leisure_events where category_code = 'BOWLING' limit 1", UUID.class);
        t.send("POST", base + "/events/" + bowling + "/decision", token, "{\"decision\":\"BLOCK\",\"reason\":\"x\"}", null).andExpect(status().isForbidden());
        t.send("PATCH", base + "/categories/QUEST", token, "{\"enabled\":false}", null).andExpect(status().isForbidden());
        // but an event of its own product is theirs to moderate
        t.send("POST", base + "/events/" + film + "/decision", token, "{\"decision\":\"BLOCK\",\"reason\":\"проверка гранта\"}", null).andExpect(status().isOk());
        // a Leisure administrator cannot reach Events
        String leisureLogin = t.loginBody("+77000000003");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'LEISURE_OPERATIONS', 'synthetic DEV admin')", LeisureTestSupport.subject(leisureLogin));
        String leisure = t.refreshed(leisureLogin);
        t.send("GET", base + "/summary?product=LEISURE", leisure, null, null).andExpect(status().isOk());
        t.send("GET", base + "/summary?product=EVENTS", leisure, null, null).andExpect(status().isForbidden());
        t.send("POST", base + "/events/" + film + "/decision", leisure, "{\"decision\":\"UNBLOCK\"}", null).andExpect(status().isForbidden());
    }

    @Test
    @SuppressWarnings("unchecked")
    void organiserSalesReportShowsOwnEventsOnly() throws Exception {
        UUID partnerA = db.queryForObject("select partner_id from marketplace.leisure_venues where slug = 'demo-leisure-cinema'", UUID.class);
        String ownerA = t.login("+77000000002");
        String ownerB = t.login("+77000000003");
        String alice = t.login("+77000000541");
        UUID film = t.event("Демо-фильм");
        UUID session = t.firstSession(film);
        UUID std = t.ticketType(film, "Стандарт");
        String hold = t.body(t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice,
                "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "C", 4) + "\",\"" + t.seat(session, "C", 5) + "\"]}]}", null).andExpect(status().isCreated()));
        t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(hold, "$.id") + "\",\"paymentMethod\":\"TEST_CARD\",\"ageConfirmed\":true}",
                "report-test-key-000000001").andExpect(status().is2xxSuccessful());
        String path = "/api/v1/partner/partners/" + partnerA + "/leisure/reports/sales";
        String report = t.body(t.send("GET", path + "?product=EVENTS&days=30", ownerA, null, null).andExpect(status().isOk()));
        assertThat((List<String>) JsonPath.read(report, "$[*].product")).isNotEmpty().containsOnly("EVENTS");
        int i = ((List<String>) JsonPath.read(report, "$[*].eventId")).indexOf(film.toString());
        assertThat(i).isGreaterThanOrEqualTo(0);
        assertThat(((Number) JsonPath.read(report, "$[" + i + "].tickets")).longValue()).isEqualTo(2L);
        assertThat(((Number) JsonPath.read(report, "$[" + i + "].revenueMinor")).longValue()).isEqualTo(400000L);
        assertThat(((Number) JsonPath.read(report, "$[" + i + "].upcomingSold")).longValue()).isGreaterThanOrEqualTo(2L);
        assertThat((List<?>) JsonPath.read(t.body(t.send("GET", path + "?product=LEISURE", ownerA, null, null).andExpect(status().isOk())), "$[?(@.eventId=='" + film + "')]")).isEmpty();
        // another organiser cannot read this organiser's report
        t.send("GET", path, ownerB, null, null).andExpect(status().is4xxClientError());
        t.send("GET", path + "?product=NOPE", ownerA, null, null).andExpect(status().isBadRequest());
    }

    @Test
    @SuppressWarnings("unchecked")
    void complaintsFollowTheProductOfTheirOrder() throws Exception {
        String alice = t.login("+77000000541");
        UUID film = t.event("Демо-фильм");
        UUID session = t.firstSession(film);
        UUID std = t.ticketType(film, "Стандарт");
        String hold = t.body(t.send("POST", "/api/v1/leisure/sessions/" + session + "/holds", alice,
                "{\"lines\":[{\"ticketTypeId\":\"" + std + "\",\"seatIds\":[\"" + t.seat(session, "B", 2) + "\"]}]}", null).andExpect(status().isCreated()));
        String order = t.body(t.send("POST", "/api/v1/leisure/orders", alice, "{\"holdId\":\"" + JsonPath.read(hold, "$.id") + "\",\"paymentMethod\":\"TEST_CARD\",\"ageConfirmed\":true}",
                "complaint-test-key-00001").andExpect(status().is2xxSuccessful()));
        UUID venue = db.queryForObject("select venue_id from marketplace.leisure_events where id = ?", UUID.class, film);
        String complaint = t.body(t.send("POST", "/api/v1/leisure/complaints", alice,
                "{\"venueId\":\"" + venue + "\",\"orderId\":\"" + JsonPath.read(order, "$.id") + "\",\"body\":\"Проблема со входом (синтетика)\"}", null).andExpect(status().isCreated()));
        String id = JsonPath.read(complaint, "$.id");
        String eventsLogin = t.loginBody("+77000000542");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'EVENTS_OPERATIONS', 'synthetic DEV admin')", LeisureTestSupport.subject(eventsLogin));
        String events = t.refreshed(eventsLogin);
        String leisureLogin = t.loginBody("+77000000003");
        db.update("INSERT INTO identity.admin_grants (user_id, permission, reason) VALUES (?, 'LEISURE_OPERATIONS', 'synthetic DEV admin')", LeisureTestSupport.subject(leisureLogin));
        String leisure = t.refreshed(leisureLogin);
        String base = "/api/v1/admin/leisure/complaints";
        assertThat((List<String>) JsonPath.read(t.body(t.send("GET", base + "?product=EVENTS", events, null, null).andExpect(status().isOk())), "$[*].id")).contains(id);
        assertThat((List<String>) JsonPath.read(t.body(t.send("GET", base + "?product=LEISURE", leisure, null, null).andExpect(status().isOk())), "$[*].id")).doesNotContain(id);
        t.send("GET", base + "?product=EVENTS", leisure, null, null).andExpect(status().isForbidden());
        t.send("POST", base + "/" + id + "/resolve", leisure, "{\"resolution\":\"не мой продукт\"}", null).andExpect(status().isForbidden());
        t.send("POST", base + "/" + id + "/resolve", events, "{\"resolution\":\"Проверено, вход исправлен\"}", null).andExpect(status().isNoContent());
    }
}
