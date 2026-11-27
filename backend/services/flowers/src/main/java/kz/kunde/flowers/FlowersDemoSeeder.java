package kz.kunde.flowers;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Synthetic DEV catalogue for Flowers &amp; Gifts ({@code app.flowers.seed-demo}). Every row is marked synthetic, nothing
 * references a real business, and a shop whose slug already exists is skipped (idempotent). Never runs unless switched on.
 */
@Component
@ConditionalOnProperty(name = "app.flowers.seed-demo", havingValue = "true")
public class FlowersDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(FlowersDemoSeeder.class);

    private record Product(String category, String name, String description, long price, String emoji, boolean popular) {}

    private record Shop(String slug, String name, String description, String emoji, long deliveryFee, int etaMin, int etaMax, List<Product> products) {}

    private static final List<Shop> SHOPS = List.of(
            new Shop("flowers-demo-lavka", "Цветочная лавка (демо)", "Вымышленный магазин для DEV: свежие цветы", "💐", 100000, 30, 45, List.of(
                    new Product("BOUQUETS", "Букет «Классика»", "25 роз, 50 см. Синтетический товар для DEV", 1790000, "🌹", true),
                    new Product("BOUQUETS", "Весенний букет", "Тюльпаны и нарциссы. Синтетический товар для DEV", 1250000, "💐", true),
                    new Product("COMPOSITIONS", "Композиция в корзине", "Сезонные цветы. Синтетический товар для DEV", 1890000, "🌸", false),
                    new Product("BOXED", "Цветы в коробке", "Розы в шляпной коробке. Синтетический товар для DEV", 2150000, "🎁", true))),
            new Shop("flowers-demo-studio", "Букетная студия (демо)", "Вымышленная студия для DEV: авторские букеты", "🌷", 0, 35, 50, List.of(
                    new Product("BOUQUETS", "Нежный микс", "Пионовидные розы. Синтетический товар для DEV", 1550000, "🌸", true),
                    new Product("BOUQUETS", "Монобукет тюльпанов", "35 тюльпанов. Синтетический товар для DEV", 990000, "🌷", false),
                    new Product("CARDS", "Открытка с пожеланием", "Синтетический товар для DEV", 80000, "💌", false))),
            new Shop("flowers-demo-gifts", "Дом подарков (демо)", "Вымышленный магазин для DEV: подарки и сувениры", "🎁", 100000, 40, 60, List.of(
                    new Product("GIFTS", "Подарочный набор", "Шоколад, открытка, игрушка. Синтетический товар для DEV", 950000, "🎁", true),
                    new Product("SWEETS", "Набор конфет", "Синтетический товар для DEV", 650000, "🍫", false),
                    new Product("TOYS", "Плюшевый мишка", "40 см. Синтетический товар для DEV", 1200000, "🧸", true))),
            new Shop("flowers-demo-roses", "Розы и пионы (демо)", "Вымышленный бутик для DEV: премиум-букеты", "🌹", 150000, 30, 40, List.of(
                    new Product("BOUQUETS", "Пионы премиум", "15 пионов. Синтетический товар для DEV", 2890000, "🌺", true),
                    new Product("BOXED", "Розы в коробке", "19 роз. Синтетический товар для DEV", 2490000, "🌹", false))));

    private final JdbcTemplate db;

    public FlowersDemoSeeder(JdbcTemplate db) {
        this.db = db;
    }

    @Override
    public void run(ApplicationArguments args) {
        log.info("Flowers demo seed: {} synthetic shops inserted", seed());
    }

    @Transactional
    public int seed() {
        int inserted = 0;
        int order = 0;
        for (Shop shop : SHOPS) {
            order += 10;
            int rows = db.update("""
                    insert into marketplace.flowers_shops (slug, name, description, emoji, tone, delivery_fee_minor, eta_min_minutes,
                                                           eta_max_minutes, is_synthetic, sort_order)
                    select ?, ?, ?, ?, 'red', ?, ?, ?, true, ?
                    where not exists (select 1 from marketplace.flowers_shops where slug = ?)""",
                    shop.slug(), shop.name(), shop.description(), shop.emoji(), shop.deliveryFee(), shop.etaMin(), shop.etaMax(), order, shop.slug());
            if (rows == 0) {
                continue;
            }
            inserted++;
            int sort = 0;
            for (Product p : shop.products()) {
                sort += 10;
                db.update("""
                        insert into marketplace.flowers_products (shop_id, category_code, name, description, price_minor, emoji, popular, sort_order, stock_qty)
                        select id, ?, ?, ?, ?, ?, ?, ?, 20 from marketplace.flowers_shops where slug = ?""",
                        p.category(), p.name(), p.description(), p.price(), p.emoji(), p.popular(), sort, shop.slug());
            }
        }
        return inserted;
    }
}
