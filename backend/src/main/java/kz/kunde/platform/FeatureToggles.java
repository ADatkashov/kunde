package kz.kunde.platform;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Runtime feature switches for marketplace products (incl. Groceries). The environment decides what is <em>allowed</em> (it also carries
 * the production guards); an administrator can only switch an allowed feature off or on again. A feature without a stored
 * switch follows the environment. Reads are cached for a few seconds, a write refreshes the cache at once.
 */
@Service
public class FeatureToggles {
    public enum Feature { AUTO, RIDES, DELIVERY, LEISURE, HEALTH, EDUCATION, GROCERIES, EVENTS, HOME_SERVICES, BEAUTY }

    public record Toggle(boolean enabled, long version, String reason, UUID updatedBy, OffsetDateTime updatedAt) {}

    public record FeatureView(Feature feature, boolean allowedByEnvironment, boolean enabled, boolean effective, long version,
            String reason, OffsetDateTime updatedAt) {}

    private static final long CACHE_MILLIS = 5_000;

    private final JdbcTemplate db;
    private final Map<Feature, FeatureGate> gates = new EnumMap<>(Feature.class);
    private final Clock clock;
    private volatile Map<Feature, Toggle> cache;
    private volatile long loadedAt;

    /**
     * Every {@link Feature} must be backed by exactly one {@link FeatureGate} supplied by its own domain, otherwise the
     * application does not start (fail closed). The platform kernel knows no domain settings class.
     */
    public FeatureToggles(JdbcTemplate db, List<FeatureGate> featureGates) {
        this.db = db;
        for (FeatureGate gate : featureGates) {
            if (gates.put(gate.feature(), gate) != null) {
                throw new IllegalStateException("More than one FeatureGate for " + gate.feature());
            }
        }
        for (Feature feature : Feature.values()) {
            if (!gates.containsKey(feature)) {
                throw new IllegalStateException("No FeatureGate for " + feature);
            }
        }
        this.clock = Clock.systemUTC();
    }

    public boolean allowedByEnvironment(Feature feature) {
        return gates.get(feature).allowedByEnvironment();
    }

    /** Whether the feature is on right now: allowed by the environment and not switched off by an administrator. */
    public boolean enabled(Feature feature) {
        if (!allowedByEnvironment(feature)) {
            return false;
        }
        Toggle toggle = snapshot().get(feature);
        return toggle == null || toggle.enabled();
    }

    /** The product's own settings with the master switch applied, e.g. {@code live(Feature.RIDES, RidesFlags.class)}. */
    public <T extends FeatureGate> T live(Feature feature, Class<T> type) {
        return type.cast(gates.get(feature).withEnabled(enabled(feature)));
    }

    /** Client-visible capability flags of a product (master switch applied); empty when the product defines none. */
    public java.util.Map<String, Boolean> capabilities(Feature feature) {
        return gates.get(feature).withEnabled(enabled(feature)).capabilities();
    }

    public List<FeatureView> views() {
        Map<Feature, Toggle> toggles = reload();
        return java.util.Arrays.stream(Feature.values()).map(f -> {
            Toggle t = toggles.get(f);
            boolean allowed = allowedByEnvironment(f);
            boolean on = t == null || t.enabled();
            return new FeatureView(f, allowed, on, allowed && on, t == null ? 0 : t.version(), t == null ? null : t.reason(),
                    t == null ? null : t.updatedAt());
        }).toList();
    }

    @Transactional
    public FeatureView set(UUID admin, Feature feature, boolean enabled, String reason, Long expectedVersion) {
        if (!allowedByEnvironment(feature)) {
            throw new ApiException(HttpStatus.CONFLICT, "FEATURE_NOT_ALLOWED_BY_ENVIRONMENT",
                    "This environment does not allow the feature; it cannot be switched from the admin application");
        }
        String why = reason == null ? "" : reason.trim();
        if (why.length() < 3 || why.length() > 200) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of 3 to 200 characters is required");
        }
        List<Toggle> current = db.query("select enabled, version, reason, updated_by, updated_at from identity.feature_toggles where feature = ? for update",
                (rs, n) -> new Toggle(rs.getBoolean(1), rs.getLong(2), rs.getString(3), rs.getObject(4, UUID.class),
                        rs.getObject(5, OffsetDateTime.class)), feature.name());
        Toggle previous = current.isEmpty() ? null : current.get(0);
        if (previous != null && expectedVersion != null && previous.version() != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The switch was changed by someone else; reload it");
        }
        if (previous == null) {
            db.update("insert into identity.feature_toggles(feature, enabled, reason, updated_by) values (?, ?, ?, ?)",
                    feature.name(), enabled, why, admin);
        } else {
            db.update("update identity.feature_toggles set enabled = ?, version = version + 1, reason = ?, updated_by = ?, updated_at = now() where feature = ?",
                    enabled, why, admin, feature.name());
        }
        db.update("insert into identity.feature_toggle_events(feature, admin_user_id, previous_enabled, new_enabled, reason) values (?, ?, ?, ?, ?)",
                feature.name(), admin, previous == null ? null : previous.enabled(), enabled, why);
        invalidate();
        return views().stream().filter(v -> v.feature() == feature).findFirst().orElseThrow();
    }

    public void invalidate() {
        cache = null;
    }

    private Map<Feature, Toggle> snapshot() {
        Map<Feature, Toggle> current = cache;
        if (current != null && clock.millis() - loadedAt < CACHE_MILLIS) {
            return current;
        }
        return reload();
    }

    private Map<Feature, Toggle> reload() {
        Map<Feature, Toggle> fresh = new EnumMap<>(Feature.class);
        db.query("select feature, enabled, version, reason, updated_by, updated_at from identity.feature_toggles", rs -> {
            fresh.put(Feature.valueOf(rs.getString(1)), new Toggle(rs.getBoolean(2), rs.getLong(3), rs.getString(4),
                    rs.getObject(5, UUID.class), rs.getObject(6, OffsetDateTime.class)));
        });
        loadedAt = clock.millis();
        cache = fresh;
        return fresh;
    }
}
