package kz.kunde.maps;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import kz.kunde.platform.geo.Point;
import kz.kunde.platform.geo.RoutingProvider;

/**
 * {@link RoutingProvider} over the KUNDE Maps Platform (Search and Routing APIs of the kunde-maps repository). It owns no routing engine and no
 * map data: it only speaks the documented HTTP contracts.
 *
 * <ul>
 *   <li>route: {@code POST /v1/routes} (driving). A route is OpenStreetMap road distance and typical time without traffic; the Rides
 *       backend prices it with its own tariff, this class never produces a price.</li>
 *   <li>geocode: {@code GET /v1/search}.</li>
 *   <li>reverse geocode: the Maps API has no reverse geocoder, so this answers only with a real place that has an address within
 *       {@value #REVERSE_RADIUS_METERS} m, else nothing. Nothing is guessed.</li>
 * </ul>
 *
 * Coordinates and queries are never logged and never put into exception messages. A provider failure (timeout, quota, 5xx, malformed
 * answer) is {@link RoutingProvider.Unavailable}; "no match" answers (no road, out of coverage, too close) are empty results.
 */
public final class KundeMapsRideRouting implements RoutingProvider {
    static final int REVERSE_RADIUS_METERS = 60;
    private static final int MAX_PLACES = 10;
    private static final int MAX_ROUTE_POINTS = 20_000;
    private static final Set<String> NO_MATCH_ERRORS = Set.of("no_route", "no_road_near_point", "outside_coverage",
            "points_too_close", "route_too_long");
    private static final Set<String> LANGUAGES = Set.of("ru", "kk", "en");

    private final URI routingBase;
    private final URI searchBase;
    private final String apiKey;
    private final Duration timeout;
    private final int maxBytes;
    private final HttpClient http;
    private final ObjectMapper json;

    public KundeMapsRideRouting(MapsProperties properties, ObjectMapper json) {
        this.routingBase = base(properties.routingUrl(), "app.maps.routing-url");
        this.searchBase = base(properties.searchUrl(), "app.maps.search-url");
        this.apiKey = properties.apiKey();
        this.timeout = Duration.ofSeconds(properties.timeoutSeconds());
        this.maxBytes = properties.maxResponseBytes();
        this.json = json;
        this.http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(Math.min(10, properties.timeoutSeconds())))
                .followRedirects(HttpClient.Redirect.NEVER).build();
    }

    /** HTTPS only, no credentials in the URL; plain HTTP is allowed solely for loopback (tests and local development). */
    static URI base(String value, String name) {
        URI uri;
        try {
            uri = URI.create(value);
        } catch (IllegalArgumentException invalid) {
            throw new IllegalStateException(name + " must be an absolute URL");
        }
        var host = uri.getHost();
        var loopback = host != null && (host.equals("localhost") || host.equals("127.0.0.1") || host.equals("[::1]"));
        var scheme = uri.getScheme();
        if (host == null || uri.getUserInfo() != null || scheme == null
                || !(scheme.equals("https") || (scheme.equals("http") && loopback))) {
            throw new IllegalStateException(name + " must be an HTTPS URL without credentials");
        }
        return uri;
    }

    @Override
    public Optional<Route> route(Point pickup, Point destination) {
        var body = """
                {"origin":{"lat":%s,"lon":%s},"destination":{"lat":%s,"lon":%s},"mode":"driving","alternatives":false,"language":"ru"}"""
                .formatted(pickup.latitude(), pickup.longitude(), destination.latitude(), destination.longitude());
        var request = request(routingBase.resolve("/v1/routes"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8)).build();
        var answer = send(request);
        if (answer.status == 200) {
            return Optional.of(parseRoute(answer.body));
        }
        if ((answer.status == 400 || answer.status == 404) && noMatch(answer.body)) {
            return Optional.empty();
        }
        throw unavailable("routing", answer.status);
    }

    @Override
    public List<Place> geocode(String query, Locale locale) {
        var url = searchBase.resolve("/v1/search?q=" + enc(query) + "&lang=" + language(locale));
        var answer = send(request(url).GET().build());
        if (answer.status == 200) {
            return parsePlaces(answer.body, "results", false);
        }
        if (answer.status == 400) {
            return List.of();
        }
        throw unavailable("search", answer.status);
    }

    @Override
    public Optional<Place> reverseGeocode(Point point, Locale locale) {
        var url = searchBase.resolve("/v1/places?lat=" + point.latitude() + "&lon=" + point.longitude() + "&radius="
                + REVERSE_RADIUS_METERS + "&limit=5");
        var answer = send(request(url).GET().build());
        if (answer.status == 200) {
            return parsePlaces(answer.body, "places", true).stream().findFirst();
        }
        if (answer.status == 400) {
            return Optional.empty();
        }
        throw unavailable("places", answer.status);
    }

    private HttpRequest.Builder request(URI url) {
        var builder = HttpRequest.newBuilder(url).timeout(timeout).header("Accept", "application/json");
        if (!apiKey.isEmpty()) {
            builder.header("X-API-Key", apiKey);
        }
        return builder;
    }

    private record Answer(int status, JsonNode body) {}

    /** One request, plus one retry for a warming-up service (502/503) or a timeout. Never throws on a bad status. */
    private Answer send(HttpRequest request) {
        RuntimeException last = null;
        for (var attempt = 1; attempt <= 2; attempt++) {
            try {
                var response = http.send(request, HttpResponse.BodyHandlers.ofInputStream());
                var status = response.statusCode();
                var body = read(response.body());
                if ((status == 502 || status == 503) && attempt == 1) {
                    last = unavailable("service", status);
                    pause();
                    continue;
                }
                return new Answer(status, parse(body));
            } catch (java.net.http.HttpTimeoutException timedOut) {
                last = new Unavailable(new IOException("Maps request timed out"));
                if (attempt == 1) {
                    continue;
                }
            } catch (IOException failure) {
                last = new Unavailable(new IOException("Maps request failed"));
                break;
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                throw new Unavailable(new IOException("Maps request interrupted"));
            }
        }
        throw last == null ? new Unavailable(new IOException("Maps request failed")) : last;
    }

    private static void pause() {
        try {
            Thread.sleep(1500);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }

    private byte[] read(InputStream stream) throws IOException {
        try (stream) {
            var bytes = stream.readNBytes(maxBytes + 1);
            if (bytes.length > maxBytes) {
                throw new IOException("Maps response too large");
            }
            return bytes;
        }
    }

    private JsonNode parse(byte[] body) {
        if (body.length == 0) {
            return json.nullNode();
        }
        try {
            return json.readTree(body);
        } catch (IOException malformed) {
            return json.nullNode();
        }
    }

    private static boolean noMatch(JsonNode body) {
        return body != null && NO_MATCH_ERRORS.contains(body.path("error").asText(""));
    }

    private Route parseRoute(JsonNode body) {
        try {
            var distance = body.path("distance_m").asDouble(Double.NaN);
            var duration = body.path("duration_s").asDouble(Double.NaN);
            var coordinates = body.path("geometry").path("coordinates");
            if (!Double.isFinite(distance) || !Double.isFinite(duration) || distance < 1 || duration < 1
                    || distance > Integer.MAX_VALUE || duration > Integer.MAX_VALUE
                    || !coordinates.isArray() || coordinates.size() < 2 || coordinates.size() > MAX_ROUTE_POINTS) {
                throw new IllegalArgumentException("route");
            }
            var geometry = new ArrayList<Point>(coordinates.size());
            for (var pair : coordinates) {
                // GeoJSON order is [longitude, latitude].
                if (!pair.isArray() || pair.size() < 2 || !pair.get(0).isNumber() || !pair.get(1).isNumber()) {
                    throw new IllegalArgumentException("route");
                }
                geometry.add(new Point(pair.get(1).asDouble(), pair.get(0).asDouble()));
            }
            return new Route((int) Math.round(distance), (int) Math.max(1, Math.round(duration)), geometry, false);
        } catch (IllegalArgumentException malformed) {
            throw new Unavailable(new IOException("Maps returned a malformed route"));
        }
    }

    private List<Place> parsePlaces(JsonNode body, String field, boolean addressRequired) {
        var items = body.path(field);
        if (!items.isArray()) {
            throw new Unavailable(new IOException("Maps returned a malformed place list"));
        }
        var places = new ArrayList<Place>();
        for (var item : items) {
            if (places.size() == MAX_PLACES) {
                break;
            }
            try {
                var label = label(item, addressRequired);
                if (label.isEmpty() || !item.path("lat").isNumber() || !item.path("lon").isNumber()) {
                    continue;
                }
                places.add(new Place(label, new Point(item.path("lat").asDouble(), item.path("lon").asDouble())));
            } catch (IllegalArgumentException invalidPoint) {
                // A single bad record is skipped; the rest of the list is still real data.
            }
        }
        return List.copyOf(places);
    }

    private static String label(JsonNode item, boolean addressRequired) {
        var address = text(item, "address");
        var name = text(item, "name");
        if (addressRequired) {
            return address.isEmpty() ? "" : (name.isEmpty() || address.contains(name) ? address : name + ", " + address);
        }
        var locality = text(item, "locality");
        if (name.isEmpty()) {
            return address;
        }
        return locality.isEmpty() || name.contains(locality) ? name : name + ", " + locality;
    }

    private static String text(JsonNode item, String field) {
        var node = item.path(field);
        return node.isTextual() ? node.asText().strip() : "";
    }

    private static String language(Locale locale) {
        var language = locale == null ? "ru" : locale.getLanguage();
        return LANGUAGES.contains(language) ? language : "ru";
    }

    private static String enc(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static Unavailable unavailable(String what, int status) {
        return new Unavailable(new IOException("Maps " + what + " answered " + status));
    }
}
