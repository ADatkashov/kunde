package kz.kunde.health;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import kz.kunde.admin.AdminGrants;
import kz.kunde.partner.PartnerAccessPolicy;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/health")
@PreAuthorize("@adminAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled"}, havingValue = "true")
public class HealthAdminController {
    private final AdminGrants grants;
    private final JdbcTemplate db;

    public HealthAdminController(AdminGrants grants, JdbcTemplate db) {
        this.grants = grants;
        this.db = db;
    }

    record Venue(UUID id, String name, boolean published) {}
    record Count(String status, long total) {}
    record Overview(List<Venue> venues, List<Count> appointmentCounts) {}
    record Moderation(@NotNull Boolean published) {}

    @GetMapping
    ResponseEntity<Overview> overview(@AuthenticationPrincipal Jwt principal) {
        authorize(principal);
        var venues = db.query("""
                select id, name, health_published from marketplace.booking_venues
                where category = 'HEALTH' and is_synthetic order by sort_order, id limit 100
                """, (rs, n) -> new Venue(rs.getObject(1, UUID.class), rs.getString(2), rs.getBoolean(3)));
        var counts = db.query("""
                select status, count(*) from transactions.bookings where category = 'HEALTH' group by status order by status
                """, (rs, n) -> new Count(rs.getString(1), rs.getLong(2)));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new Overview(venues, counts));
    }

    @PatchMapping("/venues/{id}")
    @Transactional
    public ResponseEntity<Void> moderate(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
            @Valid @RequestBody Moderation request) {
        UUID actor = authorize(principal);
        var current = db.queryForList("""
                select health_published from marketplace.booking_venues where id = ? and category = 'HEALTH' and is_synthetic for update
                """, Boolean.class, id);
        if (current.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found");
        }
        if (!current.getFirst().equals(request.published())) {
            db.update("update marketplace.booking_venues set health_published = ? where id = ?", request.published(), id);
            db.update("insert into marketplace.health_moderation_events (venue_id, admin_user_id, published) values (?, ?, ?)",
                    id, actor, request.published());
        }
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private UUID authorize(Jwt principal) {
        UUID user = PartnerAccessPolicy.userId(principal)
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is not allowed"));
        grants.require(user, AdminGrants.Permission.HEALTH_OPERATIONS);
        return user;
    }
}
