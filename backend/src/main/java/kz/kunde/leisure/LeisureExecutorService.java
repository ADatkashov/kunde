package kz.kunde.leisure;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Executors for the Leisure events that really need one (guide, host, instructor, animator, organiser). A partner (Owner/Manager) offers a session to a
 * person known by phone number; the person accepts or declines in the Executor app, starts and completes the work, or cancels before the start. An
 * ordinary cinema ticket never involves an executor. Transitions are row-locked and idempotent; every step lands in the Leisure audit.
 */
@Service
public class LeisureExecutorService {
    private static final List<String> ROLES = List.of("GUIDE", "HOST", "INSTRUCTOR", "ANIMATOR", "ORGANIZER");
    private static final Role[] MANAGE = {Role.OWNER, Role.MANAGER};

    public record Assignment(String id, String status, String role, String note, String sessionId, String eventTitle, String venueName, String venueAddress,
            OffsetDateTime startsAt, OffsetDateTime endsAt, int guests, String executor, boolean canStart, boolean canComplete, OffsetDateTime updatedAt) {}

    private final JdbcTemplate db;
    private final PartnerService partners;

    public LeisureExecutorService(JdbcTemplate db, PartnerService partners) {
        this.db = db;
        this.partners = partners;
    }

    private static final String SELECT = """
            select a.id, a.status, a.role, a.note, s.id, e.title, v.name, v.address, s.starts_at, s.ends_at,
              coalesce((select sum(t.admits) from transactions.leisure_tickets t where t.session_id = s.id and t.status in ('PENDING', 'VALID', 'USED')), 0),
              right(coalesce((select phone_e164 from identity.phone_identities p where p.user_id = a.executor_user_id), ''), 4), a.updated_at
            from transactions.leisure_assignments a join marketplace.leisure_sessions s on s.id = a.session_id join marketplace.leisure_events e on e.id = s.event_id
            join marketplace.leisure_venues v on v.id = e.venue_id """;

    private static Assignment map(java.sql.ResultSet rs, int n) throws java.sql.SQLException {
        String status = rs.getString(2);
        OffsetDateTime starts = rs.getObject(9, OffsetDateTime.class);
        OffsetDateTime ends = rs.getObject(10, OffsetDateTime.class);
        OffsetDateTime now = OffsetDateTime.now();
        boolean started = "STARTED".equals(status);
        return new Assignment(rs.getString(1), status, rs.getString(3), rs.getString(4), rs.getString(5), rs.getString(6), rs.getString(7), rs.getString(8), starts, ends,
                rs.getInt(11), "•••" + rs.getString(12), "ACCEPTED".equals(status) && now.isAfter(starts.minusHours(2)) && now.isBefore(ends), started, rs.getObject(13, OffsetDateTime.class));
    }

    private void audit(UUID actor, String type, UUID partner, String action, UUID assignment, String detail) {
        db.update("insert into marketplace.leisure_audit (actor_user_id, actor_type, partner_id, action, target, detail) values (?, ?, ?, ?, ?, ?)", actor, type, partner, action, assignment.toString(), detail);
    }

    // ---- partner side --------------------------------------------------------------------------------------------------------

    @Transactional
    public Assignment assign(UUID actor, UUID partner, UUID sessionId, String phone, String role, String note) {
        partners.requireProcessing(actor, partner, MANAGE);
        var s = db.query("select e.needs_executor, s.starts_at, s.status from marketplace.leisure_sessions s join marketplace.leisure_events e on e.id = s.event_id "
                + "join marketplace.leisure_venues v on v.id = e.venue_id where s.id = ? and v.partner_id = ?", (rs, n) -> new Object[] {rs.getBoolean(1), rs.getObject(2, OffsetDateTime.class), rs.getString(3)},
                sessionId, partner).stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SESSION_NOT_FOUND", "Not found"));
        if (!(boolean) s[0]) { throw new ApiException(HttpStatus.CONFLICT, "EXECUTOR_NOT_NEEDED", "This event does not use an executor"); }
        if (!"SCHEDULED".equals(s[2]) || !((OffsetDateTime) s[1]).isAfter(OffsetDateTime.now())) { throw new ApiException(HttpStatus.CONFLICT, "SESSION_NOT_AVAILABLE", "The session is over or cancelled"); }
        String r = role == null ? "" : role.toUpperCase(Locale.ROOT);
        if (!ROLES.contains(r)) { throw new ApiException(HttpStatus.BAD_REQUEST, "ROLE_INVALID", "Role is one of " + ROLES); }
        String text = note == null ? null : note.strip();
        if (text != null && text.length() > 200) { throw new ApiException(HttpStatus.BAD_REQUEST, "FIELD_INVALID", "note is at most 200 characters"); }
        String e164 = phone == null ? "" : phone.strip();
        UUID executor = db.query("select user_id from identity.phone_identities where phone_e164 = ?", rs -> rs.next() ? rs.getObject(1, UUID.class) : null, e164);
        if (executor == null) { throw new ApiException(HttpStatus.NOT_FOUND, "EXECUTOR_NOT_FOUND", "No KUNDE user with this phone number"); }
        if (db.queryForObject("select count(*) from transactions.leisure_assignments where session_id = ? and executor_user_id = ? and status in ('OFFERED', 'ACCEPTED', 'STARTED')", Integer.class, sessionId, executor) > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "ALREADY_ASSIGNED", "This person already has an active assignment for the session");
        }
        UUID id = db.queryForObject("insert into transactions.leisure_assignments (session_id, executor_user_id, role, assigned_by, note) values (?, ?, ?, ?, ?) returning id", UUID.class, sessionId, executor, r, actor, text);
        audit(actor, "PARTNER", partner, "ASSIGNMENT_OFFERED", id, r);
        return db.query(SELECT + " where a.id = ?", LeisureExecutorService::map, id).get(0);
    }

    @Transactional(readOnly = true)
    public List<Assignment> forSession(UUID actor, UUID partner, UUID sessionId) {
        partners.requireProcessing(actor, partner);
        return db.query(SELECT + " where s.id = ? and v.partner_id = ? order by a.created_at desc", LeisureExecutorService::map, sessionId, partner);
    }

    @Transactional
    public Assignment partnerCancel(UUID actor, UUID partner, UUID id) {
        partners.requireProcessing(actor, partner, MANAGE);
        String status = db.query("select a.status from transactions.leisure_assignments a join marketplace.leisure_sessions s on s.id = a.session_id join marketplace.leisure_events e on e.id = s.event_id "
                + "join marketplace.leisure_venues v on v.id = e.venue_id where a.id = ? and v.partner_id = ? for update of a", (rs, n) -> rs.getString(1), id, partner)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ASSIGNMENT_NOT_FOUND", "Not found"));
        if (List.of("OFFERED", "ACCEPTED").contains(status)) {
            db.update("update transactions.leisure_assignments set status = 'CANCELLED', updated_at = now(), version = version + 1 where id = ?", id);
            audit(actor, "PARTNER", partner, "ASSIGNMENT_CANCELLED", id, null);
        } else if (!"CANCELLED".equals(status)) {
            throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "An assignment in progress or finished cannot be cancelled");
        }
        return db.query(SELECT + " where a.id = ?", LeisureExecutorService::map, id).get(0);
    }

    // ---- executor side -------------------------------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<Assignment> mine(UUID executor, String scope) {
        String filter = "history".equals(scope) ? "a.status in ('DECLINED', 'COMPLETED', 'CANCELLED')" : "a.status in ('OFFERED', 'ACCEPTED', 'STARTED')";
        return db.query(SELECT + " where a.executor_user_id = ? and " + filter + " order by s.starts_at " + ("history".equals(scope) ? "desc" : "asc") + " limit 100", LeisureExecutorService::map, executor);
    }

    public enum Step { ACCEPT, DECLINE, START, COMPLETE, CANCEL }

    @Transactional
    public Assignment step(UUID executor, UUID id, Step step) {
        var row = db.query("select a.status, s.starts_at, s.ends_at, v.partner_id from transactions.leisure_assignments a join marketplace.leisure_sessions s on s.id = a.session_id "
                + "join marketplace.leisure_events e on e.id = s.event_id join marketplace.leisure_venues v on v.id = e.venue_id where a.id = ? and a.executor_user_id = ? for update of a",
                (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, OffsetDateTime.class), rs.getObject(3, OffsetDateTime.class), rs.getObject(4, UUID.class)}, id, executor)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ASSIGNMENT_NOT_FOUND", "Not found"));
        String status = (String) row[0];
        OffsetDateTime starts = (OffsetDateTime) row[1];
        OffsetDateTime now = OffsetDateTime.now();
        String to = switch (step) {
            case ACCEPT -> "ACCEPTED";
            case DECLINE -> "DECLINED";
            case START -> "STARTED";
            case COMPLETE -> "COMPLETED";
            case CANCEL -> "CANCELLED";
        };
        if (to.equals(status)) { return db.query(SELECT + " where a.id = ?", LeisureExecutorService::map, id).get(0); } // idempotent repeat
        boolean allowed = switch (step) {
            case ACCEPT, DECLINE -> "OFFERED".equals(status) && now.isBefore((OffsetDateTime) row[2]);
            case START -> "ACCEPTED".equals(status);
            case COMPLETE -> "STARTED".equals(status);
            case CANCEL -> "ACCEPTED".equals(status) && now.isBefore(starts);
        };
        if (!allowed) { throw new ApiException(HttpStatus.CONFLICT, "STATUS_CONFLICT", "This step is not possible now"); }
        if (step == Step.START && (now.isBefore(starts.minusHours(2)) || !now.isBefore((OffsetDateTime) row[2]))) {
            throw new ApiException(HttpStatus.CONFLICT, "OUTSIDE_WORK_WINDOW", "Work can be started from 2 hours before the start until the end");
        }
        db.update("update transactions.leisure_assignments set status = ?, updated_at = now(), version = version + 1 where id = ?", to, id);
        audit(executor, "EXECUTOR", (UUID) row[3], "ASSIGNMENT_" + to, id, null);
        return db.query(SELECT + " where a.id = ?", LeisureExecutorService::map, id).get(0);
    }
}
