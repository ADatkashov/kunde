package kz.kunde.booking;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/api/v1/booking/health/favorites")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.booking.enabled", havingValue = "true")
public class HealthFavoritesController {
    enum Kind { ORGANIZATION, SPECIALIST, WELLNESS_SERVICE }

    record Favorite(Kind kind, UUID id, UUID venueId, String name) {}

    private final JdbcTemplate jdbc;
    private final ConsumerIdentityService identity;
    private final BookingSlots slots;

    public HealthFavoritesController(JdbcTemplate jdbc, ConsumerIdentityService identity, BookingSlots slots) {
        this.jdbc = jdbc;
        this.identity = identity;
        this.slots = slots;
    }

    @GetMapping
    ResponseEntity<List<Favorite>> list(@AuthenticationPrincipal Jwt principal,
            @RequestParam(required = false) UUID venueId,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        slots.requireHealthCatalog();
        var favorites = jdbc.query("""
                select t.kind, t.id, t.venue_id, t.name
                from transactions.health_favorites f join marketplace.health_favorite_targets t on
                    (t.kind = 'ORGANIZATION' and t.id = f.venue_id)
                    or (t.kind = 'SPECIALIST' and t.id = f.specialist_id)
                    or (t.kind = 'WELLNESS_SERVICE' and t.id = f.service_id)
                where f.user_id = ? and (cast(? as uuid) is null or t.venue_id = ?) order by f.created_at desc, t.kind, t.id limit ? offset ?
                """, (rs, n) -> new Favorite(Kind.valueOf(rs.getString(1)), rs.getObject(2, UUID.class),
                        rs.getObject(3, UUID.class), rs.getString(4)), identity.get(principal).id(), venueId, venueId, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(favorites);
    }

    @PutMapping("/{kind}/{id}")
    ResponseEntity<Void> put(@AuthenticationPrincipal Jwt principal, @PathVariable Kind kind, @PathVariable UUID id) {
        slots.requireHealthCatalog();
        var found = jdbc.queryForObject("""
                with target as (
                    select kind, id from marketplace.health_favorite_targets where kind = ? and id = ?
                ), added as (
                    insert into transactions.health_favorites (user_id, venue_id, specialist_id, service_id)
                    select ?, case when kind = 'ORGANIZATION' then id end,
                        case when kind = 'SPECIALIST' then id end, case when kind = 'WELLNESS_SERVICE' then id end
                    from target on conflict do nothing
                )
                select exists(select 1 from target)
                """, Boolean.class, kind.name(), id, identity.get(principal).id());
        if (!Boolean.TRUE.equals(found)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HEALTH_FAVORITE_TARGET_NOT_FOUND",
                    "Favorite target is unavailable");
        }
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @DeleteMapping("/{kind}/{id}")
    ResponseEntity<Void> delete(@AuthenticationPrincipal Jwt principal, @PathVariable Kind kind, @PathVariable UUID id) {
        jdbc.update("""
                delete from transactions.health_favorites where user_id = ?
                and (venue_id = ? or specialist_id = ? or service_id = ?)
                """, identity.get(principal).id(), kind == Kind.ORGANIZATION ? id : null,
                kind == Kind.SPECIALIST ? id : null, kind == Kind.WELLNESS_SERVICE ? id : null);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }
}
