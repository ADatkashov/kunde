package kz.kunde.support;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import kz.kunde.platform.support.SupportCaseDirectory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;

/** In-process adapter of {@link SupportCaseDirectory}: the only code outside consumer flows that touches support tables. */
@Service
public class JdbcSupportCaseDirectory implements SupportCaseDirectory {
    private static final RowMapper<Case> CASE = (rs, row) -> new Case(rs.getObject("id", UUID.class),
            rs.getObject("subject_id", UUID.class), rs.getString("category"), rs.getString("message"),
            rs.getString("status"), rs.getObject("created_at", OffsetDateTime.class));

    private final JdbcTemplate db;

    public JdbcSupportCaseDirectory(JdbcTemplate db) {
        this.db = db;
    }

    /** Column is chosen from a closed enum, never from input. */
    private static String column(Subject subject) {
        return switch (subject) {
            case RIDE -> "ride_id";
            case DELIVERY -> "delivery_id";
        };
    }

    private static String select(Subject subject) {
        return "select id, " + column(subject) + " as subject_id, category, message, status, created_at from support.cases where "
                + column(subject) + " is not null";
    }

    @Override
    public List<Case> list(Subject subject, int limit) {
        return db.query(select(subject) + " order by (status <> 'RESOLVED') desc, created_at desc, id limit ?", CASE, limit);
    }

    @Override
    public Optional<Case> find(Subject subject, UUID caseId) {
        return db.query(select(subject) + " and id = ?", CASE, caseId).stream().findFirst();
    }

    @Override
    public Optional<Case> resolve(Subject subject, UUID caseId, UUID reviewer) {
        Optional<Case> current = db.query(select(subject) + " and id = ? for update", CASE, caseId).stream().findFirst();
        if (current.isEmpty() || "RESOLVED".equals(current.get().status())) {
            return current;
        }
        db.update("update support.cases set status = 'RESOLVED', updated_at = statement_timestamp() where id = ?", caseId);
        db.update("insert into support.case_events (case_id, event_type, actor_user_id) values (?, 'RESOLVED', ?)", caseId, reviewer);
        Case c = current.get();
        return Optional.of(new Case(c.id(), c.subjectId(), c.category(), c.message(), "RESOLVED", c.createdAt()));
    }

    @Override
    public List<CaseEvent> events(Subject subject, UUID caseId, int limit) {
        if (find(subject, caseId).isEmpty()) {
            return List.of();
        }
        return db.query("""
                select event_type, actor_user_id, occurred_at from support.case_events
                where case_id = ? order by id limit ?
                """, (rs, row) -> new CaseEvent(rs.getString(1), rs.getObject(2, UUID.class),
                        rs.getObject(3, OffsetDateTime.class)), caseId, limit);
    }
}
