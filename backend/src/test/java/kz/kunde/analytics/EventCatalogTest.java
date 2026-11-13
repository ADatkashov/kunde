package kz.kunde.analytics;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;

class EventCatalogTest {
    @Test
    void catalogContainsExactlyThePrdEvents() {
        assertThat(EventCatalog.names()).hasSize(27).contains("search_submitted", "payment_state_changed",
                "ai_task_completed", "registration_started", "service_viewed");
    }

    @Test
    void validEventPasses() {
        assertThat(EventCatalog.validate("search_results_viewed",
                Map.of("result_count", 3, "latency_ms", 42, "partial", false))).isEmpty();
        assertThat(EventCatalog.validate("search_submitted",
                Map.of("category_scope", "cleaning", "filter_flags", "none", "region", "almaty"))).isEmpty();
    }

    @Test
    void unknownEventMissingAndExtraPropertiesAreRejected() {
        assertThat(EventCatalog.validate("made_up", Map.of())).containsExactly("unknown event");
        assertThat(EventCatalog.validate(null, Map.of())).containsExactly("unknown event");
        assertThat(EventCatalog.validate("category_discovered", Map.of("category_id", "c1")))
                .containsExactly("missing property: source");
        assertThat(EventCatalog.validate("category_discovered", Map.of("category_id", "c1", "source", "home", "extra", "x")))
                .containsExactly("property not in schema: extra");
    }

    @Test
    void personalDataFreeTextAndEnvelopeFieldsAreRejected() {
        var bad = Map.<String, Object>of("category_scope", "a", "filter_flags", "b",
                "query", "ремонт", "phone", "+7700", "address", "x", "locale", "ru");
        assertThat(EventCatalog.validate("search_submitted", bad)).contains(
                "forbidden property: query", "forbidden property: phone", "forbidden property: address",
                "envelope field passed as property: locale");
        assertThat(EventCatalog.validate("category_discovered",
                Map.of("category_id", "ремонт квартир, ул. Абая 1", "source", "home")))
                .containsExactly("free-text or oversized value for: category_id");
        assertThat(EventCatalog.validate("category_discovered",
                Map.of("category_id", "c1", "source", new Object())))
                .containsExactly("unsupported value type for: source");
    }

    @Test
    void forbiddenNamesAreMatchedByTokenNotSubstring() {
        var base = Map.<String, Object>of("category_id", "c1", "source", "home");
        for (String key : new String[] {"user_phone", "geo_lat", "email", "card_pan", "Address"}) {
            var props = new java.util.HashMap<>(base);
            props.put(key, "x");
            assertThat(EventCatalog.validate("category_discovered", props)).contains("forbidden property: " + key);
        }
        assertThat(EventCatalog.validate("search_results_viewed",
                Map.of("result_count", 1, "latency_ms", 5, "partial", true))).isEmpty();
    }

    @Test
    void financialAndOperationalEventsAreRestricted() {
        assertThat(EventCatalog.definition("payment_attempted").access()).isEqualTo(EventCatalog.AccessClass.RESTRICTED);
        assertThat(EventCatalog.definition("search_submitted").access()).isEqualTo(EventCatalog.AccessClass.GENERAL);
        assertThat(EventCatalog.names().stream().map(EventCatalog::definition)
                .flatMap(d -> d.required().stream())).noneMatch(p -> p.matches("(?i).*(query|phone|email|address|prompt).*"));
    }
}
