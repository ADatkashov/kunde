package kz.kunde.analytics;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * TASK-041 / PRD 1.1 §19: closed catalog of business events and a minimization gate.
 * This is a contract only. Nothing here emits, stores or transmits events: analytics stays
 * disconnected until consent, residency, retention and processor gates are approved.
 */
public final class EventCatalog {
    public enum AccessClass { GENERAL, RESTRICTED }

    public record Definition(String name, AccessClass access, Set<String> required, Set<String> optional) {
        Set<String> allowed() {
            var all = new java.util.HashSet<>(required);
            all.addAll(optional);
            return all;
        }
    }

    /** Envelope fields every event carries; callers never pass them as domain properties. */
    public static final Set<String> ENVELOPE = Set.of("event_id", "event_name", "occurred_at", "schema_version",
            "actor_id", "session_id", "correlation_id", "locale", "app_version", "market");

    /** Names that must never appear as a property, even if a definition were widened by mistake. */
    private static final Set<String> FORBIDDEN_TOKENS = Set.of("query", "text", "note", "message", "prompt", "phone",
            "email", "address", "lat", "lon", "lng", "geo", "location", "name", "password", "otp", "token", "card",
            "pan", "cvv", "iban", "health", "child", "birth");

    /** Token match on snake_case parts (so latency_ms is fine, user_phone is not). */
    private static boolean forbidden(String key) {
        for (String token : key.toLowerCase(java.util.Locale.ROOT).split("[_\\W]+")) {
            if (FORBIDDEN_TOKENS.contains(token)) { return true; }
        }
        return false;
    }
    private static final Pattern SAFE_VALUE = Pattern.compile("[A-Za-z0-9_.:\\-]{1,64}");

    private static final Map<String, Definition> CATALOG = Map.ofEntries(
            def("registration_started", AccessClass.GENERAL, Set.of("method_class"), Set.of()),
            def("registration_completed", AccessClass.GENERAL, Set.of("method_class", "result"), Set.of()),
            def("authentication_result", AccessClass.GENERAL, Set.of("result_class", "device_class"), Set.of()),
            def("search_submitted", AccessClass.GENERAL, Set.of("category_scope", "filter_flags"), Set.of("region")),
            def("search_results_viewed", AccessClass.GENERAL, Set.of("result_count", "latency_ms", "partial"), Set.of()),
            def("search_result_selected", AccessClass.GENERAL, Set.of("listing_type", "category_id", "rank"), Set.of("listing_id")),
            def("category_discovered", AccessClass.GENERAL, Set.of("category_id", "source"), Set.of()),
            def("business_viewed", AccessClass.GENERAL, Set.of("category_id", "listing_id", "source"), Set.of()),
            def("service_viewed", AccessClass.GENERAL, Set.of("category_id", "listing_id", "source"), Set.of()),
            def("cart_created", AccessClass.GENERAL, Set.of("merchant_id", "item_count", "subtotal_band"), Set.of()),
            def("checkout_started", AccessClass.GENERAL, Set.of("merchant_id", "item_count", "subtotal_band"), Set.of()),
            def("payment_attempted", AccessClass.RESTRICTED, Set.of("amount", "currency", "method_class", "result_class"), Set.of()),
            def("payment_state_changed", AccessClass.RESTRICTED, Set.of("amount", "currency", "method_class", "result_class"), Set.of()),
            def("order_placed", AccessClass.RESTRICTED, Set.of("order_id", "category_id", "state", "fulfillment_type"), Set.of()),
            def("order_state_changed", AccessClass.RESTRICTED, Set.of("order_id", "category_id", "state", "fulfillment_type"), Set.of()),
            def("booking_created", AccessClass.RESTRICTED, Set.of("booking_id", "category_id", "state", "lead_time_band"), Set.of()),
            def("booking_state_changed", AccessClass.RESTRICTED, Set.of("booking_id", "category_id", "state", "lead_time_band"), Set.of()),
            def("cancellation_requested", AccessClass.RESTRICTED, Set.of("actor_class", "reason_code", "policy_version"), Set.of()),
            def("cancellation_completed", AccessClass.RESTRICTED, Set.of("actor_class", "reason_code", "policy_version", "outcome"), Set.of()),
            def("refund_requested", AccessClass.RESTRICTED, Set.of("amount", "currency", "reason_code"), Set.of()),
            def("refund_state_changed", AccessClass.RESTRICTED, Set.of("amount", "currency", "reason_code", "verified_state"), Set.of()),
            def("review_submitted", AccessClass.GENERAL, Set.of("rating", "category_id", "moderation_state"), Set.of()),
            def("support_case_opened", AccessClass.RESTRICTED, Set.of("category", "reason_code"), Set.of()),
            def("support_case_resolved", AccessClass.RESTRICTED, Set.of("category", "reason_code", "resolution_time_s"), Set.of()),
            def("ai_conversation_started", AccessClass.GENERAL, Set.of("entry_point", "feature_version"), Set.of()),
            def("ai_task_execution", AccessClass.RESTRICTED, Set.of("tool_class", "authorization_result", "duration_ms", "outcome", "cost_band"), Set.of()),
            def("ai_task_completed", AccessClass.RESTRICTED, Set.of("step_count", "completion_class", "confirmation_flag"), Set.of()));

    private static Map.Entry<String, Definition> def(String name, AccessClass access, Set<String> required, Set<String> optional) {
        return Map.entry(name, new Definition(name, access, required, optional));
    }

    private EventCatalog() {}

    public static Set<String> names() { return CATALOG.keySet(); }

    public static Definition definition(String name) { return CATALOG.get(name); }

    /** Returns every violation; an empty list means the event may be handed to a (future, approved) sink. */
    public static List<String> validate(String name, Map<String, Object> properties) {
        var violations = new ArrayList<String>();
        Definition def = name == null ? null : CATALOG.get(name);
        if (def == null) { return List.of("unknown event"); }
        Map<String, Object> props = properties == null ? Map.of() : properties;
        for (String required : def.required()) {
            if (!props.containsKey(required)) { violations.add("missing property: " + required); }
        }
        Set<String> allowed = def.allowed();
        for (var entry : props.entrySet()) {
            String key = entry.getKey();
            if (ENVELOPE.contains(key)) { violations.add("envelope field passed as property: " + key); }
            else if (forbidden(key)) { violations.add("forbidden property: " + key); }
            else if (!allowed.contains(key)) { violations.add("property not in schema: " + key); }
            Object value = entry.getValue();
            if (value instanceof String s && !SAFE_VALUE.matcher(s).matches()) {
                violations.add("free-text or oversized value for: " + key);
            } else if (value != null && !(value instanceof String) && !(value instanceof Number) && !(value instanceof Boolean)) {
                violations.add("unsupported value type for: " + key);
            }
        }
        return violations;
    }
}
