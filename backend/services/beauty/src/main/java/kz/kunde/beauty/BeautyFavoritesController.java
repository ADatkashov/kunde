package kz.kunde.beauty;

import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** The customer's favorite Beauty salons (own data only). */
@RestController
@RequestMapping("/api/v1/beauty/favorites")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class BeautyFavoritesController {
    private final JdbcTemplate db;
    private final ConsumerIdentityService identity;
    private final FeatureToggles toggles;

    public BeautyFavoritesController(JdbcTemplate db, ConsumerIdentityService identity, FeatureToggles toggles) {
        this.db = db;
        this.identity = identity;
        this.toggles = toggles;
    }

    private void requireEnabled() {
        if (!toggles.enabled(Feature.BEAUTY)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "BEAUTY_DISABLED", "Beauty is unavailable");
        }
    }

    /** Ids of the favorite salons, newest first. */
    @GetMapping
    ResponseEntity<List<String>> list(@AuthenticationPrincipal Jwt principal) {
        requireEnabled();
        var ids = db.query("select venue_id::text from marketplace.beauty_favorites where user_id = ? order by created_at desc, venue_id limit 200",
                (rs, row) -> rs.getString(1), identity.get(principal).id());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ids);
    }

    @PutMapping("/{venueId}")
    ResponseEntity<Void> put(@AuthenticationPrincipal Jwt principal, @PathVariable UUID venueId) {
        requireEnabled();
        int added = db.update("""
                insert into marketplace.beauty_favorites (user_id, venue_id)
                select ?, p.venue_id from marketplace.beauty_salon_profiles p where p.venue_id = ?
                on conflict do nothing
                """, identity.get(principal).id(), venueId);
        boolean exists = Boolean.TRUE.equals(db.queryForObject(
                "select exists(select 1 from marketplace.beauty_salon_profiles where venue_id = ?)", Boolean.class, venueId));
        if (added == 0 && !exists) {
            throw new ApiException(HttpStatus.NOT_FOUND, "SALON_NOT_FOUND", "Salon is not available");
        }
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @DeleteMapping("/{venueId}")
    ResponseEntity<Void> delete(@AuthenticationPrincipal Jwt principal, @PathVariable UUID venueId) {
        requireEnabled();
        db.update("delete from marketplace.beauty_favorites where user_id = ? and venue_id = ?", identity.get(principal).id(), venueId);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }
}
