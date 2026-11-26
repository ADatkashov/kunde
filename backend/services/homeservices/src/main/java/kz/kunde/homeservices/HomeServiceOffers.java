package kz.kunde.homeservices;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Moderated offers of Home Services: a partner's booking service classified by a catalogue definition. The state machine
 * lives here and nowhere else; every change checks the previous status and version and writes an immutable audit event.
 */
@Service
public class HomeServiceOffers {
    public enum Status { DRAFT, PENDING, PUBLISHED, REJECTED, SUSPENDED }

    public enum Actor { PARTNER, ADMIN }

    /** A named transition: who may do it, from which statuses, to which status. */
    public enum Action {
        SUBMIT(Actor.PARTNER, Status.PENDING, Status.DRAFT, Status.REJECTED),
        WITHDRAW(Actor.PARTNER, Status.DRAFT, Status.PENDING, Status.PUBLISHED),
        APPROVE(Actor.ADMIN, Status.PUBLISHED, Status.PENDING),
        REJECT(Actor.ADMIN, Status.REJECTED, Status.PENDING),
        SUSPEND(Actor.ADMIN, Status.SUSPENDED, Status.PUBLISHED),
        RESTORE(Actor.ADMIN, Status.PUBLISHED, Status.SUSPENDED);

        final Actor actor;
        final Status to;
        final Set<Status> from;

        Action(Actor actor, Status to, Status first, Status... more) {
            this.actor = actor;
            this.to = to;
            this.from = EnumSet.of(first, more);
        }
    }

    public record Offer(String id, String serviceId, String serviceName, String venueId, String partnerId,
            String definitionCode, String pricingModel, boolean homeVisit, int warrantyDays, Status status,
            String statusReason, long version, long priceMinor, int durationMinutes) {}

    public static final Set<String> PRICING_MODELS =
            Set.of("FIXED", "FROM", "HOURLY", "PER_SQM", "PER_UNIT", "DIAGNOSTIC", "QUOTE");

    private static final String SELECT = """
            select o.id, o.service_id, s.name as service_name, v.id as venue_id, v.partner_id, o.definition_code,
                   o.pricing_model, o.home_visit, o.warranty_days, o.status, o.status_reason, o.version,
                   s.price_minor, s.duration_minutes
            from marketplace.home_service_offers o
            join marketplace.booking_services s on s.id = o.service_id
            join marketplace.booking_venues v on v.id = s.venue_id
            """;

    private final JdbcTemplate db;

    public HomeServiceOffers(JdbcTemplate db) {
        this.db = db;
    }

    @Transactional
    public Offer create(UUID actor, UUID partnerId, UUID serviceId, String definitionCode, String pricingModel,
            boolean homeVisit, int warrantyDays) {
        if (!PRICING_MODELS.contains(pricingModel)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PRICING_MODEL_INVALID", "Unknown pricing model");
        }
        // Only a service of this partner's own Home Services venue may be offered (tenant isolation).
        boolean owned = Boolean.TRUE.equals(db.queryForObject("""
                select exists (select 1 from marketplace.booking_services s
                    join marketplace.booking_venues v on v.id = s.venue_id
                    where s.id = ? and v.partner_id = ? and v.category = 'CLEANING')
                """, Boolean.class, serviceId, partnerId));
        if (!owned) {
            throw new ApiException(HttpStatus.NOT_FOUND, "SERVICE_NOT_FOUND", "Service not found");
        }
        boolean activeDefinition = Boolean.TRUE.equals(db.queryForObject("""
                select exists (select 1 from marketplace.home_service_definitions d
                    join marketplace.home_service_categories c on c.code = d.category_code
                    where d.code = ? and d.active and c.active)
                """, Boolean.class, definitionCode));
        if (!activeDefinition) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "DEFINITION_INACTIVE", "The service definition is unavailable");
        }
        UUID id = db.query("""
                insert into marketplace.home_service_offers (service_id, definition_code, pricing_model, home_visit, warranty_days)
                values (?, ?, ?, ?, ?) on conflict (service_id) do nothing returning id
                """, (rs, row) -> rs.getObject("id", UUID.class), serviceId, definitionCode, pricingModel, homeVisit, warrantyDays)
                .stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.CONFLICT, "OFFER_EXISTS", "The service already has an offer"));
        event(id, 1, actor, Actor.PARTNER, null, Status.DRAFT, null);
        return get(id).orElseThrow();
    }

    /** Applies one transition; a partner is confined to its own offers, an administrator sees all. */
    @Transactional
    public Offer transition(UUID actor, Actor role, UUID partnerScope, UUID offerId, Action action, long expectedVersion,
            String reason) {
        if (action.actor != role) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ACTION_FORBIDDEN", "This action is not allowed for the role");
        }
        String cleanReason = reason == null ? null : reason.strip();
        if (role == Actor.ADMIN && (cleanReason == null || cleanReason.length() < 3)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of at least 3 characters is required");
        }
        var current = db.query("select o.status, o.version, v.partner_id from marketplace.home_service_offers o "
                + "join marketplace.booking_services s on s.id = o.service_id "
                + "join marketplace.booking_venues v on v.id = s.venue_id where o.id = ? for update of o",
                (rs, row) -> new Object[] {Status.valueOf(rs.getString(1)), rs.getLong(2), rs.getObject(3, UUID.class)}, offerId)
                .stream().findFirst();
        // A partner must not learn that an offer of another organisation exists.
        if (current.isEmpty() || (partnerScope != null && !partnerScope.equals(current.get()[2]))) {
            throw new ApiException(HttpStatus.NOT_FOUND, "OFFER_NOT_FOUND", "Offer not found");
        }
        Status from = (Status) current.get()[0];
        long version = (Long) current.get()[1];
        if (version != expectedVersion) {
            throw new ApiException(HttpStatus.CONFLICT, "VERSION_CONFLICT", "The offer changed; reload and retry");
        }
        if (!action.from.contains(from)) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_TRANSITION", "The offer is " + from + "; " + action + " is not possible");
        }
        db.update("update marketplace.home_service_offers set status = ?, status_reason = ?, version = version + 1, "
                + "updated_at = now() where id = ?", action.to.name(), cleanReason, offerId);
        event(offerId, version + 1, actor, role, from, action.to, cleanReason);
        return get(offerId).orElseThrow();
    }

    @Transactional(readOnly = true)
    public Optional<Offer> get(UUID id) {
        return db.query(SELECT + " where o.id = ?", HomeServiceOffers::offer, id).stream().findFirst();
    }

    @Transactional(readOnly = true)
    public List<Offer> listForPartner(UUID partnerId, int limit, int offset) {
        return db.query(SELECT + " where v.partner_id = ? order by o.updated_at desc, o.id limit ? offset ?",
                HomeServiceOffers::offer, partnerId, limit, offset);
    }

    @Transactional(readOnly = true)
    public List<Offer> listForReview(Status status, int limit, int offset) {
        return db.query(SELECT + " where (?::text is null or o.status = ?) order by o.updated_at, o.id limit ? offset ?",
                HomeServiceOffers::offer, status == null ? null : status.name(), status == null ? null : status.name(), limit, offset);
    }

    private void event(UUID offerId, long version, UUID actor, Actor role, Status from, Status to, String reason) {
        db.update("insert into marketplace.home_service_offer_events (offer_id, version, actor_user_id, actor_role, from_status, to_status, reason) "
                + "values (?, ?, ?, ?, ?, ?, ?)", offerId, version, actor, role.name(), from == null ? null : from.name(), to.name(), reason);
    }

    private static Offer offer(ResultSet rs, int row) throws SQLException {
        return new Offer(rs.getString("id"), rs.getString("service_id"), rs.getString("service_name"), rs.getString("venue_id"),
                rs.getString("partner_id"), rs.getString("definition_code"), rs.getString("pricing_model"),
                rs.getBoolean("home_visit"), rs.getInt("warranty_days"), Status.valueOf(rs.getString("status")),
                rs.getString("status_reason"), rs.getLong("version"), rs.getLong("price_minor"), rs.getInt("duration_minutes"));
    }
}
