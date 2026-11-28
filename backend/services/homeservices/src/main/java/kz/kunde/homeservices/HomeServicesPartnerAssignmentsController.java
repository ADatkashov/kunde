package kz.kunde.homeservices;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.homeservices.HomeServiceAssignments.Assignment;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import kz.kunde.platform.partner.PartnerDirectory;
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
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/partner/partners/{partnerId}/home-services/assignments")
@PreAuthorize("@partnerAccessPolicy.allowed(authentication)")
@ConditionalOnProperty(name = {"app.identity.consumer-enabled", "app.auth.phone.enabled", "app.booking.enabled"}, havingValue = "true")
public class HomeServicesPartnerAssignmentsController {
    public record Order(UUID id, String bookingNumber, String serviceName, OffsetDateTime startsAt, long version) {}
    public record Request(@NotNull UUID masterId, @NotNull @Min(0) Long expectedVersion,
            @NotBlank @Size(max = 200) String reason) {}

    private static final String PENDING = """
            from transactions.bookings b join marketplace.booking_venues v on v.id = b.venue_id
            where v.partner_id = ? and b.category = 'CLEANING' and b.master_id is null
                and b.status = 'CONFIRMED'
            """;

    private final JdbcTemplate db;
    private final PartnerDirectory partners;
    private final FeatureToggles toggles;
    private final HomeServiceAssignments assignments;
    private final HomeServiceReschedules reschedules;

    public HomeServicesPartnerAssignmentsController(JdbcTemplate db, PartnerDirectory partners,
            FeatureToggles toggles, HomeServiceAssignments assignments, HomeServiceReschedules reschedules) {
        this.db = db;
        this.partners = partners;
        this.toggles = toggles;
        this.assignments = assignments;
        this.reschedules = reschedules;
    }

    @GetMapping
    @Transactional(readOnly = true)
    ResponseEntity<List<Order>> queue(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId) {
        authorize(principal, partnerId, false);
        return ok(db.query("select b.id, b.booking_number, b.service_name, b.starts_at, b.version " + PENDING
                + "order by b.starts_at, b.id limit 100",
                (rs, row) -> new Order(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3),
                        rs.getObject(4, OffsetDateTime.class), rs.getLong(5)), partnerId));
    }

    @GetMapping("/{id}/masters")
    @Transactional(readOnly = true)
    ResponseEntity<List<HomeServiceAssignments.Master>> masters(@AuthenticationPrincipal Jwt principal,
            @PathVariable UUID partnerId, @PathVariable UUID id) {
        authorize(principal, partnerId, false);
        return ok(assignments.candidates(id, order(partnerId, id, null)));
    }

    @PostMapping("/{id}/reschedule")
    @Transactional
    ResponseEntity<Void> proposeReschedule(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId, @PathVariable UUID id,
            @Valid @RequestBody HomeServiceReschedules.Request request) {
        UUID actor = authorize(principal, partnerId, true);
        reschedules.propose(id, partnerId, actor, "PARTNER", request);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PostMapping("/{id}")
    @Transactional
    ResponseEntity<Void> replace(@AuthenticationPrincipal Jwt principal, @PathVariable UUID partnerId, @PathVariable UUID id,
            @Valid @RequestBody Request request) {
        UUID actor = authorize(principal, partnerId, true);
        Assignment order = order(partnerId, id, request.expectedVersion());
        assignments.replace(id, order, request.masterId(), request.expectedVersion(), "PARTNER", actor, request.reason().strip());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private Assignment order(UUID partner, UUID id, Long version) {
        return db.query("select b.status, b.venue_id, b.master_id, b.service_id, b.home_latitude, b.home_longitude, b.version "
                + PENDING + "and b.id = ?" + (version == null ? "" : " for update of b"), (rs, row) -> {
                    if (version != null && rs.getLong(7) != version) {
                        throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The order has changed; reload it");
                    }
                    return new Assignment(rs.getString(1), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class),
                            rs.getObject(4, UUID.class), rs.getObject(5, Double.class), rs.getObject(6, Double.class));
                }, partner, id).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found"));
    }

    private UUID authorize(Jwt principal, UUID partner, boolean write) {
        if (!toggles.enabled(Feature.HOME_SERVICES)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "HOME_SERVICES_DISABLED", "Home Services is unavailable");
        }
        UUID user = UUID.fromString(principal.getSubject());
        boolean allowed = write ? partners.lockCatalogManager(user, partner) : partners.isActiveStaffOfApprovedPartner(user, partner);
        if (!allowed) {
            throw new ApiException(HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND", "Partner not found");
        }
        return user;
    }

    private static <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
