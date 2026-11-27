package kz.kunde.partner;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/** In-process adapter of {@link PartnerDirectory}; the SQL is the one products used to embed in their own queries. */
@Service
public class JdbcPartnerDirectory implements PartnerDirectory {
    private static final String ACTIVE_STAFF_OF_APPROVED = """
            select 1 from marketplace.partners p
            join marketplace.partner_staff s on s.partner_id = p.id and s.user_id = ? and s.status = 'ACTIVE'
            where p.id = ? and p.verification_status = 'APPROVED'
            """;

    /** Roles that manage catalogue offers: the organisation's owner and managers; operators run orders only. */
    private static final String CATALOG_MANAGER = ACTIVE_STAFF_OF_APPROVED + " and s.role in ('OWNER', 'MANAGER')";

    private final JdbcTemplate db;

    public JdbcPartnerDirectory(JdbcTemplate db) {
        this.db = db;
    }

    @Override
    public boolean isActiveStaffOfApprovedPartner(UUID userId, UUID partnerId) {
        return !db.queryForList(ACTIVE_STAFF_OF_APPROVED, userId, partnerId).isEmpty();
    }

    @Override
    public Set<UUID> approvedPartnersOfStaff(UUID userId) {
        return new HashSet<>(db.queryForList("""
                select p.id from marketplace.partners p
                join marketplace.partner_staff s on s.partner_id = p.id and s.user_id = ? and s.status = 'ACTIVE'
                where p.verification_status = 'APPROVED'
                """, UUID.class, userId));
    }

    @Override
    public Set<UUID> approvedPartnerIds() {
        return new HashSet<>(db.queryForList("select id from marketplace.partners where verification_status = 'APPROVED'", UUID.class));
    }

    @Override
    public boolean lockActiveStaffOfApprovedPartner(UUID userId, UUID partnerId) {
        return !db.queryForList(ACTIVE_STAFF_OF_APPROVED + " for share of p, s", userId, partnerId).isEmpty();
    }

    @Override
    public boolean isCatalogManager(UUID userId, UUID partnerId) {
        return !db.queryForList(CATALOG_MANAGER, userId, partnerId).isEmpty();
    }

    @Override
    public boolean lockCatalogManager(UUID userId, UUID partnerId) {
        return !db.queryForList(CATALOG_MANAGER + " for share of p, s", userId, partnerId).isEmpty();
    }

    @Override
    public void recordCatalogChange(UUID partnerId, UUID actorUserId, String entityType, UUID entityId, String field, String oldValue, String newValue) {
        db.update("""
                insert into marketplace.partner_catalog_events (partner_id, actor_user_id, entity_type, entity_id, field, old_value, new_value)
                values (?, ?, ?, ?, ?, ?, ?)
                """, partnerId, actorUserId, entityType, entityId, field, oldValue, newValue);
    }
}
