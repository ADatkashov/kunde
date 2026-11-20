package kz.kunde.leisure;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * DEV/TEST payment contract of Leisure. There is no provider and no card data: {@code TEST_CARD} writes ledger entries only
 * (hold -> capture -> refund / void), {@code PAY_ON_SITE} writes nothing and is never shown as a payment. The test method is refused
 * outside dev/local/test, so no real charge can ever be simulated as a real one. Every transition is idempotent and runs in the caller's
 * transaction, so an order state change and its payment state change commit or roll back together.
 */
@Component
public class LeisurePayments {
    public static final String PAY_ON_SITE = "PAY_ON_SITE";
    public static final String TEST_CARD = "TEST_CARD";

    public record PaymentView(String method, String status, long heldMinor, long capturedMinor, long refundedMinor, String mode) {}

    public record Entry(String paymentId, String orderId, String method, String status, long heldMinor, long capturedMinor, long refundedMinor,
            OffsetDateTime updatedAt) {}

    private final JdbcTemplate db;
    private final LeisureFlags flags;

    public LeisurePayments(JdbcTemplate db, LeisureFlags flags) {
        this.db = db;
        this.flags = flags;
    }

    /** Validates the requested method (null means pay on site). */
    public String method(String requested) {
        if (requested == null || requested.isBlank() || PAY_ON_SITE.equals(requested)) { return PAY_ON_SITE; }
        if (!TEST_CARD.equals(requested) || !flags.testPaymentsAllowed()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PAYMENT_METHOD_UNSUPPORTED",
                    "Payment method unsupported; test payments exist only in DEV/TEST environments");
        }
        return TEST_CARD;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public void open(UUID user, UUID orderId, String method, long amountMinor) {
        boolean test = TEST_CARD.equals(method);
        UUID id = db.queryForObject("insert into transactions.leisure_payments (user_id, order_id, method, status, held_minor) values (?, ?, ?, ?, ?) returning id",
                UUID.class, user, orderId, method, test ? "TEST_HELD" : PAY_ON_SITE, test ? amountMinor : 0);
        if (test) { entry(id, "HOLD", amountMinor, "CUSTOMER", user, null); }
    }

    /** Captures a held payment (booking confirmed). No-op for pay on site and for repeats. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void capture(UUID orderId, String actorType, UUID actor) {
        var p = lock(orderId);
        if (p == null || !"TEST_HELD".equals(p.status)) { return; }
        db.update("update transactions.leisure_payments set status = 'TEST_CAPTURED', captured_minor = held_minor, updated_at = now() where id = ?", p.id);
        entry(p.id, "CAPTURE", p.held, actorType, actor, null);
    }

    /** Releases a hold that was never captured (rejection of a pending booking). */
    @Transactional(propagation = Propagation.MANDATORY)
    public void voidHold(UUID orderId, String actorType, UUID actor, String reason) {
        var p = lock(orderId);
        if (p == null || !"TEST_HELD".equals(p.status)) { return; }
        db.update("update transactions.leisure_payments set status = 'TEST_VOIDED', updated_at = now() where id = ?", p.id);
        entry(p.id, "VOID", p.held, actorType, actor, reason);
    }

    /** Refunds everything still refundable of a captured test payment; a held one is voided. Used for cancellations. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void refundAll(UUID orderId, String actorType, UUID actor, String reason) {
        var p = lock(orderId);
        if (p == null) { return; }
        if ("TEST_HELD".equals(p.status)) {
            voidHold(orderId, actorType, actor, reason);
            return;
        }
        if ("TEST_CAPTURED".equals(p.status) || "TEST_PART_REFUNDED".equals(p.status)) {
            long left = db.queryForObject("select captured_minor - refunded_minor from transactions.leisure_payments where id = ?", Long.class, p.id);
            if (left > 0) {
                db.update("update transactions.leisure_payments set refunded_minor = captured_minor, status = 'TEST_REFUNDED', updated_at = now() where id = ?", p.id);
                entry(p.id, "REFUND", left, actorType, actor, reason);
            }
        }
    }

    /** Administrator refund of a captured TEST payment, full or partial, never above what is left. */
    @Transactional
    public PaymentView refund(UUID admin, UUID paymentId, long amountMinor, String reason) {
        String text = reason == null ? "" : reason.strip();
        if (text.isEmpty() || text.length() > 200) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_REQUIRED", "A reason of 1-200 characters is required");
        }
        var row = db.query("select method, status, captured_minor, refunded_minor from transactions.leisure_payments where id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getString(2), rs.getLong(3), rs.getLong(4)}, paymentId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "PAYMENT_NOT_FOUND", "Payment not found"));
        if (!TEST_CARD.equals(row[0]) || !("TEST_CAPTURED".equals(row[1]) || "TEST_PART_REFUNDED".equals(row[1]))) {
            throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_NOT_REFUNDABLE", "Only a captured test payment can be refunded");
        }
        long left = (long) row[2] - (long) row[3];
        if (amountMinor <= 0 || amountMinor > left) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REFUND_AMOUNT_INVALID", "The refund must be between 1 tiyn and the amount still refundable");
        }
        long refunded = (long) row[3] + amountMinor;
        db.update("update transactions.leisure_payments set refunded_minor = ?, status = ?, updated_at = now() where id = ?", refunded,
                refunded == (long) row[2] ? "TEST_REFUNDED" : "TEST_PART_REFUNDED", paymentId);
        entry(paymentId, "REFUND", amountMinor, "ADMIN", admin, text);
        db.update("insert into marketplace.leisure_audit (actor_user_id, actor_type, action, target, detail) values (?, 'ADMIN', 'PAYMENT_REFUNDED', ?, ?)",
                admin, paymentId.toString(), amountMinor + ": " + text);
        return view(paymentId);
    }

    @Transactional(readOnly = true)
    public PaymentView ofOrder(UUID orderId) {
        return db.query("select method, status, held_minor, captured_minor, refunded_minor from transactions.leisure_payments where order_id = ?",
                (rs, n) -> map(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getLong(4), rs.getLong(5)), orderId).stream().findFirst().orElse(null);
    }

    @Transactional(readOnly = true)
    public List<Entry> latest(boolean refundableOnly) {
        return db.query("""
                select id, order_id, method, status, held_minor, captured_minor, refunded_minor, updated_at from transactions.leisure_payments
                where method = 'TEST_CARD' and (not ? or status in ('TEST_CAPTURED', 'TEST_PART_REFUNDED')) order by updated_at desc limit 100
                """, (rs, n) -> new Entry(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getLong(5), rs.getLong(6), rs.getLong(7),
                rs.getObject(8, OffsetDateTime.class)), refundableOnly);
    }

    private PaymentView view(UUID id) {
        return db.query("select method, status, held_minor, captured_minor, refunded_minor from transactions.leisure_payments where id = ?",
                (rs, n) -> map(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getLong(4), rs.getLong(5)), id).get(0);
    }

    private static PaymentView map(String method, String status, long held, long captured, long refunded) {
        return new PaymentView(method, status, held, captured, refunded, TEST_CARD.equals(method) ? "DEV_TEST" : "ON_SITE");
    }

    private record Locked(UUID id, String status, long held) {}

    private Locked lock(UUID orderId) {
        return db.query("select id, status, held_minor from transactions.leisure_payments where order_id = ? for update",
                (rs, n) -> new Locked(rs.getObject(1, UUID.class), rs.getString(2), rs.getLong(3)), orderId).stream().findFirst().orElse(null);
    }

    private void entry(UUID payment, String kind, long amount, String actorType, UUID actor, String reason) {
        db.update("insert into transactions.leisure_payment_events (payment_id, kind, amount_minor, actor_type, actor_user_id, reason) values (?, ?, ?, ?, ?, ?)",
                payment, kind, amount, actorType, actor, reason);
    }
}
