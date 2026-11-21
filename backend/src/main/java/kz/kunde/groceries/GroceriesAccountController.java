package kz.kunde.groceries;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import kz.kunde.food.FoodOrderService;
import kz.kunde.groceries.GroceriesCatalogController.Product;
import kz.kunde.identity.ConsumerIdentityService;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The customer's own Groceries data, stored on the server: favorite products, shopping lists and the cart. Every row is
 * owned by one customer; another customer's list is reported as 404. While the GROCERIES switch is off, reading and
 * deleting stays possible but nothing new can be added. The cart never stores prices of its own: totals come from the
 * server quote; the price a line had when it was saved is kept only to tell the customer that it has changed.
 */
@RestController
@Validated
@RequestMapping("/api/v1/groceries")
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class GroceriesAccountController {
    private static final int MAX_FAVORITES = 300;
    private static final int MAX_LISTS = 20;
    private static final int MAX_LIST_ITEMS = 100;
    private static final int MAX_CART_LINES = 30;
    private static final ObjectMapper JSON = new ObjectMapper();

    public record FavoriteState(String productId, boolean favorite) {}

    public record NameRequest(@NotBlank @Size(max = 60) String name) {}

    public record ListSummary(String id, String name, int items, int checked, OffsetDateTime updatedAt) {}

    public record ListItem(String productId, String name, String unit, int quantity, boolean checked, long priceMinor,
            boolean inStock, int maxQuantity, String emoji, String imageUrl, String storeId, String storeName) {}

    public record ListDetail(String id, String name, OffsetDateTime updatedAt, List<ListItem> items) {}

    public record ItemRequest(@NotNull @Min(1) @Max(10000) Integer quantity, Boolean checked) {}

    public record Skipped(String productId, String name, String reason) {}

    public record ToCartResult(CartView cart, List<Skipped> skipped) {}

    public record CartLineRequest(@NotNull UUID dishId, @Min(1) @Max(10000) int quantity,
            @Size(max = 20) List<@NotNull UUID> optionIds,
            @jakarta.validation.constraints.Pattern(regexp = "NONE|ANY_SIMILAR|CHOSEN") String substitution,
            @Size(max = 5) List<@NotNull UUID> substituteDishIds) {}

    public record CartRequest(@NotNull UUID restaurantId, @Size(max = MAX_CART_LINES) List<@Valid @NotNull CartLineRequest> items) {}

    /** issue: UNAVAILABLE, OUT_OF_STOCK, STOCK_LOW (quantity above stock) or PRICE_CHANGED; null when the line is fine. */
    public record CartLine(String dishId, String name, String unit, int quantity, List<String> optionIds, String substitution,
            List<String> substituteDishIds, long unitPriceMinor, long lineTotalMinor, Long previousUnitPriceMinor,
            String issue, int maxQuantity, String emoji, String imageUrl) {}

    public record CartView(String restaurantId, String restaurantName, List<CartLine> lines, long subtotalMinor,
            long deliveryFeeMinor, long discountMinor, long totalMinor, long minOrderMinor, String promoCode,
            String quoteIssue, boolean needsUpdate, String currency, OffsetDateTime updatedAt) {}

    private final JdbcTemplate db;
    private final ConsumerIdentityService identity;
    private final FeatureToggles toggles;
    private final FoodOrderService orders;

    public GroceriesAccountController(JdbcTemplate db, ConsumerIdentityService identity, FeatureToggles toggles,
            FoodOrderService orders) {
        this.db = db;
        this.identity = identity;
        this.toggles = toggles;
        this.orders = orders;
    }

    private static <T> ResponseEntity<T> noStore(HttpStatus status, T body) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(body);
    }

    private UUID user(Jwt principal) { return identity.get(principal).id(); }

    private void requireOn() { GroceriesCatalogController.requireEnabled(toggles); }

    private static ApiException notFoundProduct() {
        return new ApiException(HttpStatus.NOT_FOUND, "PRODUCT_NOT_FOUND", "Product is not available");
    }

    private static ApiException quantityInvalid() {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "QUANTITY_INVALID",
                "Weighed goods use 100 g steps from 100 g to 5 kg; pieces from 1 to 20");
    }

    /** Validates a quantity against the unit of the product; returns the unit. */
    private String checkedUnit(UUID dishId, int quantity) {
        String unit = db.query("""
                select d.unit from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id
                where d.id = ? and r.vertical = 'GROCERY'
                """, (rs, row) -> rs.getString(1), dishId).stream().findFirst().orElseThrow(GroceriesAccountController::notFoundProduct);
        boolean ok = "KG".equals(unit) ? quantity >= 100 && quantity <= 5000 && quantity % 100 == 0 : quantity >= 1 && quantity <= 20;
        if (!ok) { throw quantityInvalid(); }
        return unit;
    }

    // ---- favorite products --------------------------------------------------------------------------------

    @GetMapping("/favorites")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<List<Product>> favorites(@AuthenticationPrincipal Jwt principal) {
        UUID user = user(principal);
        return noStore(HttpStatus.OK, db.query(GroceriesCatalogController.PRODUCT_SELECT
                + " join marketplace.grocery_favorites f on f.dish_id = d.id and f.user_id = ? where r.vertical = 'GROCERY'"
                + " order by f.created_at desc, d.id", GroceriesCatalogController::mapProduct, user));
    }

    @GetMapping("/favorites/ids")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<List<String>> favoriteIds(@AuthenticationPrincipal Jwt principal) {
        return noStore(HttpStatus.OK, db.queryForList("select dish_id::text from marketplace.grocery_favorites where user_id = ?",
                String.class, user(principal)));
    }

    @PutMapping("/favorites/{productId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<FavoriteState> addFavorite(@AuthenticationPrincipal Jwt principal, @PathVariable UUID productId) {
        requireOn();
        UUID user = user(principal);
        Integer exists = db.queryForObject("""
                select count(*) from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id
                where d.id = ? and r.vertical = 'GROCERY'
                """, Integer.class, productId);
        if (exists == null || exists == 0) { throw notFoundProduct(); }
        db.query("select pg_advisory_xact_lock(hashtext('grocery-favorites'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        Integer count = db.queryForObject("select count(*) from marketplace.grocery_favorites where user_id = ?", Integer.class, user);
        boolean already = db.queryForObject("select count(*) from marketplace.grocery_favorites where user_id = ? and dish_id = ?",
                Integer.class, user, productId) > 0;
        if (!already && count != null && count >= MAX_FAVORITES) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "FAVORITES_LIMIT", "Too many favorite products");
        }
        db.update("insert into marketplace.grocery_favorites (user_id, dish_id) values (?, ?) on conflict do nothing", user, productId);
        return noStore(HttpStatus.OK, new FavoriteState(productId.toString(), true));
    }

    @DeleteMapping("/favorites/{productId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<FavoriteState> removeFavorite(@AuthenticationPrincipal Jwt principal, @PathVariable UUID productId) {
        db.update("delete from marketplace.grocery_favorites where user_id = ? and dish_id = ?", user(principal), productId);
        return noStore(HttpStatus.OK, new FavoriteState(productId.toString(), false));
    }

    // ---- shopping lists -----------------------------------------------------------------------------------

    private void ownList(UUID user, UUID listId) {
        Integer n = db.queryForObject("select count(*) from marketplace.grocery_lists where id = ? and user_id = ?", Integer.class, listId, user);
        if (n == null || n == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "LIST_NOT_FOUND", "Shopping list not found");
        }
    }

    private ListSummary summary(UUID listId) {
        return db.query("""
                select l.id, l.name, l.updated_at, (select count(*) from marketplace.grocery_list_items i where i.list_id = l.id),
                       (select count(*) from marketplace.grocery_list_items i where i.list_id = l.id and i.checked)
                from marketplace.grocery_lists l where l.id = ?
                """, (rs, row) -> new ListSummary(rs.getString(1), rs.getString(2), rs.getInt(4), rs.getInt(5),
                rs.getObject(3, OffsetDateTime.class)), listId).get(0);
    }

    private ListDetail detail(UUID listId) {
        ListSummary s = summary(listId);
        List<ListItem> items = db.query("""
                select d.id, d.name, d.unit, i.quantity, i.checked, d.price_minor, d.available, d.stock_qty, d.emoji, d.image_url,
                       r.id, r.name
                from marketplace.grocery_list_items i
                join marketplace.food_dishes d on d.id = i.dish_id
                join marketplace.food_restaurants r on r.id = d.restaurant_id
                where i.list_id = ? order by i.checked, i.created_at, i.id
                """, (rs, row) -> {
                    Integer stock = rs.getObject(8, Integer.class);
                    boolean inStock = rs.getBoolean(7) && (stock == null || stock > 0);
                    return new ListItem(rs.getString(1), rs.getString(2), rs.getString(3), rs.getInt(4), rs.getBoolean(5),
                            rs.getLong(6), inStock, GroceriesCatalogController.maxQuantity(rs.getString(3), stock),
                            rs.getString(9), rs.getString(10), rs.getString(11), rs.getString(12));
                }, listId);
        return new ListDetail(s.id(), s.name(), s.updatedAt(), items);
    }

    @GetMapping("/lists")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<List<ListSummary>> lists(@AuthenticationPrincipal Jwt principal) {
        return noStore(HttpStatus.OK, db.query("""
                select l.id, l.name, l.updated_at, (select count(*) from marketplace.grocery_list_items i where i.list_id = l.id),
                       (select count(*) from marketplace.grocery_list_items i where i.list_id = l.id and i.checked)
                from marketplace.grocery_lists l where l.user_id = ? order by l.updated_at desc, l.id
                """, (rs, row) -> new ListSummary(rs.getString(1), rs.getString(2), rs.getInt(4), rs.getInt(5),
                rs.getObject(3, OffsetDateTime.class)), user(principal)));
    }

    @PostMapping("/lists")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<ListSummary> createList(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody NameRequest body) {
        requireOn();
        UUID user = user(principal);
        db.query("select pg_advisory_xact_lock(hashtext('grocery-lists'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        Integer count = db.queryForObject("select count(*) from marketplace.grocery_lists where user_id = ?", Integer.class, user);
        if (count != null && count >= MAX_LISTS) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "LISTS_LIMIT", "Too many shopping lists");
        }
        UUID id = db.queryForObject("insert into marketplace.grocery_lists (user_id, name) values (?, ?) returning id",
                UUID.class, user, body.name().strip());
        return noStore(HttpStatus.CREATED, summary(id));
    }

    @GetMapping("/lists/{listId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<ListDetail> list(@AuthenticationPrincipal Jwt principal, @PathVariable UUID listId) {
        ownList(user(principal), listId);
        return noStore(HttpStatus.OK, detail(listId));
    }

    @PutMapping("/lists/{listId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<ListSummary> rename(@AuthenticationPrincipal Jwt principal, @PathVariable UUID listId,
            @Valid @RequestBody NameRequest body) {
        ownList(user(principal), listId);
        db.update("update marketplace.grocery_lists set name = ?, updated_at = now() where id = ?", body.name().strip(), listId);
        return noStore(HttpStatus.OK, summary(listId));
    }

    @DeleteMapping("/lists/{listId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<Void> deleteList(@AuthenticationPrincipal Jwt principal, @PathVariable UUID listId) {
        ownList(user(principal), listId);
        db.update("delete from marketplace.grocery_list_items where list_id = ?", listId);
        db.update("delete from marketplace.grocery_lists where id = ?", listId);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    @PutMapping("/lists/{listId}/items/{productId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<ListDetail> putItem(@AuthenticationPrincipal Jwt principal, @PathVariable UUID listId,
            @PathVariable UUID productId, @Valid @RequestBody ItemRequest body) {
        requireOn();
        ownList(user(principal), listId);
        checkedUnit(productId, body.quantity());
        db.query("select pg_advisory_xact_lock(hashtext('grocery-list-items'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, listId.toString());
        boolean exists = db.queryForObject("select count(*) from marketplace.grocery_list_items where list_id = ? and dish_id = ?",
                Integer.class, listId, productId) > 0;
        if (!exists) {
            Integer count = db.queryForObject("select count(*) from marketplace.grocery_list_items where list_id = ?", Integer.class, listId);
            if (count != null && count >= MAX_LIST_ITEMS) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "LIST_FULL", "The shopping list is full");
            }
        }
        db.update("""
                insert into marketplace.grocery_list_items (list_id, dish_id, quantity, checked) values (?, ?, ?, ?)
                on conflict (list_id, dish_id) do update set quantity = excluded.quantity,
                    checked = coalesce(?, marketplace.grocery_list_items.checked)
                """, listId, productId, body.quantity(), Boolean.TRUE.equals(body.checked()), body.checked());
        db.update("update marketplace.grocery_lists set updated_at = now() where id = ?", listId);
        return noStore(HttpStatus.OK, detail(listId));
    }

    @DeleteMapping("/lists/{listId}/items/{productId}")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<ListDetail> removeItem(@AuthenticationPrincipal Jwt principal, @PathVariable UUID listId,
            @PathVariable UUID productId) {
        ownList(user(principal), listId);
        db.update("delete from marketplace.grocery_list_items where list_id = ? and dish_id = ?", listId, productId);
        db.update("update marketplace.grocery_lists set updated_at = now() where id = ?", listId);
        return noStore(HttpStatus.OK, detail(listId));
    }

    /**
     * Moves the available, unchecked items of a list into the cart. The cart holds one store: the store with the most
     * available items is used unless {@code storeId} is given; items of other stores are reported as skipped. An existing
     * cart of another store is refused with 409 CART_STORE_CONFLICT unless {@code replace=true}.
     */
    @PostMapping("/lists/{listId}/to-cart")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<ToCartResult> toCart(@AuthenticationPrincipal Jwt principal, @PathVariable UUID listId,
            @RequestParam(required = false) UUID storeId, @RequestParam(defaultValue = "false") boolean replace) {
        requireOn();
        UUID user = user(principal);
        ownList(user, listId);
        ListDetail list = detail(listId);
        List<Skipped> skipped = new ArrayList<>();
        Map<String, List<ListItem>> byStore = new java.util.LinkedHashMap<>();
        for (ListItem item : list.items()) {
            if (item.checked()) { skipped.add(new Skipped(item.productId(), item.name(), "ALREADY_BOUGHT")); continue; }
            if (!item.inStock()) { skipped.add(new Skipped(item.productId(), item.name(), "UNAVAILABLE")); continue; }
            byStore.computeIfAbsent(item.storeId(), k -> new ArrayList<>()).add(item);
        }
        if (byStore.isEmpty()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "LIST_NOTHING_TO_ADD", "No available items to add to the cart");
        }
        String chosen = storeId != null ? storeId.toString() : byStore.entrySet().stream()
                .max(java.util.Comparator.comparingInt(e -> e.getValue().size())).orElseThrow().getKey();
        if (!byStore.containsKey(chosen)) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "LIST_NOTHING_TO_ADD", "No available items of this store");
        }
        byStore.forEach((storeKey, storeItems) -> {
            if (!storeKey.equals(chosen)) {
                storeItems.forEach(i -> skipped.add(new Skipped(i.productId(), i.name(), "OTHER_STORE")));
            }
        });
        UUID store = UUID.fromString(chosen);
        var existing = loadCart(user);
        ArrayNode lines = JSON.createArrayNode();
        if (existing != null && existing.restaurantId.equals(store)) {
            lines = existing.items;
        } else if (existing != null && !replace && existing.items.size() > 0) {
            throw new ApiException(HttpStatus.CONFLICT, "CART_STORE_CONFLICT",
                    "The cart already holds items of another store; replace it or finish that order first");
        }
        for (ListItem item : byStore.get(chosen)) {
            int q = Math.min(item.quantity(), item.maxQuantity());
            boolean merged = false;
            for (JsonNode line : lines) {
                if (line.get("dishId").asText().equals(item.productId()) && line.get("optionIds").isEmpty()) {
                    ((ObjectNode) line).put("quantity", Math.min(line.get("quantity").asInt() + q, item.maxQuantity()));
                    merged = true;
                }
            }
            if (!merged) {
                if (lines.size() >= MAX_CART_LINES) {
                    skipped.add(new Skipped(item.productId(), item.name(), "CART_FULL"));
                    continue;
                }
                lines.add(line(UUID.fromString(item.productId()), q, List.of(), "NONE", List.of(), item.priceMinor()));
            }
        }
        saveCart(user, store, lines);
        return noStore(HttpStatus.OK, new ToCartResult(cartView(user, null), skipped));
    }

    // ---- cart ------------------------------------------------------------------------------------------------

    private record StoredCart(UUID restaurantId, ArrayNode items, OffsetDateTime updatedAt) {}

    private StoredCart loadCart(UUID user) {
        return db.query("select restaurant_id, items::text, updated_at from marketplace.grocery_carts where user_id = ?", (rs, row) -> {
            try {
                return new StoredCart(rs.getObject(1, UUID.class), (ArrayNode) JSON.readTree(rs.getString(2)),
                        rs.getObject(3, OffsetDateTime.class));
            } catch (JsonProcessingException e) {
                throw new IllegalStateException("Stored cart is not valid JSON", e);
            }
        }, user).stream().findFirst().orElse(null);
    }

    private void saveCart(UUID user, UUID store, ArrayNode lines) {
        if (lines.isEmpty()) {
            db.update("delete from marketplace.grocery_carts where user_id = ?", user);
            return;
        }
        db.update("""
                insert into marketplace.grocery_carts (user_id, restaurant_id, items, updated_at) values (?, ?, ?::jsonb, now())
                on conflict (user_id) do update set restaurant_id = excluded.restaurant_id, items = excluded.items, updated_at = now()
                """, user, store, lines.toString());
    }

    private static ObjectNode line(UUID dishId, int quantity, List<UUID> options, String substitution, List<UUID> substitutes, long seenPrice) {
        ObjectNode n = JSON.createObjectNode();
        n.put("dishId", dishId.toString());
        n.put("quantity", quantity);
        ArrayNode o = n.putArray("optionIds");
        options.forEach(id -> o.add(id.toString()));
        n.put("substitution", substitution);
        ArrayNode s = n.putArray("substituteDishIds");
        substitutes.forEach(id -> s.add(id.toString()));
        n.put("seenPriceMinor", seenPrice);
        return n;
    }

    @GetMapping("/cart")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional(readOnly = true)
    public ResponseEntity<CartView> cart(@AuthenticationPrincipal Jwt principal, @RequestParam(required = false) @Size(max = 32) String promoCode) {
        return noStore(HttpStatus.OK, cartView(user(principal), promoCode));
    }

    /** Replaces the whole cart. An empty item list clears it. */
    @PutMapping("/cart")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    @Transactional
    public ResponseEntity<CartView> putCart(@AuthenticationPrincipal Jwt principal, @Valid @RequestBody CartRequest body) {
        UUID user = user(principal);
        List<CartLineRequest> items = body.items() == null ? List.of() : body.items();
        if (!items.isEmpty()) {
            requireOn();
        }
        db.query("select pg_advisory_xact_lock(hashtext('grocery-cart'), hashtext(?))",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {}, user.toString());
        if (items.isEmpty()) {
            db.update("delete from marketplace.grocery_carts where user_id = ?", user);
            return noStore(HttpStatus.OK, cartView(user, null));
        }
        Integer store = db.queryForObject("select count(*) from marketplace.food_restaurants where id = ? and vertical = 'GROCERY'",
                Integer.class, body.restaurantId());
        if (store == null || store == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "STORE_NOT_FOUND", "Store is not available");
        }
        ArrayNode lines = JSON.createArrayNode();
        Set<String> seen = new HashSet<>();
        for (CartLineRequest item : items) {
            var row = db.query("select price_minor, unit from marketplace.food_dishes where id = ? and restaurant_id = ?",
                    (rs, n) -> new Object[] {rs.getLong(1), rs.getString(2)}, item.dishId(), body.restaurantId()).stream().findFirst()
                    .orElseThrow(GroceriesAccountController::notFoundProduct);
            boolean kg = "KG".equals(row[1]);
            if (kg ? item.quantity() < 100 || item.quantity() > 5000 || item.quantity() % 100 != 0 : item.quantity() > 20) {
                throw quantityInvalid();
            }
            List<UUID> options = item.optionIds() == null ? List.of() : item.optionIds();
            String key = item.dishId() + "|" + options.stream().map(UUID::toString).sorted().toList();
            if (!seen.add(key)) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "CART_DUPLICATE_LINE", "The same product appears twice");
            }
            lines.add(line(item.dishId(), item.quantity(), options, item.substitution() == null ? "NONE" : item.substitution(),
                    item.substituteDishIds() == null ? List.of() : item.substituteDishIds(), (Long) row[0]));
        }
        saveCart(user, body.restaurantId(), lines);
        return noStore(HttpStatus.OK, cartView(user, null));
    }

    @DeleteMapping("/cart")
    @PreAuthorize("@consumerAccessPolicy.allowed(authentication)")
    public ResponseEntity<Void> clearCart(@AuthenticationPrincipal Jwt principal) {
        db.update("delete from marketplace.grocery_carts where user_id = ?", user(principal));
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private CartView cartView(UUID user, String promoCode) {
        StoredCart stored = loadCart(user);
        if (stored == null) {
            return new CartView(null, null, List.of(), 0, 0, 0, 0, 0, null, null, false, "KZT", null);
        }
        String storeName = db.queryForObject("select name from marketplace.food_restaurants where id = ?", String.class, stored.restaurantId());
        List<CartLine> lines = new ArrayList<>();
        List<FoodOrderService.CartItem> valid = new ArrayList<>();
        boolean needsUpdate = false;
        for (JsonNode node : stored.items()) {
            UUID dishId = UUID.fromString(node.get("dishId").asText());
            int quantity = node.get("quantity").asInt();
            List<UUID> options = new ArrayList<>();
            node.get("optionIds").forEach(o -> options.add(UUID.fromString(o.asText())));
            List<UUID> substitutes = new ArrayList<>();
            node.get("substituteDishIds").forEach(o -> substitutes.add(UUID.fromString(o.asText())));
            String substitution = node.get("substitution").asText();
            long seen = node.get("seenPriceMinor").asLong();
            var row = db.query("""
                    select name, price_minor, available, unit, stock_qty, emoji, image_url
                    from marketplace.food_dishes where id = ? and restaurant_id = ?
                    """, (rs, n) -> new Object[] {rs.getString(1), rs.getLong(2), rs.getBoolean(3), rs.getString(4),
                            rs.getObject(5, Integer.class), rs.getString(6), rs.getString(7)}, dishId, stored.restaurantId())
                    .stream().findFirst().orElse(null);
            if (row == null) {
                lines.add(new CartLine(dishId.toString(), "—", "PIECE", quantity, ids(options), substitution, ids(substitutes), 0, 0,
                        null, "UNAVAILABLE", 0, null, null));
                needsUpdate = true;
                continue;
            }
            String unit = (String) row[3];
            Integer stock = (Integer) row[4];
            long price = (Long) row[1];
            String issue = null;
            if (!(boolean) row[2]) { issue = "UNAVAILABLE"; }
            else if (stock != null && stock <= 0) { issue = "OUT_OF_STOCK"; }
            else if (stock != null && quantity > stock) { issue = "STOCK_LOW"; }
            else if (price != seen) { issue = "PRICE_CHANGED"; }
            long total = FoodOrderServiceMath.lineTotal(unit, price, quantity);
            lines.add(new CartLine(dishId.toString(), (String) row[0], unit, quantity, ids(options), substitution, ids(substitutes),
                    price, total, price != seen ? seen : null, issue, GroceriesCatalogController.maxQuantity(unit, stock),
                    (String) row[5], (String) row[6]));
            if (issue == null) {
                valid.add(new FoodOrderService.CartItem(dishId, quantity, options, substitution, substitutes));
            } else {
                needsUpdate = true;
            }
        }
        long subtotal = lines.stream().filter(l -> l.issue() == null).mapToLong(CartLine::lineTotalMinor).sum();
        long fee = 0;
        long discount = 0;
        long total = subtotal;
        long minOrder = 0;
        String appliedCode = null;
        String quoteIssue = null;
        if (!valid.isEmpty()) {
            try {
                FoodOrderService.Quote q = orders.quote(stored.restaurantId(), valid, "DELIVERY", promoCode, user);
                List<CartLine> repriced = new ArrayList<>();
                int k = 0;
                for (CartLine l : lines) {
                    if (l.issue() != null) { repriced.add(l); continue; }
                    FoodOrderService.QuoteLine ql = q.lines().get(k++);
                    repriced.add(new CartLine(l.dishId(), l.name(), l.unit(), l.quantity(), l.optionIds(), l.substitution(),
                            l.substituteDishIds(), ql.unitPriceMinor(), ql.lineTotalMinor(), l.previousUnitPriceMinor(), null,
                            l.maxQuantity(), l.emoji(), l.imageUrl()));
                }
                lines = repriced;
                subtotal = q.subtotalMinor();
                fee = q.deliveryFeeMinor();
                discount = q.discountMinor();
                total = q.totalMinor();
                minOrder = q.minOrderMinor();
                appliedCode = q.promoCode();
            } catch (ApiException e) {
                quoteIssue = e.code();
                minOrder = db.queryForObject("select min_order_minor from marketplace.food_restaurants where id = ?", Long.class, stored.restaurantId());
            }
        } else {
            quoteIssue = "CART_EMPTY";
        }
        return new CartView(stored.restaurantId().toString(), storeName, lines, subtotal, fee, discount, total, minOrder,
                appliedCode, quoteIssue, needsUpdate, "KZT", stored.updatedAt());
    }

    private static List<String> ids(List<UUID> list) { return list.stream().map(UUID::toString).toList(); }

    /** Same rounding as the order engine: grams are priced per kg, half-up to the minor unit. */
    static final class FoodOrderServiceMath {
        private FoodOrderServiceMath() {}

        static long lineTotal(String unit, long unitPrice, int quantity) {
            return "KG".equals(unit) ? (unitPrice * quantity + 500) / 1000 : unitPrice * quantity;
        }
    }
}
