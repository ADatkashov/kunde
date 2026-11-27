package kz.kunde.flowers;

import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Status changes of a flowers order made by the shop side: PLACED -&gt; ACCEPTED -&gt; ASSEMBLING (ready for a courier; the
 * courier task opens here). The Partner API (ADR-026 step 5) calls {@link #accept} and {@link #startAssembling}; until a
 * shop is operated by a real partner, orders of SYNTHETIC demo shops advance on their own, one step per
 * {@code app.flowers.simulation-step-seconds} (0 switches the simulation off). A scheduled order starts two hours before its window.
 */
@Service
public class FlowersFulfillmentService {
    private final JdbcTemplate db;
    private final int stepSeconds;

    public FlowersFulfillmentService(JdbcTemplate db, @Value("${app.flowers.simulation-step-seconds:20}") int stepSeconds) {
        this.db = db;
        this.stepSeconds = stepSeconds;
    }

    private void event(UUID orderId, String status, String actor, UUID actorUser) {
        db.update("insert into transactions.flowers_order_events (order_id, status, actor_type, actor_user_id) values (?, ?, ?, ?)",
                orderId, status, actor, actorUser);
    }

    private boolean move(UUID orderId, String from, String to) {
        int rows = db.update("update transactions.flowers_orders set status = ?, updated_at = now(), version = version + 1 where id = ? and status = ?",
                to, orderId, from);
        return rows == 1;
    }

    /** The shop accepts a placed order. */
    @Transactional
    public void accept(UUID orderId, String actor, UUID actorUser) {
        if (!move(orderId, "PLACED", "ACCEPTED")) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_STATE_INVALID", "The order cannot be accepted now");
        }
        event(orderId, "ACCEPTED", actor, actorUser);
    }

    /** The order is assembled and waits for a courier: ASSEMBLING, and an OPEN courier task appears (idempotent). */
    @Transactional
    public void startAssembling(UUID orderId, String actor, UUID actorUser) {
        if (!move(orderId, "ACCEPTED", "ASSEMBLING")) {
            throw new ApiException(HttpStatus.CONFLICT, "ORDER_STATE_INVALID", "The order cannot be assembled now");
        }
        event(orderId, "ASSEMBLING", actor, actorUser);
        db.update("insert into transactions.flowers_courier_tasks (order_id) values (?) on conflict (order_id) do nothing", orderId);
    }

    /** DEV simulation for demo shops: moves the order as far as the elapsed time allows. Safe to call on every read. */
    @Transactional
    public void advance(UUID orderId) {
        if (stepSeconds <= 0) {
            return;
        }
        var row = db.query("""
                select o.status, extract(epoch from (now() - greatest(o.placed_at, coalesce(o.scheduled_from - interval '2 hours', o.placed_at))))::bigint
                from transactions.flowers_orders o join marketplace.flowers_shops s on s.id = o.shop_id
                where o.id = ? and s.is_synthetic and s.partner_id is null and o.status in ('PLACED', 'ACCEPTED')
                for update of o
                """, (rs, n) -> new Object[] {rs.getString(1), rs.getLong(2)}, orderId).stream().findFirst();
        if (row.isEmpty()) {
            return;
        }
        long elapsed = (Long) row.get()[1];
        String status = (String) row.get()[0];
        if ("PLACED".equals(status) && elapsed >= stepSeconds) {
            accept(orderId, "SYSTEM", null);
            status = "ACCEPTED";
        }
        if ("ACCEPTED".equals(status) && elapsed >= 2L * stepSeconds) {
            startAssembling(orderId, "SYSTEM", null);
        }
    }
}
