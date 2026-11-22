package kz.kunde.maps;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import kz.kunde.rides.RideMatching.Point;
import kz.kunde.rides.RideRouting;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * Contract tests: the adapter talks real HTTP to an in-process server that replays responses captured from the deployed DEV Maps Platform
 * (src/test/resources/maps). The live test against the real platform is {@link KundeMapsLiveTest}.
 */
class KundeMapsRideRoutingTest {
    private static final Point PICKUP = new Point(43.238194, 76.94498);
    private static final Point DESTINATION = new Point(43.25, 76.93);

    private final ObjectMapper json = new ObjectMapper();
    private final List<String> requests = new CopyOnWriteArrayList<>();
    private HttpServer server;

    @AfterEach
    void stop() {
        if (server != null) {
            server.stop(0);
        }
    }

    private static String fixture(String name) throws IOException {
        return Files.readString(Path.of("src/test/resources/maps", name), StandardCharsets.UTF_8);
    }

    private KundeMapsRideRouting serve(Function<HttpExchange, Reply> handler, String apiKey) throws IOException {
        server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        server.createContext("/", exchange -> {
            var body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            requests.add(exchange.getRequestMethod() + " " + exchange.getRequestURI() + " key="
                    + exchange.getRequestHeaders().getFirst("X-API-Key") + " " + body);
            var reply = handler.apply(exchange);
            var bytes = reply.body().getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(reply.status(), bytes.length == 0 ? -1 : bytes.length);
            if (bytes.length > 0) {
                exchange.getResponseBody().write(bytes);
            }
            exchange.close();
        });
        server.start();
        var url = "http://127.0.0.1:" + server.getAddress().getPort();
        return new KundeMapsRideRouting(new MapsProperties(true, url, url, apiKey, 3, 65_536), json);
    }

    private record Reply(int status, String body) {}

    @Test
    void routePostsTheDocumentedRequestAndParsesRealGeometry() throws Exception {
        var routing = serve(exchange -> new Reply(200, read("routes-200.json")), "secret-key");

        var route = routing.route(PICKUP, DESTINATION).orElseThrow();

        assertThat(route.distanceMeters()).isEqualTo(2508);
        assertThat(route.durationSeconds()).isEqualTo(207);
        assertThat(route.synthetic()).isFalse();
        // GeoJSON [lon, lat] is mapped to latitude/longitude, not swapped.
        assertThat(route.geometry().getFirst()).isEqualTo(new Point(43.238194, 76.94498));
        assertThat(route.geometry().getLast().latitude()).isBetween(43.0, 44.0);
        assertThat(requests).singleElement().satisfies(request -> {
            assertThat(request).startsWith("POST /v1/routes key=secret-key");
            var body = request.substring(request.indexOf('{'));
            assertThat(body).contains("\"mode\":\"driving\"").contains("\"alternatives\":false");
            assertThat(body).contains("\"origin\":{\"lat\":43.238194,\"lon\":76.94498}");
        });
    }

    private static String read(String name) {
        try {
            return fixture(name);
        } catch (IOException failure) {
            throw new IllegalStateException(failure);
        }
    }

    @Test
    void noApiKeyHeaderWhenNoneIsConfigured() throws Exception {
        var routing = serve(exchange -> new Reply(200, read("routes-200.json")), "");
        routing.route(PICKUP, DESTINATION);
        assertThat(requests.getFirst()).contains("key=null");
    }

    @Test
    void noMatchAnswersAreEmptyNotOutages() throws Exception {
        for (var error : List.of("no_route", "no_road_near_point", "outside_coverage", "points_too_close", "route_too_long")) {
            var routing = serve(exchange -> new Reply(error.startsWith("no_") ? 404 : 400, "{\"error\":\"" + error + "\"}"), "");
            assertThat(routing.route(PICKUP, DESTINATION)).as(error).isEmpty();
            server.stop(0);
        }
    }

    @Test
    void outagesQuotaAndAuthFailuresAreUnavailable() throws Exception {
        for (var status : List.of(401, 403, 429, 500, 502, 503, 504)) {
            var routing = serve(exchange -> new Reply(status, "{\"error\":\"x\"}"), "");
            assertThatExceptionOfType(RideRouting.Unavailable.class).as("status " + status)
                    .isThrownBy(() -> routing.route(PICKUP, DESTINATION));
            server.stop(0);
        }
    }

    @Test
    void malformedOrImplausibleRoutesAreUnavailableNeverGuessed() throws Exception {
        for (var body : List.of("not json", "{}", "{\"distance_m\":0,\"duration_s\":10,\"geometry\":{\"coordinates\":[[76,43],[77,43]]}}",
                "{\"distance_m\":100,\"duration_s\":10,\"geometry\":{\"coordinates\":[[76,43]]}}",
                "{\"distance_m\":100,\"duration_s\":10,\"geometry\":{\"coordinates\":[[76,43],[\"a\",1]]}}",
                "{\"distance_m\":100,\"duration_s\":10,\"geometry\":{\"coordinates\":[[76,143],[77,43]]}}",
                "{\"distance_m\":1e99,\"duration_s\":10,\"geometry\":{\"coordinates\":[[76,43],[77,43]]}}")) {
            var routing = serve(exchange -> new Reply(200, body), "");
            assertThatExceptionOfType(RideRouting.Unavailable.class).as(body)
                    .isThrownBy(() -> routing.route(PICKUP, DESTINATION));
            server.stop(0);
        }
    }

    @Test
    void oversizedResponsesAreRejected() throws Exception {
        var routing = serve(exchange -> new Reply(200, "{\"pad\":\"" + "x".repeat(70_000) + "\"}"), "");
        assertThatExceptionOfType(RideRouting.Unavailable.class).isThrownBy(() -> routing.route(PICKUP, DESTINATION));
    }

    @Test
    void aWarmingUpServiceIsRetriedOnce() throws Exception {
        var calls = new AtomicInteger();
        var routing = serve(exchange -> calls.incrementAndGet() == 1 ? new Reply(503, "{\"error\":\"busy\"}")
                : new Reply(200, read("routes-200.json")), "");
        assertThat(routing.route(PICKUP, DESTINATION)).isPresent();
        assertThat(calls).hasValue(2);
    }

    @Test
    void anUnreachableServiceIsUnavailable() throws Exception {
        var routing = serve(exchange -> new Reply(200, "{}"), "");
        server.stop(0);
        assertThatExceptionOfType(RideRouting.Unavailable.class).isThrownBy(() -> routing.route(PICKUP, DESTINATION));
    }

    @Test
    void failuresNeverLeakCoordinatesOrQueriesIntoMessages() throws Exception {
        var routing = serve(exchange -> new Reply(500, "{}"), "key");
        try {
            routing.route(PICKUP, DESTINATION);
        } catch (RideRouting.Unavailable failure) {
            assertThat(String.valueOf(failure.getCause().getMessage())).doesNotContain("43.2").doesNotContain("76.9").doesNotContain("key");
        }
        try {
            routing.geocode("секретный адрес", Locale.forLanguageTag("ru"));
        } catch (RideRouting.Unavailable failure) {
            assertThat(String.valueOf(failure.getCause().getMessage())).doesNotContain("секретный");
        }
    }

    @Test
    void geocodeSendsEncodedQueryAndLanguageAndMapsRealResults() throws Exception {
        var routing = serve(exchange -> new Reply(200, read("search-200.json")), "");

        var places = routing.geocode("улица Абая 10", Locale.forLanguageTag("kk"));

        assertThat(places).isNotEmpty().hasSizeLessThanOrEqualTo(10);
        assertThat(places).allSatisfy(place -> {
            assertThat(place.address()).isNotBlank();
            assertThat(place.point().latitude()).isBetween(40.0, 56.0);
        });
        assertThat(requests.getFirst()).startsWith("GET /v1/search?q=%D1%83%D0%BB%D0%B8%D1%86%D0%B0+%D0%90%D0%B1%D0%B0%D1%8F+10&lang=kk");
    }

    @Test
    void unknownLanguageFallsBackToRussian() throws Exception {
        var routing = serve(exchange -> new Reply(200, "{\"results\":[]}"), "");
        assertThat(routing.geocode("abc", Locale.GERMAN)).isEmpty();
        assertThat(requests.getFirst()).contains("lang=ru");
    }

    @Test
    void geocodeSkipsBadRecordsButKeepsGoodOnes() throws Exception {
        var body = """
                {"results":[{"name":"A","lat":43.2,"lon":76.9},{"name":"B","lat":999,"lon":76.9},{"name":"","lat":43.2,"lon":76.9},
                {"name":"C","lat":"x","lon":1},{"name":"D","locality":"Алматы","lat":43.3,"lon":76.8}]}""";
        var routing = serve(exchange -> new Reply(200, body), "");
        assertThat(routing.geocode("abc", Locale.ENGLISH)).extracting(RideRouting.Place::address)
                .containsExactly("A", "D, Алматы");
    }

    @Test
    void geocodeBadRequestIsNoMatchAndOutageIsUnavailable() throws Exception {
        var routing = serve(exchange -> new Reply(400, "{\"error\":\"q\"}"), "");
        assertThat(routing.geocode("a", Locale.ENGLISH)).isEmpty();
        server.stop(0);
        var down = serve(exchange -> new Reply(429, "{}"), "");
        assertThatExceptionOfType(RideRouting.Unavailable.class).isThrownBy(() -> down.geocode("abc", Locale.ENGLISH));
    }

    @Test
    void reverseGeocodeNeverInventsAnAddress() throws Exception {
        // Real nearby places from DEV: none of them carries an address, so the honest answer is "not found".
        var routing = serve(exchange -> new Reply(200, read("places-200.json")), "");
        assertThat(routing.reverseGeocode(new Point(43.238, 76.945), Locale.ENGLISH)).isEmpty();
        assertThat(requests.getFirst()).contains("GET /v1/places?lat=43.238&lon=76.945&radius=60&limit=5");
    }

    @Test
    void reverseGeocodeReturnsTheFirstRealPlaceWithAnAddress() throws Exception {
        var body = """
                {"places":[{"name":"Cafe","address":null,"lat":43.2,"lon":76.9},
                {"name":"Bank","address":"улица Абая 10","lat":43.2001,"lon":76.9001}]}""";
        var routing = serve(exchange -> new Reply(200, body), "");
        var place = routing.reverseGeocode(new Point(43.2, 76.9), Locale.ENGLISH).orElseThrow();
        assertThat(place.address()).isEqualTo("Bank, улица Абая 10");
        assertThat(place.point()).isEqualTo(new Point(43.2001, 76.9001));
    }

    @Test
    void onlyHttpsOrLoopbackUrlsWithoutCredentialsAreAccepted() {
        for (var bad : List.of("", "ftp://maps.example", "http://maps.example", "https://user:pw@maps.example", "maps.example")) {
            assertThatIllegalStateException().as(bad).isThrownBy(() -> KundeMapsRideRouting.base(bad, "x"));
        }
        assertThat(KundeMapsRideRouting.base("https://maps.example", "x").getHost()).isEqualTo("maps.example");
        assertThat(KundeMapsRideRouting.base("http://127.0.0.1:9", "x").getPort()).isEqualTo(9);
    }
}
