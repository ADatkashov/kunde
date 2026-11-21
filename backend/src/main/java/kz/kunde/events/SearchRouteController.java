package kz.kunde.events;

import java.text.Normalizer;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import kz.kunde.leisure.LeisureCatalogService;
import kz.kunde.leisure.LeisureCatalogService.Search;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Global search routing for the Super App: a ticketed dated event (concert, theatre, cinema, sport, festival) belongs to Events, a bookable
 * activity (quest, bowling, VR, karaoke, karting, workshop) to Leisure. A keyword names the category unambiguously; otherwise the real catalogues
 * decide by what they contain. The answer only routes; the lists themselves come from the two catalogue APIs over the one engine.
 */
@RestController
@RequestMapping("/api/v1/search")
public class SearchRouteController {
    public record Route(String query, String route, String category, long events, long leisure) {}

    /** Keyword stems (lower case, ru/kk/en) to category code. The product follows from the category, never from the keyword. */
    private static final Map<String, String> KEYWORDS = new LinkedHashMap<>();
    static {
        for (String k : List.of("концерт", "concert", "gig", "джаз", "jazz")) { KEYWORDS.put(k, "CONCERT"); }
        for (String k : List.of("театр", "спектакл", "theatre", "theater", "play", "театрл")) { KEYWORDS.put(k, "THEATER"); }
        for (String k : List.of("кино", "фильм", "киносеанс", "cinema", "movie", "film")) { KEYWORDS.put(k, "CINEMA"); }
        for (String k : List.of("спорт", "матч", "футбол", "хоккей", "match", "football", "sport")) { KEYWORDS.put(k, "SPORT"); }
        for (String k : List.of("фестивал", "festival")) { KEYWORDS.put(k, "FESTIVAL"); }
        for (String k : List.of("шоу", "show", "цирк", "circus")) { KEYWORDS.put(k, "SHOW"); }
        for (String k : List.of("стендап", "стэндап", "stand-up", "standup")) { KEYWORDS.put(k, "STANDUP"); }
        for (String k : List.of("выставк", "көрме", "exhibition")) { KEYWORDS.put(k, "EXHIBITION"); }
        for (String k : List.of("квест", "quest", "escape")) { KEYWORDS.put(k, "QUEST"); }
        for (String k : List.of("боулинг", "bowling")) { KEYWORDS.put(k, "BOWLING"); }
        for (String k : List.of("vr", "вр ", "виртуал", "virtual", "игровой клуб")) { KEYWORDS.put(k, "GAMING_VR"); }
        for (String k : List.of("караоке", "karaoke")) { KEYWORDS.put(k, "KARAOKE"); }
        for (String k : List.of("картинг", "karting", "go-kart")) { KEYWORDS.put(k, "KARTING"); }
        for (String k : List.of("лазертаг", "лазер", "laser")) { KEYWORDS.put(k, "LASER_TAG"); }
        for (String k : List.of("батут", "trampoline")) { KEYWORDS.put(k, "TRAMPOLINE"); }
        for (String k : List.of("бильярд", "billiard", "pool")) { KEYWORDS.put(k, "BILLIARDS"); }
        for (String k : List.of("мастер-класс", "мастер класс", "мастер-кл", "workshop", "masterclass")) { KEYWORDS.put(k, "MASTERCLASS"); }
        for (String k : List.of("скалодром", "climbing")) { KEYWORDS.put(k, "CLIMBING"); }
        for (String k : List.of("пейнтбол", "paintball")) { KEYWORDS.put(k, "PAINTBALL"); }
        for (String k : List.of("настольн", "board game")) { KEYWORDS.put(k, "BOARD_GAMES"); }
        for (String k : List.of("экскурс", "tour", "excursion")) { KEYWORDS.put(k, "EXCURSION"); }
    }

    private final LeisureCatalogService catalog;

    public SearchRouteController(LeisureCatalogService catalog) { this.catalog = catalog; }

    @GetMapping("/route")
    ResponseEntity<Route> route(@RequestParam(defaultValue = "") String q) {
        String text = Normalizer.normalize(q == null ? "" : q, Normalizer.Form.NFKC).strip().toLowerCase(Locale.ROOT);
        if (text.isEmpty() || text.length() > 80) { return ok(new Route("", "NONE", null, 0, 0)); }
        String padded = " " + text + " ";
        String category = null;
        for (var e : KEYWORDS.entrySet()) {
            if (padded.contains(e.getKey()) && (e.getKey().length() > 2 || padded.contains(" " + e.getKey().strip() + " "))) { category = e.getValue(); break; }
        }
        long events = count(text, "EVENTS");
        long leisure = count(text, "LEISURE");
        if (category != null) {
            return ok(new Route(text, eventsCategory(category) ? "EVENTS" : "LEISURE", category, events, leisure));
        }
        String route = events > 0 && leisure > 0 ? "BOTH" : events > 0 ? "EVENTS" : leisure > 0 ? "LEISURE" : "NONE";
        return ok(new Route(text, route, null, events, leisure));
    }

    private static boolean eventsCategory(String c) {
        return List.of("CINEMA", "CONCERT", "THEATER", "EXHIBITION", "SPORT", "FESTIVAL", "SHOW", "STANDUP", "KIDS_SHOW").contains(c);
    }

    private long count(String text, String product) {
        return catalog.search(new Search(text, null, null, null, null, null, null, null, null, null, false, null, null, null, null, null, "time", null, 50, 0), product).size();
    }

    private static <T> ResponseEntity<T> ok(T body) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body); }
}
