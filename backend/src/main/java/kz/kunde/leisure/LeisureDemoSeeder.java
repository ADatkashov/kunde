package kz.kunde.leisure;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZonedDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import kz.kunde.partner.PartnerOpsDemoSeeder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * DEV-only synthetic Leisure data: invented venues and events (every name says "синтетика"), no photos (the app draws honest placeholders), no
 * users or orders except the two synthetic partners of the Partner Operations seed. Idempotent: venues and events are found by slug/title, and
 * upcoming sessions are topped up for the next days on every start. Runs only with {@code app.leisure.seed-demo=true} in dev/local/test.
 */
@Component
@Order(110)
@ConditionalOnProperty(name = "app.leisure.seed-demo", havingValue = "true")
public class LeisureDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(LeisureDemoSeeder.class);
    private static final int DAYS = 8;

    private final JdbcTemplate db;
    private final PhoneAuthProperties auth;
    private final Environment env;

    public LeisureDemoSeeder(JdbcTemplate db, PhoneAuthProperties auth, Environment env) {
        this.db = db;
        this.auth = auth;
        this.env = env;
    }

    @Override
    public void run(ApplicationArguments args) { log.info("Leisure demo seed: {} sessions added", seed()); }

    /** Returns the number of sessions inserted by this call. */
    @Transactional
    public int seed() {
        UUID a = new PartnerOpsDemoSeeder(db, auth, env).seed();
        UUID b = db.queryForObject("select id from marketplace.partners where display_name = 'Демо-партнёр Б (синтетика)' order by created_at limit 1", UUID.class);
        int added = 0;
        UUID cinema = venue(a, "demo-leisure-cinema", "Демо-кинозал (синтетика)", "Бостандыкский", "ул. Тестовая, 1 (синтетика)", 43.2185, 76.9285, "Вход по билету. Еду и напитки лучше покупать в баре.");
        UUID film = event(cinema, "CINEMA", "SEAT_MAP", "Демо-фильм «Ночной экспресс» (синтетика)", "Вымышленный фильм для проверки сценария покупки мест.", 120, 12, false, 10, "AUTO");
        types(film, new Object[][] {{"Стандарт", 200000L, "STANDARD"}, {"VIP", 350000L, "VIP"}});
        added += sessions(film, 7, List.of("14:00", "17:30", "21:00"), 0, 6, 10, 1);
        UUID kids = event(cinema, "CINEMA", "SEAT_MAP", "Демо-мультфильм «Лунные друзья» (синтетика)", "Вымышленный семейный мультфильм.", 85, 0, true, 8, "AUTO");
        types(kids, new Object[][] {{"Детский и взрослый", 150000L, null}});
        added += sessions(kids, 7, List.of("11:00", "15:00"), 0, 5, 8, 0);

        UUID bowling = venue(a, "demo-leisure-bowling", "Демо-боулинг (синтетика)", "Медеуский", "пр. Примерный, 10 (синтетика)", 43.2380, 76.9570, "Сменная обувь входит в стоимость. Дети до 12 лет — с взрослыми.");
        UUID lane = event(bowling, "BOWLING", "TIME_SLOT", "Дорожка на час (синтетика)", "Одна дорожка на час для компании до 6 человек.", 60, 0, true, 6, "AUTO");
        types(lane, new Object[][] {{"Дорожка, 1 час", 1200000L, null}});
        added += sessions(lane, 7, List.of("12:00", "14:00", "16:00", "18:00", "20:00", "22:00"), 4, 0, 0, 0);

        UUID karaoke = venue(a, "demo-leisure-karaoke", "Демо-караоке (синтетика)", "Алмалинский", "ул. Пробная, 5 (синтетика)", 43.2500, 76.9300, "Комната бронируется целиком. Подтверждение организатором.");
        UUID room = event(karaoke, "KARAOKE", "PRIVATE_SESSION", "Комната на 2 часа (синтетика)", "Отдельная комната, организатор подтверждает бронь вручную.", 120, 18, false, 12, "MANUAL");
        types(room, new Object[][] {{"Комната, 2 часа", 2500000L, null}});
        added += sessions(room, 7, List.of("18:00", "20:30"), 1, 0, 0, 0);

        UUID jump = venue(a, "demo-leisure-trampoline", "Демо-батутный парк (синтетика)", "Ауэзовский", "мкр. Образцовый, 3 (синтетика)", 43.2250, 76.8650, "Носки обязательны. Дети до 7 лет — только с сопровождающим.");
        UUID session90 = event(jump, "TRAMPOLINE", "CAPACITY", "Сеанс 90 минут (синтетика)", "Свободное прыжковое время.", 90, 3, true, 10, "AUTO");
        types(session90, new Object[][] {{"Детский", 350000L, null}, {"Взрослый", 450000L, null}});
        added += sessions(session90, 7, List.of("10:00", "12:00", "14:00", "16:00", "18:00"), 30, 0, 0, 0);

        UUID gallery = venue(a, "demo-leisure-gallery", "Демо-галерея (синтетика)", "Алмалинский", "ул. Выставочная, 7 (синтетика)", 43.2560, 76.9450, "Фотосъёмка без вспышки.");
        UUID expo = event(gallery, "EXHIBITION", "GENERAL_ADMISSION", "Выставка «Свет и тень» (синтетика)", "Вымышленная выставка.", 180, 0, true, 10, "AUTO");
        types(expo, new Object[][] {{"Входной билет", 100000L, null}, {"Льготный", 50000L, null}});
        added += sessions(expo, 7, List.of("11:00", "15:00"), 80, 0, 0, 0);

        UUID tour = venue(a, "demo-leisure-tours", "Демо-экскурсии (синтетика)", "Медеуский", "Старт у фонтана (синтетика)", 43.2380, 76.9450, "Удобная обувь. Группа до 15 человек.");
        UUID walk = event(tour, "EXCURSION", "CAPACITY", "Пешая экскурсия по центру (синтетика)", "Вымышленный маршрут с гидом; назначение гида идёт через приложение исполнителя.", 120, 0, true, 6, "AUTO");
        types(walk, new Object[][] {{"Участник", 300000L, null}});
        db.update("update marketplace.leisure_events set needs_executor = true where id = ?", walk);
        added += sessions(walk, 7, List.of("10:00", "16:00"), 15, 0, 0, 0);

        UUID hall = venue(a, "demo-leisure-concert-hall", "Демо-концертный зал (синтетика)", "Бостандыкский", "пр. Концертный, 2 (синтетика)", 43.2150, 76.9100, "Вход за 30 минут до начала.");
        UUID jazz = event(hall, "CONCERT", "SEAT_MAP", "Демо-концерт «Весенний джаз» (синтетика)", "Вымышленный концерт.", 120, 6, false, 8, "AUTO");
        types(jazz, new Object[][] {{"Партер", 400000L, "STANDARD"}, {"Первый ряд", 700000L, "VIP"}});
        added += sessions(jazz, 7, List.of("19:00"), 0, 5, 8, 1);

        UUID kidsClub = venue(a, "demo-leisure-kids-center", "Демо-детский центр (синтетика)", "Ауэзовский", "ул. Детская, 9 (синтетика)", 43.2300, 76.8800, "Родители остаются в центре.");
        UUID play = event(kidsClub, "KIDS_CENTER", "CAPACITY", "Игровая зона, 2 часа (синтетика)", "Игры и аниматор.", 120, 3, true, 8, "AUTO");
        types(play, new Object[][] {{"Ребёнок", 280000L, null}});
        added += sessions(play, 7, List.of("10:00", "13:00", "16:00"), 25, 0, 0, 0);

        UUID vr = venue(b, "demo-leisure-vr", "Демо-VR-клуб Б (синтетика)", "Бостандыкский", "ул. Виртуальная, 11 (синтетика)", 43.2100, 76.9200, "Шлемы обрабатываются после каждого гостя.");
        UUID vrEvent = event(vr, "GAMING_VR", "TIME_SLOT", "VR-сессия 1 час (синтетика)", "Вымышленный клуб второго партнёра.", 60, 12, false, 4, "AUTO");
        types(vrEvent, new Object[][] {{"Станция, 1 час", 800000L, null}});
        added += sessions(vrEvent, 7, List.of("13:00", "15:00", "17:00", "19:00"), 3, 0, 0, 0);
        return added;
    }

    private UUID venue(UUID partner, String slug, String name, String district, String address, double lat, double lng, String rules) {
        UUID id = db.query("select id from marketplace.leisure_venues where slug = ?", rs -> rs.next() ? rs.getObject(1, UUID.class) : null, slug);
        if (id != null) { return id; }
        return db.queryForObject("insert into marketplace.leisure_venues (partner_id, slug, name, description, address, district, latitude, longitude, rules, status, is_synthetic) "
                + "values (?, ?, ?, ?, ?, ?, ?, ?, ?, 'APPROVED', true) returning id", UUID.class, partner, slug, name, "Синтетическая площадка для DEV/TEST. Не существует.", address, district, lat, lng, rules);
    }

    private UUID event(UUID venue, String category, String type, String title, String description, int minutes, int minAge, boolean family, int maxGuests, String confirmation) {
        UUID id = db.query("select id from marketplace.leisure_events where venue_id = ? and title = ?", rs -> rs.next() ? rs.getObject(1, UUID.class) : null, venue, title);
        if (id != null) { return id; }
        return db.queryForObject("insert into marketplace.leisure_events (venue_id, category_code, booking_type, title, description, duration_minutes, min_age, family_friendly, max_guests, confirmation, status, is_synthetic) "
                + "values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PUBLISHED', true) returning id", UUID.class, venue, category, type, title, description, minutes, minAge, family, maxGuests, confirmation);
    }

    private void types(UUID event, Object[][] defs) {
        String bookingType = db.queryForObject("select booking_type from marketplace.leisure_events where id = ?", String.class, event);
        String pricing = "TIME_SLOT".equals(bookingType) || "PRIVATE_SESSION".equals(bookingType) ? "PER_BOOKING" : "PER_TICKET";
        int order = 0;
        for (Object[] d : defs) {
            db.update("insert into marketplace.leisure_ticket_types (event_id, name, price_minor, pricing, seat_zone, sort_order) values (?, ?, ?, ?, ?, ?) on conflict (event_id, name) do nothing",
                    event, d[0], d[1], pricing, d[2], order++);
        }
    }

    private int sessions(UUID event, int days, List<String> times, int capacity, int rows, int perRow, int vipRows) {
        int minutes = db.queryForObject("select duration_minutes from marketplace.leisure_events where id = ?", Integer.class, event);
        int added = 0;
        LocalDate today = LocalDate.now(LeisureCatalogService.ALMATY);
        for (int d = 0; d < Math.min(days, DAYS); d++) {
            for (String t : times) {
                ZonedDateTime start = ZonedDateTime.of(today.plusDays(d), LocalTime.parse(t), LeisureCatalogService.ALMATY);
                if (!start.toInstant().isAfter(java.time.Instant.now())) { continue; }
                OffsetDateTime at = start.toOffsetDateTime();
                int cap = rows > 0 ? rows * perRow : capacity;
                UUID id = db.query("insert into marketplace.leisure_sessions (event_id, starts_at, ends_at, capacity) values (?, ?, ?, ?) on conflict (event_id, starts_at) do nothing returning id",
                        rs -> rs.next() ? rs.getObject(1, UUID.class) : null, event, at, at.plusMinutes(minutes), cap);
                if (id == null) { continue; }
                added++;
                for (int r = 0; r < rows; r++) {
                    for (int s = 1; s <= perRow; s++) {
                        db.update("insert into marketplace.leisure_seats (session_id, row_label, seat_number, zone) values (?, ?, ?, ?)", id, String.valueOf((char) ('A' + r)), s, r < vipRows ? "VIP" : "STANDARD");
                    }
                }
            }
        }
        return added;
    }
}
