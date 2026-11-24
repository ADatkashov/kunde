# Аудит структуры проекта и целевая организация (PR A)

Дата: 2026-11-24, `main` @ `0677e06`. Основание — исходный код, а не документация. Статус: **предложение**, ничего в коде не перемещено. Решение по сборке — [ADR-023](adr/ADR-023-build-system-and-module-structure.md) (PROPOSED, ждёт подтверждения владельца).

Связанные документы: [microservice-readiness](microservice-readiness.md) (границы и нарушения V1–V12), [database-sharding-readiness](database-sharding-readiness.md), [ADR-001](adr/ADR-001-backend-architecture-style.md) (modular monolith).

Воспроизвести цифры: `cd backend && find src/main/java -name '*.java' | wc -l`; связи — `src/test/resources/architecture/cross-module-baseline.txt`.

## 1. Что есть на самом деле

| Область | Факт |
|---|---|
| Backend | Maven, один модуль `kz.kunde:kunde-api`, Spring Boot 4.0.9, Java 21; 216 main- и 99 test-файлов; 68 миграций Flyway (V1–V68) в `src/main/resources/db/migration` |
| Пакеты | 23 плоских пакета `kz.kunde.<модуль>`, подпакетов почти нет (кроме `platform/*`). Доступ к данным — `JdbcTemplate` с SQL прямо в контроллерах и сервисах; слоя репозиториев нет |
| Тесты backend | 13 интеграционных тестов лежат в корне `src/test/java/kz/kunde/`, остальные — по пакетам доменов; `architecture/` — `ArchitectureBoundariesTest` (ратчет по `cross-module-baseline.txt`), `PlacementRegistryTest` |
| Flutter | **Два проекта, а не четыре**: `mobile/` (Consumer; плюс точки входа `executor_main.dart` и `admin_rides_main.dart`, т.е. Executor и часть Admin — это режимы того же приложения) и `partner_app/` (Partner). Общий пакет — `packages/kunde_design`. Отдельный Admin: `scripts/admin-web` (Node-обёртка) |
| Flutter-структура | `mobile/lib/features/<x>` — плоский список из 26 папок, где админские и исполнительские экраны лежат рядом с потребительскими (`rides` / `rides_admin`, `delivery` / `delivery_admin`, `executor/*_work_screen.dart`); `partner_app/lib/features/*` организован по *функциям* (`orders`, `bookings`, `business`), а не по доменам |
| CI | 30 workflow; `backend.yml` собирает Maven (`mvn clean verify`, кэш по `backend/pom.xml`); Maven/`backend/target` упоминают 14 workflow и 7 скриптов `scripts/ci`; `backend/Dockerfile` ставит Apache Maven 3.10.0 с проверкой SHA-256 и вызывает `mvn package` |

## 2. Реестр доменов

Колонки: пакет → маршруты API → Flutter → владелец данных (по `table-owners.txt`) → размер (файлы / тесты) → готовность к модулю.

| Домен | Backend-пакет | API (`/api/v1/...`) | Flutter (mobile) | Данные | Ф/Т | Замечания |
|---|---|---|---|---|---|---|
| identity | `identity` | `me`, `me/addresses`, `me/consents` | `identity` | `identity.users…`, `profile.*`, `serviceability.*` | 7/0 | ядро, общее; тестов в пакете нет (есть корневые `Consumer*IntegrationTest`) |
| auth | `auth` | `auth` | `identity` | `identity.auth_/otp_/refresh_` | 12/6 | готов; `partner → auth` и `leisure → auth` — по одному импорту |
| partner | `partner` | `partner`, `partner/partners/{id}/offerings` | `partner` + `partner_app` | `marketplace.partner*` | 8/6 | общее B2B-ядро; контракт `PartnerDirectory` уже в `platform.partner` (ADR-021) |
| catalog | `catalog` | `categories`/offerings | — | `marketplace.offering*`, `categories` | 4/1 | 153 строки; кандидат слиться с `partner` |
| food | `food` | `food`, `executor/food`, `partner/.../food` | `food`, `food_admin` | `food_*` | 14/4 | |
| groceries | `groceries` | `groceries` | `groceries` | `grocery_*` | 3/1 | вертикаль Food: 31 SQL-ссылка на `food_*` + `FoodOrderService` |
| delivery | `delivery` | `deliveries`, `executor/deliveries`, `admin/deliveries`, `partner/.../deliveries` | `delivery`, `delivery_admin`, `executor/delivery_work_screen` | `deliver*` | 15/4 | цикл с rides по импортам закрыт (V2b); остаётся SQL взаимного исключения водитель↔курьер |
| rides (Taxi) | `rides` | `rides`, `executor/rides`, `admin/rides`, `partner/.../rides/fleet` | `rides`, `rides_admin`, `executor/driver_*` | `ride*` | 21/13 | самый протестированный; Maps — адаптер `maps` к порту `platform.geo.RoutingProvider` |
| maps | `maps` | — | `maps` | — (отдельный сервис `kunde-maps`, ADR-020) | 3/3 | только HTTP-адаптер |
| booking (engine) | `booking` | `booking`, `booking/bookings`, `beauty`, `home-services`, `executor/beauty`, `partner/.../booking`, `partner/.../beauty` | `booking`, `beauty`, `home`, `home_services_admin` | `booking_*`, `beauty_*`, `home_service*`, `bookings` | 21/8 | **внутри лежат три продукта**: движок записи, Beauty и Home Services |
| health | `health` | `booking/health/favorites` (в `booking`), `admin/health` | `health` | `health_*` | 3/0 | тонкая вертикаль Booking |
| auto | `auto` | `auto` | `auto`, `auto_admin`, `executor/auto_work_screen` | `auto_*`, `customer_vehicles` | 12/7 | вертикаль Booking (~32 SQL-ссылки на `booking_*`) |
| leisure | `leisure` | `leisure`, `executor/leisure`, `partner/.../leisure` | `leisure`, `leisure_admin`, `executor/gate_scan_screen` | `leisure_*` | 15/6 | |
| events | `events` | `events`, `search` | (в `leisure`) | (`leisure_*`) | 3/0 | продукт отделён в V56, код общий с leisure; Flutter-фичи `events` нет |
| education | `education` | `education`, `education/enrollments` | `education` | `education_*` | 9/4 | |
| support | `support` | `me/support/cases` | (в `delivery`/`rides`) | `support.*` | 3/1 | зависимости убраны через `platform.support` (V3/V4) |
| admin | `admin` | `admin/{auto,beauty,features,food,groceries,home-services,leisure,partners}` | `admin_employees`, `admin_features`, `*_admin` | `identity.admin_*` | 11/2 | **44 SQL + 17 импортов в чужие домены** — основной источник связности |
| platform | `platform/{authz,geo,events,placement,dispatch,partner,support}` + корень | `health`, `poc` | `shell` | `platform.*`, `identity.feature_toggle*` | 39/10 | ядро; остался `platform → delivery, rides` (FeatureToggles) |
| config | `config` | — | — | — | 4/3 | composition root: Security/Web/PhoneAuth |
| fulfillment, order, notification, analytics | по 1–3 файла | — | — | — | 1–3 | контракты-заготовки без обращений из кода (только друг к другу); кандидат в `platform` или удаление после проверки владельцем |

Найденные домены, которых нет в предварительном списке: **Home Services** (внутри `booking`), **Serviceability/Placement** (внутри `identity`/`platform`), **Fulfillment/Order/Notification/Analytics** (заготовки). Отдельного **Payments**, **Loyalty**, **Promotions**, **Chat**, **Analytics** домена в коде нет (платежи — DEV-заглушки внутри доменов; акции — внутри food/beauty). Создавать для них модули нельзя: это пустые модули.

## 3. Расхождения имён (то, что мешает «найти код по названию»)

| # | Расхождение | Где видно | Предлагаемое каноническое имя |
|---|---|---|---|
| N1 | Продукт «Beauty» живёт в пакете `booking`; его таблицы `marketplace.beauty_*` числятся за `booking`, API `/beauty`, Flutter `features/beauty` | `booking/Beauty*Controller` | пакет `beauty` (зависит от `booking`), владелец `marketplace.beauty_`=`beauty` |
| N2 | «Home Services» живёт в `booking`; Flutter — `home` + `home_services_admin`; API `home-services` | `booking/HomeService*` | пакет `homeservices` (Java-идентификатор без дефиса), Flutter `home_services`; API-маршрут не меняется |
| N3 | Taxi называется `rides` в backend/Flutter/API, «Taxi» — только в бизнес-речи | везде | оставить `rides` (технический термин), «Taxi» — бизнес-имя, зафиксировать в глоссарии |
| N4 | Роли внутри домена названы по-разному: `executor/*_work_screen`, `partner/.../deliveries`, `admin/deliveries`, `*_admin` | Flutter, API | правило «`<domain>` + роль-подпапка»: `features/delivery/{consumer,executor,admin}/` |
| N5 | `partner_app/features` — по функциям (`orders`, `bookings`, `business`, `dashboard`), общие для доменов; доменные (`delivery`, `education`, `leisure`) — вперемешку | `partner_app/lib/features` | оставить функциональные экраны, но доменные вынести в `features/<domain>/`; без массового переноса |
| N6 | `catalog` = `categories` + `offerings`, `partner/.../offerings` — тоже offerings | `catalog`, `partner` | один владелец (`catalog`), partner вызывает контракт |
| N7 | `events` (продукт) в backend использует `leisure`; во Flutter отдельной фичи нет | `events` | оставить, в реестре указать «вертикаль leisure»; Flutter-фичу не создавать, пока UI отдельный не появится |
| N8 | `analytics/notification/order/fulfillment` — заготовки с обобщёнными именами | корень пакетов | свернуть в `platform.contracts` после подтверждения (не удалять без владельца) |

Правило имён (предлагается в Конституцию): имя домена — одно слово в нижнем регистре, совпадает в `kz.kunde.<domain>`, `features/<domain>`, коде префикса таблиц (`<domain>_*`), Gradle-модуле `services/<domain>`; HTTP-маршруты — публичный контракт, **не переименовываются ради красоты**.

## 4. Зависимости и граф модулей (по baseline)

Импорты между модулями **без циклов** (проверено вычислением компонент сильной связности по `cross-module-baseline.txt`), кроме инверсии ядра:

```text
admin ──► delivery, food, leisure, partner            auto ──► booking
booking ──► partner      delivery, education, food, rides ──► partner
events ──► leisure       groceries ──► food       health ──► booking, partner
leisure ──► auth, partner       partner ──► auth
platform ──► delivery, rides   ← единственная инверсия (FeatureToggles: RidesFlags, DeliveryProperties)
```

Следствия:
1. Compile-time граф уже пригоден для разрезания на Gradle/Maven-модули, **после** одного шага: убрать `platform → delivery, rides` (V1, остаток).
2. Это только 44 из 159 связей в baseline. Остальные **115 (72%) — SQL в таблицы чужого домена** (`admin` 44, `partner` 11, `groceries` 11, `auto` 9, `rides` 7, `education` 7, `booking` 7 …; цифры — файлы-источники). Gradle/Maven такие связи **не видят**: модуль `delivery` скомпилируется, а в рантайме читает `marketplace.partners`. Поэтому `ArchitectureBoundariesTest` (SQL-ратчет) сохраняется и после перехода на модули.
3. Реально «не разрезается» без работы: `admin` (знает SQL 9 доменов), вертикали `groceries→food`, `auto/health→booking`, `events→leisure`. Они остаются *зависимыми модулями* (одним направлением), а не независимыми.

## 5. Целевая структура (предложение, уточняется ADR-023)

```text
backend/
├── app/                      # единственный Spring Boot jar: KundeApplication, config/, application.yml, Flyway
├── platform/                 # техническое ядро: authz, geo, events(outbox), placement, dispatch, контракты partner/support
├── services/
│   ├── identity/             # identity + auth (общее ядро учёток; auth остаётся пакетом внутри)
│   ├── partner/              # partner + catalog
│   ├── food/   groceries/    # groceries → food
│   ├── booking/              # движок записи
│   ├── beauty/ homeservices/ health/ auto/   # вертикали → booking
│   ├── rides/  delivery/ maps/               # maps → platform.geo
│   ├── leisure/ events/      # events → leisure
│   ├── education/  support/
│   └── admin/                # единое окно админки; зависит от доменов (в будущем растворяется в домены)
└── (миграции Flyway остаются одним деревом в app/, см. ADR-023 §Flyway)
```

Не создаём модули: `payments`, `loyalty`, `promotions`, `chat`, `analytics`, `notifications` (в коде их нет); `fulfillment/order/notification/analytics` — в `platform` после подтверждения.

Внутри модуля (пропорционально размеру): `api` (контроллеры, DTO) / `application` (сервисы, use cases) / `domain` (правила, enums, record'ы) / `infrastructure` (JDBC, адаптеры). Модули до ~10 файлов остаются плоскими; разбиение на слои — только при >15 файлов (`rides`, `booking`, `food`, `delivery`, `leisure`, `admin`).

## 6. Flutter: целевая организация

```text
mobile/lib/features/<domain>/{consumer|executor|admin}/…   # вместо <domain>, <domain>_admin, executor/*_work_screen
partner_app/lib/features/<domain>/…                         # доменные экраны; общие (orders, dashboard, profile, login) остаются функциональными
```

- API-клиент домена — `features/<domain>/<domain>_api.dart` (уже так у `delivery`, `rides`, `executor`).
- Тесты повторяют структуру (`mobile/test/features/<domain>/…` — уже так).
- Переносы только git-mv + обновление импортов, без изменения экранов/дизайна; проверка — `flutter analyze` и существующие тесты (в этом окружении Flutter SDK надо проверить отдельно, см. риски).

## 7. План PR

| PR | Содержимое | Риск | Требует подтверждения |
|---|---|---|---|
| **A (этот)** | аудит, реестр доменов, нейминг, ADR-023 | нет (docs) | выбор Gradle/Maven и границ модулей |
| B0 | закрыть `platform → delivery, rides` (V1) внутри текущего Maven-модуля | низкий | нет |
| B | `beauty`/`homeservices` выделить из `booking` пакетом; тот же артефакт | низкий–средний (FQCN, тесты, baseline не растёт) | нет |
| C | Gradle foundation: параллельный `build.gradle.kts`, эквивалентность jar/тестов/Flyway, CI без переключения | средний | **да (ADR-023)** |
| D… | перенос доменов в `services/*` по группам: partner+catalog → food+groceries → booking+вертикали → rides+delivery+maps → leisure+events → education+support → admin | средний, по одному PR | нет |
| E | переключение CI/Dockerfile/скриптов на Gradle, удаление Maven | средний | да (после зелёной эквивалентности) |
| F… | Flutter: переносы по приложениям | низкий–средний | нет |
| Final | Конституция `docs/architecture/CONSTITUTION.md`, ссылки из `AGENTS.md`/PR-шаблона, Developer Guide | низкий | да (Конституция) |

## 8. Что намеренно не делается в PR A

Нет перемещения кода, нет изменения API, миграций, CI и Docker. Конституция создаётся последним PR, когда структура реально существует (иначе документ описывает несуществующее). Применённые миграции Flyway и их checksums не трогаются.
