package kz.kunde.rides;

import static org.hamcrest.Matchers.greaterThan;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.sun.net.httpserver.HttpServer;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

/**
 * Taxi quotes over the real HTTP adapter to the KUNDE Maps Platform. The Maps side is an in-process HTTP server that replays responses
 * captured from the deployed DEV platform (src/test/resources/maps); the whole Rides stack (security, tariff, database) is real. Maps
 * supplies distance and time only - the fare is computed by the Rides tariff.
 */
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true",
        "app.auth.phone.secret=synthetic-rides-only-for-integration-tests",
        "app.rides.enabled=true",
        "app.rides.consumer-enabled=true",
        "app.maps.enabled=true",
        "app.maps.timeout-seconds=5",
        "app.rides.pricing.tariffs.economy.version=maps-v1",
        "app.rides.pricing.tariffs.economy.base-kzt=200",
        "app.rides.pricing.tariffs.economy.per-kilometer-kzt=80",
        "app.rides.pricing.tariffs.economy.per-minute-kzt=10",
        "app.rides.pricing.tariffs.economy.minimum-kzt=400",
        "app.rides.pricing.tariffs.economy.fixed-fee-kzt=0"
})
@AutoConfigureMockMvc
@Transactional
class RideQuoteMapsIntegrationTest {
    private static final String QUOTE = """
            {"rideClass":"ECONOMY","pickup":{"latitude":43.238194,"longitude":76.94498},
             "destination":{"latitude":43.25,"longitude":76.93}}
            """;
    private static HttpServer maps;
    private static final AtomicReference<Integer> routeStatus = new AtomicReference<>(200);
    private static final AtomicReference<String> routeBody = new AtomicReference<>();
    private static final AtomicInteger routeCalls = new AtomicInteger();

    @Autowired MockMvc http;

    @BeforeAll
    static void startMaps() throws Exception {
        maps = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        maps.createContext("/v1/routes", exchange -> {
            routeCalls.incrementAndGet();
            exchange.getRequestBody().readAllBytes();
            reply(exchange, routeStatus.get(), routeBody.get());
        });
        maps.createContext("/v1/search", exchange -> reply(exchange, 200, resource("search-200.json")));
        maps.start();
    }

    @AfterAll
    static void stopMaps() {
        maps.stop(0);
    }

    @DynamicPropertySource
    static void mapsUrls(DynamicPropertyRegistry registry) throws Exception {
        if (maps == null) {
            startMaps();
        }
        var base = "http://127.0.0.1:" + maps.getAddress().getPort();
        registry.add("app.maps.routing-url", () -> base);
        registry.add("app.maps.search-url", () -> base);
    }

    @BeforeEach
    void reset() throws Exception {
        routeStatus.set(200);
        routeBody.set(resource("routes-200.json"));
        routeCalls.set(0);
    }

    private static String resource(String name) throws java.io.IOException {
        return Files.readString(Path.of("src/test/resources/maps", name), StandardCharsets.UTF_8);
    }

    private static void reply(com.sun.net.httpserver.HttpExchange exchange, int status, String body) throws java.io.IOException {
        var bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }

    @Test
    void quoteIsPricedByTheRidesTariffFromARealMapsRoute() throws Exception {
        // 2508 m and 207 s from the captured DEV route: (200 + 80 * 2.508 + 10 * 3.45) = 435.14. Maps never supplies a price.
        http.perform(post("/api/v1/rides/quotes").with(customer("maps-passenger"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.estimateKzt").value(435.14))
                .andExpect(jsonPath("$.tariffVersion").value("maps-v1"))
                .andExpect(jsonPath("$.distanceMeters").value(2508))
                .andExpect(jsonPath("$.durationSeconds").value(207))
                .andExpect(jsonPath("$.synthetic").value(false));
    }

    @Test
    void routePreviewReturnsRealGeometryWithoutAPrice() throws Exception {
        http.perform(post("/api/v1/rides/route-preview").with(customer("maps-passenger"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pickup\":{\"latitude\":43.238194,\"longitude\":76.94498},"
                                + "\"destination\":{\"latitude\":43.25,\"longitude\":76.93}}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.distanceMeters").value(2508))
                .andExpect(jsonPath("$.durationSeconds").value(207))
                .andExpect(jsonPath("$.synthetic").value(false))
                .andExpect(jsonPath("$.geometry[0].latitude").value(43.238194))
                .andExpect(jsonPath("$.geometry[0].longitude").value(76.94498))
                .andExpect(jsonPath("$.estimateKzt").doesNotExist());
    }

    @Test
    void addressSearchReturnsRealPlaces() throws Exception {
        http.perform(post("/api/v1/rides/address-search").with(customer("maps-passenger"))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"query\":\"улица Абая 10\",\"language\":\"ru\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(greaterThan(0))))
                .andExpect(jsonPath("$[0].address").isNotEmpty())
                .andExpect(jsonPath("$[0].point.latitude").isNumber());
    }

    @Test
    void noRoadMeansNoQuote() throws Exception {
        routeStatus.set(404);
        routeBody.set("{\"error\":\"no_route\"}");
        http.perform(post("/api/v1/rides/quotes").with(customer("maps-passenger"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("RIDE_ROUTE_NOT_FOUND"));
    }

    @Test
    void mapsOutageFailsClosedWithoutAFallbackPrice() throws Exception {
        routeStatus.set(500);
        routeBody.set("{\"error\":\"routing_unavailable\"}");
        http.perform(post("/api/v1/rides/quotes").with(customer("maps-passenger"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("RIDES_ROUTING_UNAVAILABLE"));
    }

    @Test
    void aMalformedMapsRouteIsNeverQuoted() throws Exception {
        routeBody.set("{\"distance_m\":0}");
        http.perform(post("/api/v1/rides/quotes").with(customer("maps-passenger"))
                        .contentType(MediaType.APPLICATION_JSON).content(QUOTE))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("RIDES_ROUTING_UNAVAILABLE"));
    }

    private static RequestPostProcessor customer(String subject) {
        return jwt().jwt(token -> token.issuer("https://identity.example.test").subject(subject)
                .claim("typ", "Bearer").claim("azp", "kunde-consumer").claim("scope", "kunde.consumer"));
    }
}
