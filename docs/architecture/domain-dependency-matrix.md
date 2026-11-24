# Domain Dependency Matrix

Состояние: 2026-11-24, `main` @ `cab484f` + ветка аудита. Источник — исходный код, а не документация: `ArchitectureBoundariesTest` / `ArchitectureFitnessTest` пишут `backend/app/build/architecture/coupling.tsv`, таблица ниже строится командой
`python3 scripts/dev/architecture_matrix.py matrix` (после `cd backend && ./gradlew :app:test --tests 'kz.kunde.architecture.*'`).

Ячейка «из (строка) → в (столбец)»: `Ni` — число файлов строки, импортирующих тип столбца (compile-time); `Ns` — число файлов строки, чьи SQL-строки называют таблицу, которой владеет столбец. Пакеты — как в [domain-registry](domain-registry.md) (`auth`/`identity` и `partner`/`catalog` живут в одних Gradle-модулях `identity` и `partners`). Импорты `platform`/`identity` по правилу ядра не считаются.

| из \ в | auth | identity | partner | catalog | admin | support | food | groceries | delivery | rides | maps | booking | beauty | homeservices | health | auto | leisure | events | education |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **auth** |  | 4s | 1s |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **identity** |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **partner** | 1i+1s | 5s |  | 3s |  |  | 1s |  |  |  |  | 1s |  |  |  |  |  |  |  |
| **catalog** |  |  | 1s |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **admin** |  | 3s | 12i+3s |  |  |  | 2i+14s | 1s | 1i |  |  | 4s | 2s | 2s |  | 3i+4s | 3i+11s |  |  |
| **support** |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **food** |  | 1s | 2i+2s |  |  |  |  | 1s | 1s |  |  |  |  |  |  |  |  |  |  |
| **groceries** |  |  |  |  |  |  | 1i+11s |  |  |  |  |  |  |  |  |  |  |  |  |
| **delivery** |  | 1s | 2i |  |  |  |  |  |  | 1s |  |  |  |  |  |  |  |  |  |
| **rides** |  | 2s | 1i+4s |  |  |  |  |  | 1s |  |  |  |  |  |  |  |  |  |  |
| **maps** |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **booking** |  |  | 2i+1s |  |  |  |  |  |  |  |  |  |  |  | 2s | 2s |  |  |  |
| **beauty** |  | 1s | 2i |  |  |  |  |  |  |  |  | 4i+13s |  |  |  |  |  |  |  |
| **homeservices** |  |  |  |  |  |  |  |  |  |  |  | 1i |  |  |  |  |  |  |  |
| **health** |  |  | 1i |  |  |  |  |  |  |  |  | 2i+3s |  |  |  |  |  |  |  |
| **auto** |  |  |  |  |  |  |  |  |  |  |  | 4i+9s |  |  |  |  |  |  |  |
| **leisure** | 1i+1s |  | 4i+2s |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **events** |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2i |  |  |
| **education** |  | 3s | 2i+4s |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |

Всего: 42 связи-импорта и 102 SQL-связи в baseline (144; рост со 140 до 144 в PR D3 — не новые зависимости, а четыре ранее невидимых импорта `admin → auto/leisure`, которые стал видеть улучшенный детектор: полные имена классов в коде) + 36 зафиксированных намеренных рёбер вертикалей к движку Booking (`allowed-module-edges.txt`).

## Как читать

- **Правильное направление** — к ядру: `* → identity`, `* → partner` (через `PartnerDirectory`, ADR-021) и вертикаль → движок (`beauty/health/auto/homeservices → booking`).
- **Обратные рёбра** (ядро или движок → вертикаль) — инверсия, главный блокер выделения: `partner → food/booking/auth`, `booking → auto/health`, `catalog ↔ partner`, `food → groceries/delivery`, `rides ↔ delivery`.
- **Admin** — единственная строка, которая зависит почти от всех бизнес-доменов (≈38 SQL и 9 импортов наружу): см. [microservice-readiness §Admin](microservice-readiness.md).

## Узел циклов (strongly connected component)

Единый сильно связный узел из 10 пакетов, поэтому их нельзя выделять по одному: `auth, auto, booking, catalog, delivery, food, groceries, health, partner, rides`. Рёбра узла заморожены в `known-coupling-cycles.txt` (20 рёбер; тест `domainCouplingHasNoNewCycles`: новое ребро внутри узла или новый цикл — падение, исчезнувшее — обязательное удаление строки).

Узел держится на трёх фактах, каждый исправим малым PR:

1. **`PartnerOpsDemoSeeder`** (DEV-сид в модуле `partners`) делает SQL в `food_restaurants`, `booking_venues`, `identity.phone_identities/users/consumer_profiles`: это порождает `partner → food`, `partner → booking`, `partner → auth` и четыре из пяти `partner → identity` (7 из 8 SQL-связей демо-сидов; восьмая — `LeisureDemoSeeder → partners`). Вынос демо-сидов в `backend/app` (composition root, исключён из проверки границ) разрывает узел вокруг `partner`.
2. **Пары «движок ↔ вертикаль»**: `booking → auto` (`auto_service_categories`, `auto_payments`), `booking → health` (`health_categories`, `health_favorites`): движок знает вертикали по таблицам вместо `BookingCategory`.
3. **Пары `food ↔ groceries` и `rides ↔ delivery`**: `food → grocery_categories`, `groceries → food_*` (11 SQL), `food → delivery_couriers`, `rides ↔ transactions.deliveries/rides`.
