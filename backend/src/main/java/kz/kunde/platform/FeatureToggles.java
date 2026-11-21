package kz.kunde.platform;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.auto.AutoProperties;
import kz.kunde.delivery.DeliveryProperties;
import kz.kunde.education.EducationSettings;
import kz.kunde.events.EventsSettings;
import kz.kunde.leisure.LeisureFlags;
import kz.kunde.groceries.GroceriesSettings;
import kz.kunde.health.HealthSettings;
import kz.kunde.rides.RidesFlags;
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
    public enum Feature { AUTO, RIDES, DELIVERY, LEISURE, HEALTH, EDUCATION, GROCERIES, EVENTS }

    public record Toggle(boolean enabled, long version, String reason, UUID updatedBy, OffsetDateTime updatedAt) {}

    public record FeatureView(Feature feature, boolean allowedByEnvironment, boolean enabled, boolean effective, long version,
            String reason, OffsetDateTime updatedAt) {}

    private static final long CACHE_MILLIS = 5_000;

    private final JdbcTemplate db;
    private final AutoProperties auto;
    private final RidesFlags rides;
    private final DeliveryProperties delivery;
    private final LeisureFlags leisure;
    private final HealthSettings health;
    private final EducationSettings education;
    private final EventsSettings events;
    private final GroceriesSettings groceries;
    private final Clock clock;
    private volatile Map<Feature, Toggle> cache;
    private volatile long loadedAt;

    public FeatureToggles(JdbcTemplate db, AutoProperties auto, RidesFlags rides, DeliveryProperties delivery, LeisureFlags leisure, HealthSettings health, EducationSettings education,
            GroceriesSettings groceries, EventsSettings events) {
        this.db = db;
        this.auto = auto;
        this.rides = rides;
        this.delivery = delivery;
        this.leisure = leisure;
        this.health = health;
        this.education = education;
        this.groceries = groceries;
        this.events = events;
        this.clock = Clock.systemUTC();
    }

    public boolean allowedByEnvironment(Feature feature) {
        return switch (feature) {
            case AUTO -> auto.enabled();
            case RIDES -> rides.enabled();
            case DELIVERY -> delivery.enabled();
            case LEISURE -> leisure.allowedByEnvironment();
            case HEALTH -> health.enabled();
            case EDUCATION -> education.allowedByEnvironment();
            case EVENTS -> events.allowedByEnvironment();
            case GROCERIES -> groceries.allowedByEnvironment();
        };
    }

    /** Whether the feature is on right now: allowed by the environment and not switched off by an administrator. */
    public boolean enabled(Feature feature) {
        if (!allowedByEnvironment(feature)) {
            return false;
        }
        Toggle toggle = snapshot().get(feature);
        return toggle == null || toggle.enabled();
    }

    /** Rides flags with the master switch applied; sub-flags keep their environment values. */
    public RidesFlags rides() {
        return rides.withEnabled(enabled(Feature.RIDES));
    }

    /** Delivery settings with the master switch applied; everything else keeps its environment value. */
    public DeliveryProperties delivery() {
        return delivery.withEnabled(enabled(Feature.DELIVERY));
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
