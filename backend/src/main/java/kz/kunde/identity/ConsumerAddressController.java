package kz.kunde.identity;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
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
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/me/addresses")
@PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class ConsumerAddressController {
    private final JdbcTemplate db;
    private final ConsumerIdentityService identity;

    public ConsumerAddressController(JdbcTemplate db, ConsumerIdentityService identity) {
        this.db = db;
        this.identity = identity;
    }

    public record AddressRequest(
            @NotBlank @Size(max = 80) String label,
            @NotBlank @Size(max = 500) String formattedAddress,
            @NotNull @DecimalMin("-90") @DecimalMax("90") BigDecimal latitude,
            @NotNull @DecimalMin("-180") @DecimalMax("180") BigDecimal longitude) {}

    public record AddressView(UUID id, String label, String formattedAddress,
                              BigDecimal latitude, BigDecimal longitude, long version,
                              boolean serviceable) {}

    @GetMapping
    @Transactional(readOnly = true)
    public ResponseEntity<List<AddressView>> list(@AuthenticationPrincipal Jwt principal) {
        UUID user = identity.get(principal).id();
        List<AddressView> result = db.query("""
                SELECT a.id, a.label, a.formatted_address, a.latitude, a.longitude, a.version,
                EXISTS (SELECT 1 FROM serviceability.zone_addresses za
                        JOIN serviceability.zones z ON z.id = za.zone_id
                        WHERE za.address_id = a.id AND z.enabled) AS serviceable
                FROM profile.consumer_addresses a
                WHERE a.user_id = ? AND a.deleted_at IS NULL ORDER BY a.created_at DESC, a.id
                """, (rs, row) -> new AddressView(rs.getObject("id", UUID.class),
                        rs.getString("label"), rs.getString("formatted_address"),
                        rs.getBigDecimal("latitude"), rs.getBigDecimal("longitude"),
                        rs.getLong("version"), rs.getBoolean("serviceable")), user);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(result);
    }

    @PostMapping
    @Transactional
    public ResponseEntity<AddressView> create(@AuthenticationPrincipal Jwt principal,
                                               @Valid @RequestBody AddressRequest request) {
        UUID user = identity.get(principal).id();
        UUID id = db.queryForObject("""
                INSERT INTO profile.consumer_addresses
                    (user_id, label, formatted_address, latitude, longitude)
                VALUES (?, ?, ?, ?, ?) RETURNING id
                """, UUID.class, user, request.label().strip(), request.formattedAddress().strip(),
                request.latitude(), request.longitude());
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore())
                .body(new AddressView(id, request.label().strip(), request.formattedAddress().strip(),
                        request.latitude(), request.longitude(), 0, false));
    }

    @DeleteMapping("/{id}")
    @Transactional
    public ResponseEntity<Void> delete(@AuthenticationPrincipal Jwt principal, @PathVariable UUID id,
                                       @RequestParam @PositiveOrZero long version) {
        UUID user = identity.get(principal).id();
        int updated = db.update("""
                UPDATE profile.consumer_addresses
                SET deleted_at = now(), updated_at = now(), version = version + 1
                WHERE id = ? AND user_id = ? AND deleted_at IS NULL AND version = ?
                """, id, user, version);
        if (updated == 0) {
            throw new ApiException(HttpStatus.CONFLICT, "ADDRESS_VERSION_CONFLICT",
                    "Address is unavailable or has changed");
        }
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }
}
