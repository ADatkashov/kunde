package kz.kunde.support;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Consumer-owned support cases (SUP-001). Every query is scoped to the authenticated owner; a case of
 * another user is indistinguishable from a missing one. Not linked to transactions and has no staff side.
 */
@Service
@ConditionalOnProperty(name = "app.identity.consumer-enabled", havingValue = "true")
public class SupportCaseService {
    /** Technical abuse guard, not a product or SLA policy. */
    static final int MAX_ACTIVE_CASES = 10;
    static final int MAX_PAGE = 100;

    public enum Category { GENERAL, ACCOUNT, PRIVACY, APP_PROBLEM }

    public record CaseView(UUID id, String category, String message, String status,
                           OffsetDateTime createdAt, OffsetDateTime updatedAt) {}

    public record Created(CaseView view, boolean created) {}

    private static final RowMapper<CaseView> MAPPER = (rs, row) -> new CaseView(
            rs.getObject("id", UUID.class), rs.getString("category"), rs.getString("message"),
            rs.getString("status"), rs.getObject("created_at", OffsetDateTime.class),
            rs.getObject("updated_at", OffsetDateTime.class));

    private final JdbcTemplate db;
    private final ConsumerIdentityService identity;

    public SupportCaseService(JdbcTemplate db, ConsumerIdentityService identity) {
        this.db = db;
        this.identity = identity;
    }

    @Transactional
    public Created open(Jwt principal, String idempotencyKey, Category category, String message) {
        if (idempotencyKey == null || !idempotencyKey.matches("[A-Za-z0-9_-]{16,64}")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_IDEMPOTENCY_KEY",
                    "Idempotency-Key must be 16-64 characters: letters, digits, '-' or '_'");
        }
        String text = message == null ? "" : message.strip();
        if (text.isEmpty() || text.length() > 2000) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CASE_MESSAGE",
                    "Message must be 1-2000 characters");
        }
        UUID owner = identity.get(principal).id();
        // One lock per owner (not per key): both the idempotency lookup and the case cap must be
        // evaluated serially, otherwise concurrent requests with different keys exceed the cap.
        db.query("SELECT pg_advisory_xact_lock(hashtext(?), hashtext(?))", (RowCallbackHandler) rs -> {},
                "support.cases.open", owner.toString());
        String hash = sha256(category.name() + "\n" + text);
        List<Object[]> existing = db.query("""
                SELECT id, request_sha256 FROM support.cases
                WHERE owner_user_id = ? AND idempotency_key = ?
                """, (rs, row) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2)},
                owner, idempotencyKey);
        if (!existing.isEmpty()) {
            if (!hash.equals(existing.get(0)[1])) {
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED",
                        "Idempotency-Key was already used for a different request");
            }
            return new Created(find(owner, (UUID) existing.get(0)[0]), false);
        }
        Integer active = db.queryForObject(
                "SELECT count(*) FROM support.cases WHERE owner_user_id = ?", Integer.class, owner);
        if (active != null && active >= MAX_ACTIVE_CASES) {
            throw new ApiException(HttpStatus.CONFLICT, "CASE_LIMIT_REACHED",
                    "Too many open support cases");
        }
        UUID id = db.queryForObject("""
                INSERT INTO support.cases (owner_user_id, category, message, idempotency_key, request_sha256)
                VALUES (?, ?, ?, ?, ?) RETURNING id
                """, UUID.class, owner, category.name(), text, idempotencyKey, hash);
        db.update("INSERT INTO support.case_events (case_id, event_type) VALUES (?, 'CREATED')", id);
        return new Created(find(owner, id), true);
    }

    @Transactional
    public List<CaseView> list(Jwt principal, int limit, int offset) {
        if (limit < 1 || limit > MAX_PAGE || offset < 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PAGE", "limit 1-100, offset >= 0");
        }
        UUID owner = identity.get(principal).id();
        return db.query("""
                SELECT id, category, message, status, created_at, updated_at FROM support.cases
                WHERE owner_user_id = ? ORDER BY created_at DESC, id LIMIT ? OFFSET ?
                """, MAPPER, owner, limit, offset);
    }

    @Transactional
    public CaseView get(Jwt principal, UUID id) {
        return find(identity.get(principal).id(), id);
    }

    /** Records the consumer's request to escalate. Idempotent; does not promise a response time. */
    @Transactional
    public CaseView requestEscalation(Jwt principal, UUID id) {
        UUID owner = identity.get(principal).id();
        String status = db.query("""
                SELECT status FROM support.cases WHERE id = ? AND owner_user_id = ? FOR UPDATE
                """, rs -> rs.next() ? rs.getString(1) : null, id, owner);
        if (status == null) {
            throw notFound();
        }
        if ("OPEN".equals(status)) {
            db.update("UPDATE support.cases SET status = 'ESCALATION_REQUESTED', updated_at = now() WHERE id = ?", id);
            db.update("INSERT INTO support.case_events (case_id, event_type) VALUES (?, 'ESCALATION_REQUESTED')", id);
        }
        return find(owner, id);
    }

    private CaseView find(UUID owner, UUID id) {
        List<CaseView> rows = db.query("""
                SELECT id, category, message, status, created_at, updated_at FROM support.cases
                WHERE id = ? AND owner_user_id = ?
                """, MAPPER, id, owner);
        if (rows.isEmpty()) {
            throw notFound();
        }
        return rows.get(0);
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "CASE_NOT_FOUND", "Support case not found");
    }

    private static String sha256(String value) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
