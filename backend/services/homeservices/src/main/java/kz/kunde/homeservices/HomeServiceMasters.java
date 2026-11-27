package kz.kunde.homeservices;

import java.security.SecureRandom;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Masters of the partner's cleaning venues: the partner creates a master, hands out a one-time invite code (the master links it in
 * Executor) and retires the master. A master is a Booking Engine resource ({@code booking_masters}); Home Services only adds this
 * onboarding. Writes need a catalog manager (same rule as offers and zones); every change is audited in
 * {@code partner_catalog_events}.
 */
@Service
public class HomeServiceMasters {
    static final int MAX_MASTERS_PER_VENUE = 50;
    /** No 0/O/1/I: the code is read aloud and typed by hand. */
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RANDOM = new SecureRandom();

    public record MasterRow(String id, String venueId, String venueName, String name, boolean linked, String inviteCode) {}

    private final JdbcTemplate db;
    private final PartnerDirectory partners;

    public HomeServiceMasters(JdbcTemplate db, PartnerDirectory partners) {
        this.db = db;
        this.partners = partners;
    }

    /** Active masters of the partner's cleaning venues; the invite code is shown only while the master is not linked yet. */
    public List<MasterRow> masters(UUID user, UUID partnerId) {
        if (!partners.isActiveStaffOfApprovedPartner(user, partnerId)) {
            throw partnerNotFound();
        }
        return db.query(SELECT + " where v.partner_id = ? and v.category = 'CLEANING' and m.active order by v.sort_order, m.sort_order, m.name, m.id",
                HomeServiceMasters::row, partnerId);
    }

    @Transactional
    public MasterRow create(UUID user, UUID partnerId, UUID venueId, String name) {
        requireManager(user, partnerId);
        String clean = cleanName(name);
        // Serialise creators of one venue so the limit and the sort order hold.
        var venue = db.query("select id from marketplace.booking_venues where id = ? and partner_id = ? and category = 'CLEANING' for update",
                (rs, i) -> rs.getObject(1, UUID.class), venueId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "VENUE_NOT_FOUND", "Venue not found"));
        Integer count = db.queryForObject("select count(*) from marketplace.booking_masters where venue_id = ? and active", Integer.class, venue);
        if (count != null && count >= MAX_MASTERS_PER_VENUE) {
            throw new ApiException(HttpStatus.CONFLICT, "TOO_MANY_MASTERS", "At most " + MAX_MASTERS_PER_VENUE + " masters per venue");
        }
        UUID id = db.queryForObject("insert into marketplace.booking_masters (venue_id, name, bio, emoji, tone, invite_code, sort_order) "
                + "values (?, ?, '', '🧹', 'amber', ?, coalesce((select max(sort_order) + 1 from marketplace.booking_masters where venue_id = ?), 0)) returning id",
                UUID.class, venue, clean, newCode(), venue);
        db.update("insert into marketplace.booking_master_services (master_id, service_id) select ?, id from marketplace.booking_services where venue_id = ?", id, venue);
        for (int day = 1; day <= 6; day++) {
            db.update("insert into marketplace.booking_working_hours (master_id, weekday, start_time, end_time) values (?, ?, '09:00', '18:00')", id, day);
        }
        audit(partnerId, user, id, "created", null, clean);
        return one(id);
    }

    /** A new code replaces the old one; refused once the master has linked an account (nothing left to hand out). */
    @Transactional
    public MasterRow reissueInvite(UUID user, UUID partnerId, UUID masterId) {
        requireManager(user, partnerId);
        var linked = lockedMaster(partnerId, masterId);
        if (linked) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_LINKED", "The master already signed in; there is no code to reissue");
        }
        db.update("update marketplace.booking_masters set invite_code = ? where id = ?", newCode(), masterId);
        audit(partnerId, user, masterId, "invite_reissued", null, null);
        return one(masterId);
    }

    /** Retires the master (no new bookings, the code stops working). Refused while the master has upcoming or running visits. */
    @Transactional
    public void deactivate(UUID user, UUID partnerId, UUID masterId) {
        requireManager(user, partnerId);
        lockedMaster(partnerId, masterId);
        Integer open = db.queryForObject("select count(*) from transactions.bookings where master_id = ? and status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS')",
                Integer.class, masterId);
        if (open != null && open > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "MASTER_HAS_BOOKINGS", "The master has active bookings; finish or reassign them first");
        }
        db.update("update marketplace.booking_masters set active = false, invite_code = null where id = ?", masterId);
        audit(partnerId, user, masterId, "deactivated", "active", "inactive");
    }

    /** Locks an active master of the partner's cleaning venue and tells whether an account is already linked. */
    private boolean lockedMaster(UUID partnerId, UUID masterId) {
        return db.query("select m.user_id is not null from marketplace.booking_masters m join marketplace.booking_venues v on v.id = m.venue_id "
                + "where m.id = ? and m.active and v.partner_id = ? and v.category = 'CLEANING' for update of m", (rs, i) -> rs.getBoolean(1), masterId, partnerId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "MASTER_NOT_FOUND", "Master not found"));
    }

    private static final String SELECT = """
            select m.id::text, m.venue_id::text, v.name, m.name, m.user_id is not null as linked,
                   case when m.user_id is null then m.invite_code end as invite_code
            from marketplace.booking_masters m join marketplace.booking_venues v on v.id = m.venue_id""";

    private MasterRow one(UUID id) {
        return db.queryForObject(SELECT + " where m.id = ?", HomeServiceMasters::row, id);
    }

    private static MasterRow row(java.sql.ResultSet rs, int i) throws java.sql.SQLException {
        return new MasterRow(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getBoolean(5), rs.getString(6));
    }

    private String newCode() {
        for (int attempt = 0; attempt < 20; attempt++) {
            StringBuilder code = new StringBuilder("H");
            for (int i = 0; i < 9; i++) {
                if (i == 4) {
                    code.append('-');
                }
                code.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
            }
            if (!Boolean.TRUE.equals(db.queryForObject("select exists (select 1 from marketplace.booking_masters where invite_code = ?)", Boolean.class, code.toString()))) {
                return code.toString();
            }
        }
        throw new IllegalStateException("could not generate a free invite code");
    }

    private static String cleanName(String name) {
        String clean = name == null ? "" : name.strip();
        if (clean.isEmpty() || clean.length() > 120) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "NAME_INVALID", "Name must be 1-120 characters");
        }
        return clean;
    }

    private void audit(UUID partnerId, UUID actor, UUID masterId, String field, String oldValue, String newValue) {
        db.update("insert into marketplace.partner_catalog_events (partner_id, actor_user_id, entity_type, entity_id, field, old_value, new_value) "
                + "values (?, ?, 'MASTER', ?, ?, ?, ?)", partnerId, actor, masterId, field, oldValue, newValue);
    }

    private void requireManager(UUID user, UUID partnerId) {
        if (partners.lockCatalogManager(user, partnerId)) {
            return;
        }
        if (partners.isActiveStaffOfApprovedPartner(user, partnerId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "PARTNER_ROLE_FORBIDDEN", "Role is not allowed to do this");
        }
        throw partnerNotFound();
    }

    private static ApiException partnerNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND", "Partner not found");
    }
}
