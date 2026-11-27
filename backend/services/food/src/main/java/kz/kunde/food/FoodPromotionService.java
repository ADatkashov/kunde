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
 * Food promotions and promo codes. The discount is always computed here from the stored promotion; the client only
 * sends the code. One code per order (no stacking). The discount applies to the items subtotal, never to delivery, and
 * is capped by the subtotal. Redemptions are counted per user and in total; cancelling an order releases its redemption.
 */
@Service
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodPromotionService {
    /** Partner-created promotions are limited so a partner cannot publish an absurd offer (Admin can still disable). */
    public static final int PARTNER_MAX_PERCENT = 50;
    public static final long PARTNER_MAX_FIXED_MINOR = 500_000;
    public static final int PARTNER_MAX_DAYS = 90;

    public record Evaluated(UUID promotionId, String code, String title, long discountMinor) {}

    public record PromotionView(String id, String code, String title, String description, String kind, long value,
            Long maxDiscountMinor, long minSubtotalMinor, String restaurantId, String restaurantName, String cuisine,
            OffsetDateTime startsAt, OffsetDateTime endsAt, Integer maxRedemptions, int redeemed, int perUserLimit,
            String status, boolean banner, boolean synthetic, boolean partnerOwned) {}

    private final JdbcTemplate db;

    public FoodPromotionService(JdbcTemplate db) { this.db = db; }

    static String normalize(String code) {
        return code == null ? "" : code.strip().toUpperCase(java.util.Locale.ROOT);
    }

    private static ApiException invalid(String code, String message) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, code, message);
    }

    /** Validates the code for this cart and returns the discount; throws a specific 422 when it cannot be applied. */
    @Transactional
    public Evaluated evaluate(String rawCode, UUID restaurantId, long subtotalMinor, UUID user, boolean lock) {
        String code = normalize(rawCode);
        var row = db.query("""
                select p.id, p.title, p.kind, p.value, p.max_discount_minor, p.min_subtotal_minor, p.restaurant_id, p.cuisine,
                       p.starts_at <= now() and p.ends_at > now() as in_window, p.max_redemptions, p.per_user_limit, p.status,
                       r.cuisine
                from marketplace.food_promotions p, marketplace.food_restaurants r
                where p.code = ? and r.id = ?""" + (lock ? " for update of p" : ""),
                (rs, n) -> new Object[] {rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), rs.getLong(4),
                        rs.getObject(5, Long.class), rs.getLong(6), rs.getObject(7, UUID.class), rs.getString(8),
                        rs.getBoolean(9), rs.getObject(10, Integer.class), rs.getInt(11), rs.getString(12), rs.getString(13)},
                code, restaurantId).stream().findFirst()
                .orElseThrow(() -> invalid("PROMO_NOT_FOUND", "Promo code not found"));
        if (!"ACTIVE".equals(row[11])) { throw invalid("PROMO_NOT_FOUND", "Promo code not found"); }
        if (!(boolean) row[8]) { throw invalid("PROMO_EXPIRED", "Promo code is not valid now"); }
        if ((row[6] != null && !row[6].equals(restaurantId)) || (row[7] != null && !row[7].equals(row[12]))) {
            throw invalid("PROMO_NOT_APPLICABLE", "Promo code does not apply to this restaurant");
        }
        if (subtotalMinor < (long) row[5]) {
            throw invalid("PROMO_MIN_SUBTOTAL", "Order total is below the promo minimum");
        }
        UUID id = (UUID) row[0];
        if (row[9] != null) {
            Integer used = db.queryForObject("select count(*) from transactions.food_promo_redemptions where promotion_id = ? and released_at is null",
                    Integer.class, id);
            if (used != null && used >= (Integer) row[9]) { throw invalid("PROMO_EXHAUSTED", "Promo code has been fully used"); }
        }
        if (user != null) {
            Integer mine = db.queryForObject("select count(*) from transactions.food_promo_redemptions where promotion_id = ? and user_id = ? and released_at is null",
                    Integer.class, id, user);
            if (mine != null && mine >= (int) row[10]) { throw invalid("PROMO_ALREADY_USED", "You have already used this promo code"); }
        }
        long value = (long) row[3];
        long discount = "PERCENT".equals(row[2]) ? subtotalMinor * value / 100 : value;
        if (row[4] != null) { discount = Math.min(discount, (Long) row[4]); }
        discount = Math.min(discount, subtotalMinor);
        if (discount <= 0) { throw invalid("PROMO_NOT_APPLICABLE", "Promo code gives no discount for this cart"); }
        return new Evaluated(id, code, (String) row[1], discount);
    }

    /** Records the redemption under a row lock on the promotion so concurrent orders cannot exceed the limits. */
    @Transactional
    public void redeem(String code, UUID orderId, UUID user, long discountMinor) {
        UUID restaurant = db.queryForObject("select restaurant_id from transactions.food_orders where id = ?", UUID.class, orderId);
        long subtotal = db.queryForObject("select subtotal_minor from transactions.food_orders where id = ?", Long.class, orderId);
        Evaluated locked = evaluate(code, restaurant, subtotal, user, true);
        if (locked.discountMinor() != discountMinor) {
            throw new ApiException(HttpStatus.CONFLICT, "FOOD_PRICE_CHANGED", "The total changed; refresh the cart");
        }
        db.update("insert into transactions.food_promo_redemptions (promotion_id, order_id, user_id, discount_minor) values (?, ?, ?, ?)",
                locked.promotionId(), orderId, user, discountMinor);
    }

    @Transactional
    public void release(UUID orderId) {
        db.update("update transactions.food_promo_redemptions set released_at = now() where order_id = ? and released_at is null", orderId);
    }

    // ---- reads / management --------------------------------------------------------------------------------

    private static final String VIEW_SELECT = """
            select p.id, p.code, p.title, p.description, p.kind, p.value, p.max_discount_minor, p.min_subtotal_minor,
                   p.restaurant_id, r.name, p.cuisine, p.starts_at, p.ends_at, p.max_redemptions,
                   (select count(*) from transactions.food_promo_redemptions x where x.promotion_id = p.id and x.released_at is null),
                   p.per_user_limit, p.status, p.banner, p.is_synthetic, p.owner_partner_id is not null
            from marketplace.food_promotions p left join marketplace.food_restaurants r on r.id = p.restaurant_id
            """;

    private static PromotionView map(java.sql.ResultSet rs, int n) throws java.sql.SQLException {
        return new PromotionView(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5),
                rs.getLong(6), rs.getObject(7, Long.class), rs.getLong(8), rs.getString(9), rs.getString(10), rs.getString(11),
                rs.getObject(12, OffsetDateTime.class), rs.getObject(13, OffsetDateTime.class), rs.getObject(14, Integer.class),
                rs.getInt(15), rs.getInt(16), rs.getString(17), rs.getBoolean(18), rs.getBoolean(19), rs.getBoolean(20));
    }

    /** Public: promotions that can be used right now (active, in window, not exhausted). */
    @Transactional(readOnly = true)
    public List<PromotionView> active(UUID restaurantId, String vertical) {
        return db.query(VIEW_SELECT + """
                where p.status = 'ACTIVE' and p.starts_at <= now() and p.ends_at > now()
                  and (p.max_redemptions is null or p.max_redemptions >
                       (select count(*) from transactions.food_promo_redemptions x where x.promotion_id = p.id and x.released_at is null))
                  and (?::uuid is null or p.restaurant_id is null or p.restaurant_id = ?::uuid)
                  and (p.restaurant_id is null or r.vertical = ?)
                  and (p.restaurant_id is null or marketplace.food_restaurant_open(r))
                order by p.banner desc, p.ends_at, p.title limit 30""",
                FoodPromotionService::map, restaurantId, restaurantId, vertical);
    }

    @Transactional(readOnly = true)
    public List<PromotionView> forPartner(UUID partnerId) {
        return db.query(VIEW_SELECT + " where p.owner_partner_id = ? order by p.created_at desc limit 100",
                FoodPromotionService::map, partnerId);
    }

    @Transactional(readOnly = true)
    public List<PromotionView> all(String status) {
        return db.query(VIEW_SELECT + " where (?::text is null or p.status = ?::text) order by p.created_at desc limit 200",
                FoodPromotionService::map, status, status);
    }

    public record CreatePromotion(String code, String title, String description, String kind, long value, Long maxDiscountMinor,
            long minSubtotalMinor, UUID restaurantId, OffsetDateTime startsAt, OffsetDateTime endsAt, Integer maxRedemptions,
            Integer perUserLimit, boolean banner) {}

    /** A partner creates a promotion only for its own restaurant and within the allowed limits. */
    @Transactional
    public PromotionView createForPartner(UUID actor, UUID partnerId, CreatePromotion in) {
        if (in.restaurantId() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "RESTAURANT_REQUIRED", "A partner promotion needs a restaurant");
        }
        Integer own = db.queryForObject("select count(*) from marketplace.food_restaurants where id = ? and partner_id = ?",
                Integer.class, in.restaurantId(), partnerId);
        if (own == null || own == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND", "Restaurant not found");
        }
        OffsetDateTime starts = in.startsAt() == null ? OffsetDateTime.now() : in.startsAt();
        if (in.endsAt() == null || !in.endsAt().isAfter(starts) || in.endsAt().isAfter(starts.plusDays(PARTNER_MAX_DAYS))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PROMO_PERIOD_INVALID", "The promotion must end within " + PARTNER_MAX_DAYS + " days");
        }
        validateKind(in);
        if ("PERCENT".equals(in.kind()) && in.value() > PARTNER_MAX_PERCENT
                || "FIXED".equals(in.kind()) && in.value() > PARTNER_MAX_FIXED_MINOR) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROMO_LIMIT_EXCEEDED", "The discount exceeds the allowed limit for partners");
        }
        UUID id = insert(in, in.startsAt(), partnerId, false);
        audit(actor, "PARTNER", "PROMO_CREATED", id.toString(), in.title());
        return db.query(VIEW_SELECT + " where p.id = ?", FoodPromotionService::map, id).get(0);
    }

    private static void validateKind(CreatePromotion in) {
        if (in.title() == null || in.title().isBlank() || in.title().length() > 120 || !("PERCENT".equals(in.kind()) || "FIXED".equals(in.kind()))
                || in.value() <= 0 || ("PERCENT".equals(in.kind()) && in.value() > 100)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PROMO_INVALID", "Invalid promotion");
        }
        if (in.code() != null && !normalize(in.code()).matches("^[A-Z0-9_-]{3,32}$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PROMO_CODE_INVALID", "Code: 3-32 letters, digits, '-' or '_'");
        }
    }

    UUID insert(CreatePromotion in, OffsetDateTime starts, UUID ownerPartner, boolean synthetic) {
        String code = in.code() == null || in.code().isBlank() ? null : normalize(in.code());
        if (code != null) {
            Integer taken = db.queryForObject("select count(*) from marketplace.food_promotions where code = ?", Integer.class, code);
            if (taken != null && taken > 0) {
                throw new ApiException(HttpStatus.CONFLICT, "PROMO_CODE_TAKEN", "This promo code already exists");
            }
        }
        return db.queryForObject("""
                insert into marketplace.food_promotions (code, title, description, kind, value, max_discount_minor, min_subtotal_minor,
                    restaurant_id, owner_partner_id, starts_at, ends_at, max_redemptions, per_user_limit, banner, is_synthetic)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, coalesce(?::timestamptz, now()), ?, ?, ?, ?, ?) returning id""", UUID.class, code, in.title().strip(),
                in.description() == null ? "" : in.description().strip(), in.kind(), in.value(), in.maxDiscountMinor(),
                in.minSubtotalMinor(), in.restaurantId(), ownerPartner, starts, in.endsAt(), in.maxRedemptions(),
                in.perUserLimit() == null ? 1 : in.perUserLimit(), in.banner(), synthetic);
    }

    /** Partner can pause/resume its own promotion; it cannot re-enable what an administrator disabled. */
    @Transactional
    public PromotionView setPartnerStatus(UUID actor, UUID partnerId, UUID promotionId, String status) {
        String current = db.query("select status from marketplace.food_promotions where id = ? and owner_partner_id = ? for update",
                (rs, n) -> rs.getString(1), promotionId, partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "PROMO_NOT_FOUND", "Promotion not found"));
        if ("DISABLED".equals(current)) {
            throw new ApiException(HttpStatus.CONFLICT, "PROMO_DISABLED_BY_ADMIN", "This promotion was disabled by an administrator");
        }
        db.update("update marketplace.food_promotions set status = ? where id = ?", status, promotionId);
        audit(actor, "PARTNER", "PROMO_" + status, promotionId.toString(), "");
        return db.query(VIEW_SELECT + " where p.id = ?", FoodPromotionService::map, promotionId).get(0);
    }

    @Transactional
    public PromotionView adminSetStatus(UUID admin, UUID promotionId, String status, String reason) {
        int n = db.update("update marketplace.food_promotions set status = ? where id = ?", status, promotionId);
        if (n == 0) { throw new ApiException(HttpStatus.NOT_FOUND, "PROMO_NOT_FOUND", "Promotion not found"); }
        audit(admin, "ADMIN", "PROMO_" + status, promotionId.toString(), reason == null ? "" : reason);
        return db.query(VIEW_SELECT + " where p.id = ?", FoodPromotionService::map, promotionId).get(0);
    }

    void audit(UUID actor, String type, String action, String target, String detail) {
        db.update("insert into marketplace.food_audit (actor_user_id, actor_type, action, target, detail) values (?, ?, ?, ?, ?)",
                actor, type, action, target, detail.length() > 300 ? detail.substring(0, 300) : detail);
    }
}
