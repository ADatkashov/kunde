package kz.kunde.food;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Courier hand-off of partner-owned delivery orders (Groceries and Food). A task is OPEN while the order waits for a courier,
 * ASSIGNED to exactly one approved online courier (atomic claim, repeat requests by the winner are replays), PICKED_UP when the
 * courier collected it (the order goes ON_THE_WAY) and DELIVERED when handed to the customer (the order is DELIVERED).
 * Couriers see the store and the area before accepting; the customer's address only after acceptance. No distances are shown:
 * stores have no stored coordinates, and no GPS or ETA is invented.
 */
@Service
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodCourierService {
    public record Task(String id, String orderId, String shortRef, String status, String storeName, String storeAddress,
            String deliveryAddress, String deliveryLabel, String comment, int itemCount, long totalMinor,
            String paymentMethod, String paymentStatus, boolean collectOnDelivery, OffsetDateTime createdAt,
            OffsetDateTime assignedAt, OffsetDateTime pickedUpAt, OffsetDateTime deliveredAt, String vertical) {}

    private static final String SELECT = """
            select t.id, t.order_id, t.status, r.name, r.address_text, o.address_text, o.address_label, o.comment,
                   (select coalesce(sum(i.quantity) filter (where i.unit = 'PIECE'), 0) + count(*) filter (where i.unit = 'KG')
                      from transactions.food_order_items i where i.order_id = o.id and i.fulfillment_status in ('OK', 'SUBSTITUTED')),
                   coalesce(o.final_total_minor, o.total_minor), o.payment_method, o.payment_status, t.created_at, t.assigned_at,
                   t.picked_up_at, t.delivered_at, o.vertical, t.courier_id
            from transactions.food_courier_tasks t
            join transactions.food_orders o on o.id = t.order_id
            join marketplace.food_restaurants r on r.id = o.restaurant_id
            """;

    private final JdbcTemplate db;

    public FoodCourierService(JdbcTemplate db) { this.db = db; }

    /** Opens the task for an order that is ready for a courier (idempotent). */
    @Transactional
    public void openTask(UUID orderId) {
        db.update("insert into transactions.food_courier_tasks (order_id) values (?) on conflict (order_id) do nothing", orderId);
    }

    /** The order was cancelled: its task closes (a courier that already accepted is released by the CANCELLED status). */
    @Transactional
    public void cancel(UUID orderId) {
        db.update("update transactions.food_courier_tasks set status = 'CANCELLED', version = version + 1 where order_id = ? and status in ('OPEN', 'ASSIGNED')", orderId);
    }

    private void requireApprovedCourier(UUID courier, boolean online) {
        Integer ok = db.queryForObject("""
                select count(*) from transactions.delivery_couriers where user_id = ? and status = 'APPROVED' and (not ? or online)
                """, Integer.class, courier, online);
        if (ok == null || ok == 0) {
            throw new ApiException(HttpStatus.FORBIDDEN, "COURIER_NOT_APPROVED", "An approved courier profile is required");
        }
    }

    /** Open tasks for an approved, online courier: store and area only. */
    @Transactional(readOnly = true)
    public List<Task> open(UUID courier) {
        requireApprovedCourier(courier, true);
        return db.query(SELECT + " where t.status = 'OPEN' and o.status = 'READY_FOR_PICKUP' order by t.created_at, t.id limit 30",
                (rs, n) -> map(rs, false, null));
    }

    @Transactional(readOnly = true)
    public List<Task> mine(UUID courier) {
        requireApprovedCourier(courier, false);
        return db.query(SELECT + " where t.courier_id = ? order by (t.status in ('ASSIGNED', 'PICKED_UP')) desc, t.created_at desc, t.id limit 50",
                (rs, n) -> map(rs, true, courier), courier);
    }

    private static Task map(java.sql.ResultSet rs, boolean full, UUID viewer) throws java.sql.SQLException {
        String status = rs.getString(3);
        boolean reveal = full && !"CANCELLED".equals(status);
        String paymentMethod = rs.getString(11);
        String paymentStatus = rs.getString(12);
        UUID orderId = rs.getObject(2, UUID.class);
        return new Task(rs.getString(1), orderId.toString(), orderId.toString().substring(0, 8).toUpperCase(), status,
                rs.getString(4), rs.getString(5), reveal ? rs.getString(6) : null, reveal ? rs.getString(7) : null,
                reveal ? rs.getString(8) : null, rs.getInt(9), rs.getLong(10), paymentMethod, paymentStatus,
                "CASH_ON_DELIVERY".equals(paymentMethod) && "PAY_ON_RECEIPT".equals(paymentStatus),
                rs.getObject(13, OffsetDateTime.class), rs.getObject(14, OffsetDateTime.class),
                rs.getObject(15, OffsetDateTime.class), rs.getObject(16, OffsetDateTime.class), rs.getString(17));
    }

    private Task get(UUID id, UUID courier) {
        return db.query(SELECT + " where t.id = ?", (rs, n) -> map(rs, true, courier), id).stream().findFirst().orElseThrow();
    }

    /** Atomic claim: the first approved online courier wins; the winner's repeat request is a replay, anyone else gets 409. */
    @Transactional
    public Task accept(UUID courier, UUID taskId) {
        requireApprovedCourier(courier, true);
        var task = db.query("select status, courier_id, order_id from transactions.food_courier_tasks where id = ? for update",
                (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class), rs.getObject(3, UUID.class)}, taskId)
                .stream().findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "TASK_NOT_FOUND", "Task not found"));
        if (courier.equals(task[1]) && !"CANCELLED".equals(task[0])) {
            return get(taskId, courier);
        }
        if (!"OPEN".equals(task[0])) {
            throw new ApiException(HttpStatus.CONFLICT, "TASK_UNAVAILABLE", "The task was taken or cancelled");
        }
        Integer busy = db.queryForObject("select count(*) from transactions.food_courier_tasks where courier_id = ? and status in ('ASSIGNED', 'PICKED_UP')",
                Integer.class, courier);
        if (busy != null && busy >= 3) {
            throw new ApiException(HttpStatus.CONFLICT, "COURIER_BUSY", "Finish your current tasks first");
        }
        db.update("update transactions.food_courier_tasks set status = 'ASSIGNED', courier_id = ?, assigned_at = now(), version = version + 1 where id = ?",
                courier, taskId);
        db.update("insert into transactions.food_order_events (order_id, status, actor_type, actor_user_id, reason) values (?, 'READY_FOR_PICKUP', 'COURIER', ?, 'COURIER_ASSIGNED')",
                task[2], courier);
        return get(taskId, courier);
    }

    private Object[] ownedTask(UUID courier, UUID taskId) {
        return db.query("select t.status, t.order_id, o.status from transactions.food_courier_tasks t join transactions.food_orders o on o.id = t.order_id where t.id = ? and t.courier_id = ? for update of t, o",
                (rs, n) -> new Object[] {rs.getString(1), rs.getObject(2, UUID.class), rs.getString(3)}, taskId, courier).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "TASK_NOT_FOUND", "Task not found"));
    }

    /** The courier collected the order at the store: the order is ON_THE_WAY. */
    @Transactional
    public Task pickUp(UUID courier, UUID taskId) {
        var t = ownedTask(courier, taskId);
        if ("PICKED_UP".equals(t[0])) { return get(taskId, courier); }
        if (!"ASSIGNED".equals(t[0]) || !"READY_FOR_PICKUP".equals(t[2])) {
            throw new ApiException(HttpStatus.CONFLICT, "TASK_STATE_INVALID", "The order cannot be picked up now");
        }
        db.update("update transactions.food_courier_tasks set status = 'PICKED_UP', picked_up_at = now(), version = version + 1 where id = ?", taskId);
        db.update("update transactions.food_orders set status = 'ON_THE_WAY', updated_at = now(), version = version + 1 where id = ?", t[1]);
        db.update("insert into transactions.food_order_events (order_id, status, actor_type, actor_user_id) values (?, 'ON_THE_WAY', 'COURIER', ?)", t[1], courier);
        return get(taskId, courier);
    }

    /** Handed to the customer: the order is DELIVERED (cash on delivery is collected here and recorded as paid). */
    @Transactional
    public Task deliver(UUID courier, UUID taskId) {
        var t = ownedTask(courier, taskId);
        if ("DELIVERED".equals(t[0])) { return get(taskId, courier); }
        if (!"PICKED_UP".equals(t[0]) || !"ON_THE_WAY".equals(t[2])) {
            throw new ApiException(HttpStatus.CONFLICT, "TASK_STATE_INVALID", "The order is not on its way");
        }
        db.update("update transactions.food_courier_tasks set status = 'DELIVERED', delivered_at = now(), version = version + 1 where id = ?", taskId);
        db.update("update transactions.food_orders set status = 'DELIVERED', updated_at = now(), version = version + 1 where id = ?", t[1]);
        db.update("insert into transactions.food_order_events (order_id, status, actor_type, actor_user_id) values (?, 'DELIVERED', 'COURIER', ?)", t[1], courier);
        return get(taskId, courier);
    }
}
