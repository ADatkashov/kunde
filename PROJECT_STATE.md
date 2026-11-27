# KUNDE project state

## Структура проекта и сборка (2026-11-24, ADR-023 ACCEPTED)

- **Backend — Gradle Kotlin DSL multi-module, Maven удалён.** `backend/platform` (ядро без доменных импортов), `backend/app` (composition root, Flyway, Spring/БД-тесты), 17 модулей `backend/services/*` (identity, partners, food, groceries, booking, beauty, homeservices, health, auto, rides, maps, delivery, leisure, events, education, support, admin). Общая настройка — `backend/gradle/kunde-module.gradle.kts`; wrapper 8.14.3 с pinned checksum; jar по-прежнему `backend/build/libs/kunde-api-0.1.0-SNAPSHOT.jar`. Локально и в CI: 506 тестов, 0 падений. Docker-образ через pinned wrapper — **локально не собирался** (нет демона), проверяется на Render/CI.
- Конституция [CONSTITUTION.md](docs/architecture/CONSTITUTION.md), [реестр доменов](docs/architecture/domain-registry.md), [Developer Guide](docs/architecture/DEVELOPER_GUIDE.md), решение [ADR-023](docs/architecture/adr/ADR-023-build-system-and-module-structure.md), аудит [project-structure-audit](docs/architecture/project-structure-audit.md).
- Границы: `platform` без доменных импортов; `beauty`/`homeservices` отделены от `booking` через `BookingCategory`; платёжный порт `BookingPayments` (вместо цикла `booking → auto`); `ArchitectureBoundariesTest` видит обращения по полному имени класса (4 прежде невидимые связи `admin → auto/leisure` внесены в baseline), записанные рёбра — `allowed-module-edges.txt`. Baseline: 157 → 144 связи (в 144 включены 4 прежде невидимые, найденные уточнённым детектором; без них 140).
- Flutter (2026-11-24): четыре независимых приложения `apps/{consumer,partner,executor,admin}` + общие пакеты `packages/*`; токен-сессия — общее ядро `kunde_session` и отдельные адаптеры ([ADR-024](docs/architecture/adr/ADR-024-shared-token-session-core.md)). Тесты: Consumer 359, Partner 135, Executor 30, Admin 47, ядро 21. Подписанные DEV APK собираются `release-apk-on-merge`. (Ранее: Executor/Admin отвязаны от потребительской оболочки (`OperatorGate`, замыкание 137→42 / 140→43 файла). отдельные проекты и CI/релиз уже сделаны, см. выше.)

## Готовность к микросервисам (2026-11-24, ветка `claude/kunde-microservices-readiness-0xa17y`)

- Аудит кода: [microservice-readiness](docs/architecture/microservice-readiness.md), [матрица зависимостей](docs/architecture/domain-dependency-matrix.md), [владение данными](docs/architecture/database-ownership-matrix.md), [оценки доменов](docs/architecture/domain-readiness-scores.md), [event-catalog](docs/architecture/event-catalog.md), [fitness-functions](docs/architecture/fitness-functions.md), [ADR-025 (Proposed)](docs/architecture/adr/ADR-025-gradual-service-extraction.md), диаграмма [14](docs/architecture/diagrams/14-domain-components.md). Рост baseline со 140 до 144 объяснён: четыре ранее невидимых импорта `admin → auto/leisure` (детектор D3), новых зависимостей нет.
- Новые ратчеты (`ArchitectureFitnessTest`): слои Gradle, новые рёбра на циклах (узел из 10 пакетов, 20 рёбер), 123 FK между владельцами, HTTP-типы в сервисах. Главные находки: Admin (44 SQL), демо-сиды как источник циклов (V13), FK между владельцами (V14), нет трассировки и инструмента DLQ.
- Долг: API Partner перенесён в `packages/kunde_api`; Executor/Admin — свои ключи secure storage (`kunde.<role>.session.v1`) с миграцией сессии; `executor_delivery` — причина нестабильности: повторное нажатие при отключённой кнопке (`_busy`); сборка Docker-образа backend добавлена в `backend.yml`.
- DEV (Render `kunde-backend`) на `e2e9c5b` (#245), `main` впереди; деплой ждёт разрешения владельца. PROD не затрагивался.

## KUNDE Beauty & Care 1.0 (2026-11-23, ветка `ccr-247e6e41-upaipi`)

- Аудит `main` и план по фазам: [beauty-care.md](docs/product/beauty-care.md). Beauty строится на существующем Booking Engine (барбершопы `BARBER`, защита от двойной записи через `EXCLUDE`).
- Phase 1 (часть 1): флаг `BEAUTY_ENABLED` (по умолчанию выкл., только local/dev/test; закрывает и барбершопы Booking Engine — решение владельца 2026-11-23), V63 (переключатель + `beauty_categories`), `GET /api/v1/beauty/categories`, `beautyEnabled` в capabilities. Локальный PostgreSQL 16: 76 тестов Beauty/Booking/Auto/Partner/Health/Toggles прошли. Consumer: салоны, каталог с серверными фильтрами, карточка услуги, выбор мастера и времени, оформление и подтверждение, акции и избранное, номер записи (V64/V65, RU/KK/EN; backend 94 теста, Flutter 419). Partner-обзор, Executor мастера (по коду приглашения) и Admin-аналитика (V66, грант `BEAUTY_OPERATIONS`). **Не сделано:** hold и онлайн-оплата, перенос, CRUD партнёра, модерация, E2E, DEV-деплой, APK.

## Database sharding readiness, Phase 1 (2026-11-23, ветка `ccr-9632bc84-lc47ye`)

- Аудит: **понятия города в схеме не было** (только текст `education_courses.city` и `region_code` в грантах). Система **не готова** к физическому sharding; блокеры B1–B10 — в [database-sharding-readiness](docs/architecture/database-sharding-readiness.md).
- Добавлено (только expand): миграция V67 (пустой реестр `serviceability.cities`, nullable неизменяемый `city_id` на 7 корнях агрегатов, без backfill), `platform.placement` (`ShardKey/ShardResolver`, `SingleShardResolver` всегда `default`, локаторы агрегатов по ID), реестр `placement-registry.txt` + быстрый `PlacementRegistryTest`, интеграционный `CityPlacementIntegrationTest`. API и поведение не менялись, локаторы пока не подключены к эндпоинтам.
- **Не сделано:** список городов и backfill (нужно решение владельца), решение по платежам, мягкие ссылки вместо FK на users/partners, реплики/пулы/HPA, физические shards.

## Microservice readiness V1 — FeatureGate, V12 — AdminGrants (2026-11-23)

- Outbox/Inbox ([ADR-022](docs/architecture/adr/ADR-022-transactional-outbox.md), PROPOSED, Flyway V68): `platform.events`, relay выключен, ни один продукт пока не публикует события.
- V4: `platform.support.CaseSubjectOwnership` — Support не импортирует rides/delivery (−2 импорта), владение заказом проверяется прежними `get(owner,id)` через адаптеры доменов, fail-closed при старте.
- V3: `platform.support.SupportCaseDirectory` — rides/delivery больше не пишут в таблицы Support (−4 SQL-связи), адаптер в `support`; авторизация в доменах без изменений.
- V2b: `RoutingProvider`, `SyntheticRouting`, `Geo`, `ActiveWork` в `platform`; цикл `delivery ↔ rides` по импортам закрыт (−6 импортов, baseline 46 IMPORT). Остаётся SQL взаимного исключения водитель↔курьер.
- V2a: `Coordinates` и `Point` вынесены в `platform.geo` (JSON тот же), −6 импортов `delivery/maps → rides`. Остаётся цикл `delivery ↔ rides` через `RideRouting`, `RideMatching.distanceMeters`, `ACTIVE_DELIVERY_STATES` и SQL.
- V12: `AdminGrants` перенесён из `admin` в `platform.authz` (только пакет), −6 импортов `домен → admin` в baseline. V9 (`PartnerDirectory`) отложен: SQL Education держит блокировки `for share of p,s`, нужен отдельный дизайн.
- `platform` больше не импортирует настройки 8 из 10 доменов: каждый домен реализует `platform.FeatureGate`, `FeatureToggles` собирает их списком и не стартует без gate на каждый продукт. Baseline импортов уменьшен на 8 (остались `RidesFlags`, `DeliveryProperties`). API и JSON не менялись. `mvn clean verify` на PostgreSQL 16: 492 теста, 0 ошибок.

## Microservice readiness audit (2026-11-23, ветка `ccr-040ab629-xks3w5`)

- Аудит фактического кода: модульный монолит, плоские пакеты, одна БД; связи между модулями — импорты и SQL к чужим таблицам (36 пар по импортам/114 SQL-ссылок в baseline), событий/outbox нет. Maps уже отдельный сервис. Отчёт, матрица готовности, порядок выделения и откат: [microservice-readiness](docs/architecture/microservice-readiness.md).
- Добавлен быстрый тест `ArchitectureBoundariesTest` (без БД; шаг в `backend.yml`): новая межмодульная связь или таблица без владельца ломает сборку, baseline только уменьшается. Бизнес-код и API не менялись; рискованные исправления (V1–V4, V9, V12) оформлены как предложения. Локально `mvn clean verify`: 450 тестов, 0 ошибок.

## KUNDE Maps Platform — интеграция (2026-11-22, ветка `ccr-f8e4fcef-esjxcm`)

- Аудит `main`: Rides и Delivery уже зависят от интерфейса `RideRouting`, но реализован только `SyntheticRideRouting`; в Flutter-приложениях карт нет. [ADR-020](docs/architecture/adr/ADR-020-kunde-maps-platform-integration.md) (PROPOSED) и [ADR 0007 в kunde-maps](https://github.com/ADatkashov/kunde-maps/blob/main/docs/architecture/decisions/0007-kunde-maps-sdk-and-ecosystem-integration.md).
- Backend: `KundeMapsRideRouting` подключает Maps Search/Routing к Rides и Delivery за флагом `MAPS_ENABLED` (по умолчанию выключен, только внутренние среды). Цена по-прежнему считается тарифом Rides, не Maps. Проверено: контрактные тесты на ответах реального DEV Maps, live-тест против DEV (`KUNDE_MAPS_LIVE=true`), интеграционный тест квоты через весь стек Rides.
- **Не сделано:** клиентские экраны (Taxi, Executor, Consumer адреса), reverse-геокодер, трафик, production-включение.

## KUNDE Home Services 1.0

- Исходный `main` `6349b13` содержит пилот уборки на Booking Engine (V19). В рабочей ветке V59 добавляет независимый переключатель `HOME_SERVICES_ENABLED`, выключенный по умолчанию. Контракт и границы пилота описаны в [Booking MVP](docs/product/booking-mvp.md#переключатель-пилота-дом-и-быт).
- В ветке справочника V60 добавляет 8 категорий и 55 наименований RU/KK/EN, API с пагинацией и флагом. Локальный PostgreSQL 16: 21 тест прошёл. [Аудит и детали](docs/product/home-services.md).
- В ветке Admin API V61 добавляет создание, редактирование и отключение категорий, грант `HOME_SERVICES_CATALOG`, контроль версий и журнал. Локальный PostgreSQL 16: 15 тестов прошли.
- В ветке редактора Admin Flutter подключён к API V61: список, создание, редактирование и отключение категории. Многоролевая приёмка открыта.
- В ветке `ccr-7d446c93-dcqb0f` V69 добавляет модерируемые предложения (`home_service_offers`, журнал событий), публичный каталог только опубликованных предложений, Partner API (создание, подача, отзыв) и Admin API модерации с грантом `HOME_SERVICES_CATALOG`; [детали](docs/product/home-services.md#модерируемые-предложения-v69). Экраны Flutter, мастера/назначение, смета, фотоотчёт, отзывы, гарантия, оплата и Maps-трекинг открыты.
- Приёмка Home Services 1.0 открыта. Пилот хранит записи и цены по площади, а подтверждение в нём синтетическое. Коммерческий каталог, роли, оплата, многоролевой E2E и подписанные APK с изменениями ожидают реализации или проверки.

## KUNDE Events & Tickets / Leisure — разделение продуктов (2026-11-21/22)

- **В `main`:** PR [#196](https://github.com/ADatkashov/kunde/pull/196) (`a5745ad`; обязательные Backend/Flutter/Partner Flutter/Security/config и Android visual зелёные, Leisure Android E2E — `PASSED`). Один движок билетов; Events и Leisure — два продукта с раздельными каталогами (`/api/v1/events`, `/api/v1/leisure`), флагами `EVENTS_ENABLED`/`LEISURE_ENABLED`, правами `EVENTS_OPERATIONS`/`LEISURE_OPERATIONS`, глобальным поиском `/api/v1/search/route`, контролёром `GATE` (Flyway V56–V58). Подробности и ограничения: [events](docs/product/events.md).
- **DEV:** `kunde-backend-ty81` развёрнут из `df4fa4d` (deploy `dep-dc18fp9ksfps73867n40`; до этого `a5745ad`, Flyway применил V56–V58, схема v58), `eventsEnabled: true`, `leisureEnabled: true`; `scripts/dev/events_smoke.py` (включая отчёт продаж Partner и изоляцию организаторов) и `scripts/dev/leisure_smoke.py` → `SMOKE OK`. PROD не менялся. Добавлено в [#219](https://github.com/ADatkashov/kunde/pull/219): отчёт продаж по событиям (Partner) и жалобы/отзывы по продукту заказа (Admin).
- **Подписанные DEV Release APK** из `6349b13` (DEV URL, workflow проверяет подпись, package ID, не debuggable): Consumer `com.example.kunde_mobile` ([run](https://github.com/ADatkashov/kunde/actions/runs/44940631508)), Executor `com.kunde.executor` ([run](https://github.com/ADatkashov/kunde/actions/runs/44940637924)), Admin `com.kunde.admin` ([run](https://github.com/ADatkashov/kunde/actions/runs/44940643845)), Partner `com.kunde.kunde_partner` ([run](https://github.com/ADatkashov/kunde/actions/runs/44940650284)).
- **Не подтверждено:** шаги «потеря сети» и «флаг выключен» в приложении на эмуляторе (потеря устройства CI, `UNVERIFIED`), нативные E2E Partner/Admin/Executor для Events, TalkBack и установка APK на устройство, ADMITTED/DUPLICATE на DEV (нет сеанса в окне входа; покрыто интеграционными тестами и E2E), редактор схемы зала (схема задаётся при создании сеансов: ряды, места, VIP), сравнение скриншотов с референсом, Linear.

## KUNDE Groceries 1.0 — DEV/TEST срез (2026-11-21, ветка `ccr-7604baac-80k1na`)

## KUNDE Groceries 1.0 — DEV/TEST (2026-11-21)

- В `main` (V45–V52, PR #195, #197, #204): каталог/поиск/фильтры на сервере, карточка товара с галереей, Share, избранное, списки, серверная корзина, фото и поля товара (Partner), интерактивная сборка с согласованием замен, задачи курьера и экран Executor, Groceries Control Center (scoped `GROCERIES_OPERATIONS`), проверенные отзывы и рейтинг. DEV на `3faa0ee`.
- Проверено: `mvn verify` 389 тестов, Consumer 353, Partner 120; сквозной integration-тест Consumer → Partner → Executor → Consumer → Admin. **Не сделано / NOT VERIFIED:** лояльность (правила не утверждены), уведомления, корректировка по весу, карта в Consumer, нативный Android E2E, реальные Android-скриншоты, APK. Матрица: [groceries](docs/product/groceries.md).

## KUNDE Education & Courses 1.0 — синтетический DEV/TEST

- В `main` после #193, #194, #198–#201: каталог, запись в поток с TEST_CARD, текстовые уроки, задания с проверкой преподавателем, тест, прогресс, PDF с проверяемым кодом и отзыв. Partner создаёт черновик и поток, Admin модерирует, Executor работает с назначенной группой. Миграции Education: V44, V48–V49 и V53–V55.
- [Контракты, покрытие и ограничения](docs/product/education.md). Полная техническая приёмка остаётся открытой.

## KUNDE Food Ordering 1.0 — slice 1: location, hours, distance (2026-11-26, ветка `ccr-d1e798b4-0h5jn4`)

- Flyway V71: координаты ресторана, недельный график (Asia/Almaty, ночные слоты, `24:00`), функции `food_restaurant_open`/`food_distance_m`. Единое «открыто сейчас» (переключатель + модерация + график) во всех чтениях каталога и в checkout (`409 RESTAURANT_CLOSED` вне графика). `distanceMeters`, `sort=distance`, `maxDistanceMeters` (по прямой, без выдуманных значений); Partner `PUT …/hours`, `PUT …/location`, `GET …/schedule` (Owner/Manager, аудит); синтетические координаты DEV-сида.
- Проверено локально: `./gradlew test` на PostgreSQL 16 — 530 тестов, 0 падений (новый `FoodScheduleApiIntegrationTest`, 5 тестов; fitness-функции и владение схемами зелёные). **Не проверено:** Flutter (в окружении нет SDK), DEV-деплой V71, смоук на DEV. UI этих полей не реализован. Детали и список оставшегося: [food-mvp](docs/product/food-mvp.md#food-location-opening-hours-and-distance-flyway-v71-devtest--2026-11-26).

## KUNDE Food Ordering 2.0 — DEV slice (2026-11-21, ветка `ccr-0b95f693-1hsj46`)

- Flyway V43: самовывоз, акции и промокоды (скидка считается на сервере), избранное и проверенные отзывы с рейтингом в PostgreSQL, `READY_FOR_PICKUP`, настройки ресторана и акции Partner, Admin Food API (`FOOD_OPERATIONS`, дашборд из реальных данных, модерация, тестовый возврат, аудит). Consumer: серверные фильтры и сортировка, категории и баннер акции только из данных backend, переключатель «Доставка/Самовывоз», промокод, вкладки Меню/Отзывы/О заведении, отзыв после доставки. Partner: статус «Готов», самовывоз, скидка в заказе.
- Проверено локально: `mvn verify` на PostgreSQL 16 — 366 тестов, 0 падений; `scripts/dev/food_smoke.py` против локального jar на чистой БД (V1–V43) — `SMOKE OK`; Consumer `flutter analyze --fatal-infos` чисто, 283 теста (включая 6 тестов Admin Food); Partner 117 тестов. Admin Flutter: экран «Еда: центр управления» (обзор из реальных данных, заказы с тестовым возвратом, рестораны, акции, отзывы, журнал). Partner: условия заказа (самовывоз, время готовности) и акции.
- **В `main`:** PR [#191](https://github.com/ADatkashov/kunde/pull/191) (`fd1fbb6`, обязательные Backend/Flutter/Security/Partner Flutter CI зелёные). **DEV:** `kunde-backend-ty81` развёрнут из `fd1fbb6` (deploy `dep-dc0maqu7bikc73b84okg`, 2026-11-21), Flyway V43 применён, `scripts/dev/food_smoke.py` → `SMOKE OK`. PROD не менялся.
- **Не сделано:** аналитика и CRUD секций/модификаторов в Partner, фото, карта и маршрут (нет провайдера), расстояние (нет координат), лояльность, push, нативный Android E2E, подписанные APK. Матрица соответствия референсу: [food-mvp](docs/product/food-mvp.md#food-20-flyway-v43-devtest--2026-11-21).

## KUNDE Leisure & Entertainment 1.0 — DEV (2026-11-20)

- Backend в `main` ([#175](https://github.com/ADatkashov/kunde/pull/175), Flyway V40): общая модель на 5 типов бронирования и 16 категорий, каталог/поиск, удержание мест, идемпотентные заказы, QR-билеты с серверной проверкой, `TEST_CARD`/`PAY_ON_SITE`, возвраты, модерация, аудит, Executor-назначения, флаг `LEISURE_ENABLED` (включён в local/dev/test, выключен в production). Flutter-интерфейс Consumer/Partner/Admin/Executor — [#177](https://github.com/ADatkashov/kunde/pull/177) (в `main`, `3e77801`).
- **DEV:** `kunde-backend-ty81` развёрнут из `3e77801` (deploy `dep-dc0k3hk0916s73bvv6sg`, 2026-11-21), `LEISURE_ENABLED=true`, `LEISURE_SEED_DEMO=true`, `scripts/dev/leisure_smoke.py` → `SMOKE OK`. PROD не менялся.
- **Нативный E2E на эмуляторе** ([`Leisure Android E2E`](https://github.com/ADatkashov/kunde/actions/runs/44877393970), зелёный на `243f843`): вход → Досуг → места → TEST_CARD → QR → скан на входе → «Использован» → отзыв → потеря сети, плюс HTTP-сценарии (гонка за место, идемпотентность, флаг выключен). Шаг «приложение при выключенном флаге» не блокирующий: эмулятор CI терял связь на нём в 5 прогонах подряд (причина не установлена), статус `complete_flag_off_ui_UNVERIFIED`; серверная часть проверена по HTTP, экран — виджет-тестом.
- **Подписанные DEV Release APK** из `3e77801` (DEV URL внутри, не debuggable, подпись `CN=KUNDE DEV`, v2): Consumer `com.example.kunde_mobile` ([run](https://github.com/ADatkashov/kunde/actions/runs/44878215167), SHA-256 `90db643b…03f5fb`), Executor `com.kunde.executor` ([run](https://github.com/ADatkashov/kunde/actions/runs/44878218292), `d3eb5b71…4affed`), Admin `com.kunde.admin` ([run](https://github.com/ADatkashov/kunde/actions/runs/44878221110), `9608019f…d95d62f`), Partner `com.kunde.kunde_partner` ([run](https://github.com/ADatkashov/kunde/actions/runs/44878223735), `6c30aed9…4704ff54`).
- **Не подтверждено:** установка APK на устройство и TalkBack, нативные E2E Partner/Admin/Executor (покрыты виджет-тестами и HTTP), экран выключенного флага на эмуляторе, карта, фото, push, реальные платежи, Linear. Подробности: [leisure](docs/product/leisure.md).
## KUNDE Health & Wellness 1.0 — внутренний пилот

- Стартовый аудит сверил `origin/main` `30f4bc5`, открытый Leisure [#175](https://github.com/ADatkashov/kunde/pull/175) и [последний Security CI на main](https://github.com/ADatkashov/kunde/actions/runs/44784856492). Linear доступен, отдельный Health-тикет поиском не найден.
- В main через [#176](https://github.com/ADatkashov/kunde/pull/176): V41, синтетический каталог, общий Booking Engine и тестовый ledger, Consumer, управление площадкой через Partner и модерация Admin. Реестр возможностей, проверок и ограничений — в [Health PRD](docs/product/health-wellness.md).
- Render DEV обслуживает `14f851dbe81480bbee66c343c9ab83cfbf2c602c`. Neon V42, `healthEnabled: true`. В DEV проверены фильтры [#183](https://github.com/ADatkashov/kunde/pull/183), число результатов [#188](https://github.com/ADatkashov/kunde/pull/188), избранное [#186](https://github.com/ADatkashov/kunde/pull/186) и оба способа синтетической оплаты. [Доказательства DEV](docs/product/health-wellness.md#проверки-21-ноября)
- Полная приёмка DEV/TEST открыта. Профиль специалиста и Android E2E объединены в [#178](https://github.com/ADatkashov/kunde/pull/178), создание услуг и специалистов Partner объединено в [#179](https://github.com/ADatkashov/kunde/pull/179). Повторный Android E2E после визуальных исправлений [#181](https://github.com/ADatkashov/kunde/pull/181) прошёл. Результаты сверены с Linear ADA-66.

## KUNDE Control Center 3.0 — DEV

- [Аудит и зависимости](docs/roadmap/27-control-center-2-audit.md) приняты в [#155](https://github.com/ADatkashov/kunde/pull/155). [#156](https://github.com/ADatkashov/kunde/pull/156) добавил `GET /api/v1/admin/me/capabilities` для действующих грантов текущего сотрудника. Backend CI и Security CI прошли на PR.
- [#157](https://github.com/ADatkashov/kunde/pull/157) добавил навигацию по разрешённым очередям Rides, Delivery и Auto.
- [#160](https://github.com/ADatkashov/kunde/pull/160) добавил назначения ролей с областью, сроком действия и отзывом. [#161](https://github.com/ADatkashov/kunde/pull/161) применяет область к списку отправлений Delivery и аудиту. [#162](https://github.com/ADatkashov/kunde/pull/162) открывает эти два сценария во Flutter для scoped-оператора.
- [#164](https://github.com/ADatkashov/kunde/pull/164) добавил серверный реестр сотрудников с постраничной выдачей под действующим платформенным `ADMIN_GRANTS`. Управление назначениями и D-14 остаются открытыми.
- [#165](https://github.com/ADatkashov/kunde/pull/165) добавил Flutter-реестр сотрудников. [#163](https://github.com/ADatkashov/kunde/pull/163) и [#166](https://github.com/ADatkashov/kunde/pull/166) добавили scoped-сводку Delivery и выбор периода.
- [#168](https://github.com/ADatkashov/kunde/pull/168) добавил адаптивный обзор со scoped-метриками Delivery и действующими разрешениями. Flutter Analyze и 253 локальных теста прошли на `6252018`. Дополнительно проверены 18 сочетаний ширины, языка и темы с текстом 200%, загрузкой, ошибкой, повтором и пустым результатом.
- Web PR [#159](https://github.com/ADatkashov/kunde/pull/159) и [#152](https://github.com/ADatkashov/kunde/pull/152) объединены. Выпущен проверенный подписанный [Admin DEV APK](https://github.com/ADatkashov/kunde/actions/runs/44804997291/artifacts/14663216127). Нативный авторизованный Admin E2E остаётся открытым.
- В работе: scoped RBAC, панели продуктов, реестры, поддержка, финансы, операции, аудит и проверка поставки на всех платформах. Functional DEV/TEST Ready ещё не подтверждён.

## KUNDE Auto 1.0 — backend slice (в работе)

- Backend Auto (Flyway V34) построен на Booking Engine: автомобили, серверные котировки, идемпотентная запись, защита от двойной записи и буфер, перенос/отмена, жизненный цикл партнёра с согласованием цены, недоступные периоды, Admin и флаг `AUTO_ENABLED` (выключен). `mvn verify` на PostgreSQL 16: 316 тестов, 0 ошибок. Детали и ограничения: [auto](docs/product/auto.md).
- В `main`: backend (#149), Consumer + Partner + backend Executor (#150), Executor Flutter (#151). Далее: Admin, жалобы и отзывы (V36), локально `mvn verify` 325, Flutter 244 теста, `flutter analyze --fatal-infos` чисто; на устройстве не проверено.
- Платёжный DEV-контракт (V38, ledger-only TEST_CARD/PAY_ON_SITE, возвраты админом, без реальных списаний): `mvn verify` 334, Flutter 244 — локально; подробности в [auto](docs/product/auto.md).
- **DEV:** Auto включён на DEV-сервисе (`AUTO_ENABLED=true`, `AUTO_SEED_DEMO=true`, `main` 77b86a0); `scripts/dev/auto_smoke.py` и `booking_smoke.py` пройдены на DEV. PROD не менялся, публичный приём выключен.
- Переключатели Auto/Rides/Delivery в Control Center (V39, грант `ADMIN_GRANTS`, потолок — переменные окружения, журнал, причина обязательна): [feature-toggles](docs/engineering-foundation/feature-toggles.md). Booking/Food — пока только окружение.
- Android E2E Auto (`.github/workflows/auto-native-e2e.yml`, `scripts/ci/auto_native_e2e.py`, PR #173): Consumer APK на эмуляторе Android 35 против реального backend и PostgreSQL 16 — 14 этапов `PASSED` (вход, авто, каталог, слот, котировка, запись с `TEST_CARD`, история и оценка, согласование цены, перенос и отмена, потеря сети и повтор, идемпотентный повтор, отказ партнёра, конкурентная запись, нет слотов, выездная заявка Executor, выключенный флаг). Партнёр и исполнитель в этом прогоне действуют через HTTP; их приложения проверяются своими тестами. Подробности: [auto](docs/product/auto.md#android-e2e).
- Подписанные DEV Release APK (Consumer, Executor, Partner, Admin) из `main` e831750: сертификат `6645a7bc…d600`, подпись v2, не debuggable; идентификаторы и SHA-256 в [auto](docs/product/auto.md#dev-release-apk).
- **Не готово:** проверка на физическом устройстве и TalkBack, нативный E2E Partner и Executor, экран платежей Admin, синхронизация Linear (коннектор недоступен). Статус Functional DEV/TEST Ready **не** заявлен: решение за владельцем после проверки на устройстве.

## KUNDE Delivery 1.0

- Персональные и корпоративные отправления используют текущую платформу. Consumer оформляет и отслеживает отправление. Executor принимает оффер и подтверждает вручение. Partner работает с отправлениями своей организации. Admin проверяет курьеров, аудит, возвраты и жалобы.
- В `main` вошли лимиты отправлений и параметры сохранённой котировки, форма Consumer, создание реального отправления Partner за флагом Maps и журнал статусов. [#224](https://github.com/ADatkashov/kunde/pull/224) · [#225](https://github.com/ADatkashov/kunde/pull/225) · [#230](https://github.com/ADatkashov/kunde/pull/230) · [#227](https://github.com/ADatkashov/kunde/pull/227).
- Android Consumer → Executor прошёл с тестовым маршрутом. Отдельный HTTP-прогон изолированного Spring Boot и PostgreSQL c реальным Maps Routing подтвердил котировку, назначение, вручение, оценку, владение отправлением Partner и видимость в Admin. Четыре подписанных DEV APK собраны из промежуточного SHA `eb5f1f0`. [Проверки и архивы APK](docs/product/delivery.md#dev-проверки-и-сборки).
- Для полной DEV-приёмки нужны интегрированные нативные сценарии четырёх ролей с картой и платёжный провайдер. Публичный приём выключен. [Актуальный аудит](docs/product/delivery-1.0-audit.md).

## Rides & Transport 1.3

- Backend поездок, Consumer, Executor, тестовая маршрутизация, Partner Fleet и Admin вошли в `main` через [#131](https://github.com/ADatkashov/kunde/pull/131)–[#137](https://github.com/ADatkashov/kunde/pull/137). Продолжение интеграции — [#138](https://github.com/ADatkashov/kunde/pull/138) и [#139](https://github.com/ADatkashov/kunde/pull/139).
- **Functional DEV/TEST ready** проверяется нативным E2E и двумя подписанными DEV APK на интегрированном коммите. [Прогон ветки](https://github.com/ADatkashov/kunde/actions/runs/44455026918) подтвердил поездку, координаты, историю, отмену, сетевое восстановление и повтор запроса.
- **External integration pending** — дорожная маршрутизация Алматы, платёжный цикл, загрузка и проверка файлов водительских документов.
- **Production launch blocked** — Rides выключен по умолчанию и разрешён только во внутренних средах. [Проверка DEV E2E](docs/product/rides-transport.md#нативный-e2e) · [Установка APK](docs/infrastructure/android-release-apk.md).
- **Consumer, экран заказа с KUNDE Maps (2026-11-23, за флагом `MAPS_ENABLED`):** «Откуда» по умолчанию «Моё местоположение» (позиция устройства только для этого экрана), адрес ищется поиском KUNDE Maps (`LocationPicker`), после выбора обеих точек сервер котирует все классы (Эконом, Комфорт, Бизнес, Минивэн) параллельно; класс без тарифа (`RIDE_CLASS_UNAVAILABLE`) не показывается; кнопка «Заказать · цена ₸» заказывает выбранную котировку, просроченная котировка пересчитывается. Проверено: `flutter analyze --fatal-infos` чисто, `flutter test` Rides/Delivery/Executor/Home/Shell зелёные. **Не сделано:** оплата и промокод (нет в backend, в интерфейс не добавлены), «~N мин» до водителя (нет данных о наличии водителей), нативный E2E и скриншоты на устройстве, включение `MAPS_ENABLED` на DEV не проверялось.

## KUNDE Premium UI 2.1

- [PR #128](https://github.com/ADatkashov/kunde/pull/128) updates the five Consumer tabs: Home, Catalog, KUNDE AI, Orders and Profile. The booking catalog remains available from Home and Catalog. Restaurant data, order history, profile, addresses and repeat order use existing APIs.
- KUNDE AI has a localized Soon preview with disabled sending. Catalog and order surfaces keep DEV data and payment labels. The Consumer profile omits phone or statistics that its API does not return.
- [PR #127](https://github.com/ADatkashov/kunde/pull/127) remains the prior signed DEV baseline. See PR #128 for the Android before/after captures, checks and signed release evidence.

## KUNDE Premium UI 2.0

- Consumer and standalone Partner share the violet/gold Material palette. Both default to light mode; Consumer saves the theme device-side. Consumer home, search entry points, order history/details, and profile use existing routes and server capabilities.
- Consumer assistant has a localized unavailable state and a UI adapter seam. The backend still reports AI disabled. Executor has no app/API and Admin verification is API-only.
- Backend regression checks: Maven verify on PostgreSQL 16.16 passed 265 tests.
- Acceptance still needs a signed Consumer DEV build and a phone run for navigation, checkout, orders, language/theme and TalkBack.

## KUNDE Partner 2.0 — standalone app rebuilt, 2026-11-17 (DEV)

- Merged: [#121](https://github.com/ADatkashov/kunde/pull/121) (`724fee0`) design system (Material 3, deep-green, light/dark), RU/KK/EN strings, typed models, hardened API/session (UTF-8, single-flight refresh, session restore, offline-safe), Home dashboard (real data only), orders (tabs, details, server-driven actions, reasons, countdown), bookings (requests/upcoming/history, date/status filters, confirm/reject/cancel/complete), partner choice, roles, foreground alerts. Fixed defects: partner name read from wrong field, order/booking fields not parsed, latin1 decoding of Cyrillic, no session restore, refresh error wiped session, hard-coded booking buttons. PR [#122](https://github.com/ADatkashov/kunde/pull/122): business management (open state, menu/price/stock, add dish, services, specialists, weekly schedule) and signed Release APK workflow `partner-release.yml` (applicationId `com.kunde.kunde_partner`).
- **Verified:** `flutter analyze --fatal-infos` clean; 105 partner tests (unit, API contract with fake backend, auth/session, controller, store, widget, accessibility guidelines, 200% text at 320/360 dp). CI on #121 green (partner-flutter, partner-android debug build). Backend unchanged.
- **Signed Release APK:** [run 44132726419](https://github.com/ADatkashov/kunde/actions/runs/44132726419) on `dda8620` succeeded (analyze/test, signature v2/v3 not debug, package `com.kunde.kunde_partner`, label, INTERNET, not debuggable, arm64, DEV API host, no secrets); artifact `KUNDE-Partner-dev-release` id 14350517707, artifact digest `sha256:baac203675e7eccc614362da0c685fc881429ce7bcc0c01ac24f207ab3d9a7d8`, expires 2026-12-01.
- **Not verified:** phone check (see NEXT_TASK); TalkBack on device; KK strings unreviewed; background push absent; PROD untouched. API gaps (stats endpoint, customer details, restaurant hours, partner slot list, staff management, push) are listed in [partner-app](docs/product/partner-app.md). Details: [partner-android-release](docs/infrastructure/partner-android-release.md).

## Partner Operations — follow-ups merged, 2026-11-16 (DEV)

- Merged to main (`8eac9db`, required CI green on each): [#105](https://github.com/ADatkashov/kunde/pull/105) partner response timeout (D-05: 300 s, system cancel `PARTNER_TIMEOUT`, `respondBy`/`reminderAt`), in-app alert (sound/haptic/banner) for new orders/requests, partner section hidden from non-staff unless `PARTNER_APPLY_ENABLED` (workflow input `partner-apply`); [#106](https://github.com/ADatkashov/kunde/pull/106) DEV flag `AUTH_DEV_OTP_SKIP_THROTTLE` (no OTP request throttling for the allowlisted synthetic numbers only; set on DEV); [#107](https://github.com/ADatkashov/kunde/pull/107) partner edits dish name/description/price and adds dishes (Owner/Manager; operators keep availability/stock), audited. Details: [partner-operations](docs/product/partner-operations.md).
- **Verified:** backend `mvn verify` on PostgreSQL 16 — 264 tests, 0 failures; Flutter 3.47.9 analyze/format clean, 194 tests pass. DEV `kunde-backend-ty81` redeployed (`dep-dbtlk6gae00c73e9sukg`, `8eac9db`); `partner_ops_smoke.py`, `food_smoke.py`, `booking_smoke.py` print `SMOKE OK`; menu price edit/create/duplicate 409 checked over HTTP on DEV; OTP login for `+77000000001/2/3` checked after the throttle flag. **APK:** run 43940248100 (`8eac9db`, rerun after a runner NDK download error), sha256 `748991f18eb86307276e05350cf910c09d4cbd857644add95bede695bd73964d`. Owner reported the Partner Operations scenario works on a phone (no TalkBack/device details).
- **Not verified / open:** response timeout and alerts on a phone; KK strings unreviewed; no background push (D-11), no staff-management screen, no dish deletion/photos/option groups; PROD untouched; Linear ADA-84/ADA-83 stay In Progress (production gates).

## Partner Operations MVP — 2026-11-16 (DEV)

- Merged as [PR #103](https://github.com/ADatkashov/kunde/pull/103), main `b0e8fed` (required CI green: backend, flutter, configuration, containers, dependencies, secrets, validate). Flyway V20; partner order inbox/accept/reject/status flow for Food/Grocery, booking requests (`PENDING` holds the slot) with confirm/reject/cancel/complete, availability/stock/schedule with conflict protection, RBAC + ownership isolation, idempotent transitions, row locks, append-only audit; Flutter partner hub (Orders/Bookings/Availability) for approved-partner staff only. Details/limits: [partner-operations](docs/product/partner-operations.md).
- **Verified:** backend `mvn verify` on PostgreSQL 16 — 260 tests, 0 failures (15 new); Flutter 3.47.9 analyze/format clean, 190 tests pass. **DEV:** `PARTNER_OPS_SEED_DEMO=true` set and manual deploy `dep-dbtkgpou01pc73e6qu7g` of `b0e8fed` to `kunde-backend-ty81`; `scripts/dev/partner_ops_smoke.py`, `booking_smoke.py` and `food_smoke.py` against it all print `SMOKE OK` (access control, order and booking end-to-end, history after session refresh; history also verified after a restart of a local jar). **APK:** [run 43927055620](https://github.com/ADatkashov/kunde/actions/runs/43927055620) (`b0e8fed`, partner-features on, DEV OTP hint on), artifact `KUNDE-dev-release` id 14255689393, artifact digest `sha256:9b3d2495fe4914d6668f09b947246690a2b3dd66c7af99944aaaff774d3aee90`, expires 2026-11-30.
- **Not verified:** install and use on a phone, TalkBack; KK strings of the partner hub are unreviewed; no notifications (polling); PROD untouched, no real payments/providers. Linear partner/order tasks stay open (production gates).

## Category architecture + Home services (cleaning) — 2026-11-15

- Owner decision: user categories follow life needs (Food, Groceries, Rides, Delivery, Home services, Beauty, Health, Auto, Leisure); «Все сервисы» is a catalog. Booking remains one internal mechanism. Implemented on a branch from main `59295d0`: Home tile «Красота» → Барбершопы, «Дом и быт» → Уборка (type, address, area, demo price estimate, free slot, request, history, free cancel before start); Flyway V19 (cleaning pricing by area, booking category/address/area; old bookings stay `BARBER`); RU/KK/EN strings. Details/limits: [booking-mvp](docs/product/booking-mvp.md#category-architecture-and-home-services--cleaning-owner-decision-2026-11-15-dev).
- Verified locally: backend `mvn verify` on PostgreSQL 16 — 245 tests, 0 failures (incl. 2 new cleaning/compat tests); real-HTTP `scripts/dev/booking_smoke.py` (barbershop + cleaning: book, replay, overlap 409, validation 400, restore after session refresh, cancel) and `food_smoke.py` against a local jar — OK; Flutter 3.47.9 `analyze --fatal-infos` clean, format clean, 183 tests pass (goldens of Home updated: «Красота» tile replaces «Услуги»). PR #101 merged as `d39ce3a` with all required CI green. **DEV (2026-11-16):** manual deploy `dep-dbt8akl6e07s73bngoig` of `d39ce3a` to `kunde-backend-ty81` (V19 applied, cleaning venue seeded); `booking_smoke.py` (barbershop + cleaning) and `food_smoke.py` against it pass. **APK:** run 43803858989 (`d39ce3a`, partner-features on, DEV OTP hint on), artifact `KUNDE-dev-release` id 14197846592, sha256 `8c987c93c5824fa86eec8b87c94d97d8952fe7966eb46d19795f6571ddaa10e5`, expires 2026-11-30. **Not verified:** install and use on a phone (owner), TalkBack.

## Premium Flutter UI — signed release verified, 2026-11-15

- Premium redesign merged as [PR #98](https://github.com/ADatkashov/kunde/pull/98), font-license packaging fix as [PR #99](https://github.com/ADatkashov/kunde/pull/99). White/emerald default, original K/Almaty header, bundled 3D categories, AI «Скоро», Food photo banner, unified Food/Grocery/cart/checkout/history/profile, five tabs Home/Search/Orders/Services/Profile. Backend/business flows unchanged; sources/licenses in `mobile/assets/README.md`.
- **Verified:** Flutter analyze/format clean; **178/178 CI tests, 0 skipped**, including 11 new golden baselines, Samsung 360/390/412 dp with 200% text and bundled OFL/MIT license checks. Main `59295d0` Flutter/Security/CI configuration green. Signed [Release run 43770508122](https://github.com/ADatkashov/kunde/actions/runs/43770508122) succeeded (analyze/test, release build, signature/appId/INTERNET/non-debuggable/ARM64/API/no-secret checks). Artifact `KUNDE-dev-release`, id `14184357296`, 22,325,530-byte APK, expires 2026-11-29. SHA-256 `8a8c9f1e2051a7579cc6905cfd6f72a2b88238081ab56460f7191bdb5331d682`. Downloaded bytes match the workflow hash; ARM64, DEV API host and OFL/MIT license files additionally inspected inside the APK. Partner features retained. Current DEV capabilities read: Food=true, Booking=true, AI=false.
- **Not verified:** installation/use of this redesigned APK on a physical Samsung or TalkBack. Next: owner phone check; existing DEV payment/delivery simulation limits unchanged. Details/screens/tests: [premium UI evidence](docs/design/premium-ui-redesign.md).

## DEV deploy permission (owner, 2026-11-15)

- Owner gave a standing permission to deploy `main` to the existing DEV backend and set DEV pilot flags without asking each time; scope and exclusions (no PROD, no service/DB replacement, no `terraform apply`, no secrets, no real payments) are recorded in [AGENTS.md](AGENTS.md). Booking (V18) was deployed to DEV under this permission: deploy `dep-dbt2t4u7bikc73css3g0` of `420b595` with `BOOKING_ENABLED`/`BOOKING_SEED_DEMO`. **Verified on DEV (2026-11-15):** `/capabilities` reports `bookingEnabled=true`; `scripts/dev/booking_smoke.py` against `kunde-backend-ty81` passed (V18 incl. `btree_gist` applied on Neon; 4 venues; booking, idempotent replay, slot disappears, overlapping booking refused with 409, restore after session refresh, cancel, slot freed) and `scripts/dev/food_smoke.py` still passes (Food + Grocery unaffected). Release APK from run 43767173233 (`420b595`, sha256 `a6b401a5b476a2353bf18de12ec9246f93e96a964af2812ed00feb6b32143555`) was delivered to the owner; **not yet verified on a phone** (Booking scenario: Home → Услуги → barbershop → service → master → slot → book → restart → Orders → Записи → cancel).

## KUNDE Booking MVP — barbershops (2026-11-15, owner-approved category B)

- Owner approved booking as the next category, first service barbershops (cleaning/other services later). Implemented for DEV: Flyway V18 (`btree_gist` exclusion constraint prevents overlapping bookings of one master), slots API, idempotent booking, free cancellation before the start, 4 synthetic barbershops (9 masters), DEV-mock confirmation (labelled), Flutter «Услуги» → barbershop → service → master → slot → confirm, bookings history in Orders → «Записи». Details/limits: [docs/product/booking-mvp.md](docs/product/booking-mvp.md).
- Verified automatically: backend 243 tests on PostgreSQL 16 (incl. direct-SQL overlap rejection), real-HTTP `scripts/dev/booking_smoke.py` against a local jar, Flutter analyze clean and 163 tests. **Not verified:** DEV deploy (needs separate approval: `BOOKING_ENABLED`/`BOOKING_SEED_DEMO`, V18), a new APK on a phone.

## Product Delivery 2.0 — 2026-11-15

- **Manual confirmation (owner):** the Release APK from run 43734913344 (`58cf20a`, Food + Grocery MVP, DEV `kunde-backend-ty81`) was installed on a real Samsung phone; the owner reported "Установил, проверил, всё работает". Nothing more detailed was reported (no scenario list, TalkBack or other devices).
- **Grocery completion (V17):** weighed goods (grams, per-kg price), stock reservation/return, customer-consented substitutions with order-change display, photo URLs (no photos bundled), catalog filters, skeleton loading. Verified automatically: backend 237 tests on PostgreSQL 16 (V17 also applied over existing V15/V16 data), local real-HTTP smoke OK, Flutter analyze clean and 158 tests. Details: [docs/product/food-mvp.md](docs/product/food-mvp.md). **Not verified:** DEV deploy of V17, a new APK on a phone.
- Linear FEAT-009 (cart/checkout, ADA-40), FEAT-010 (order state, ADA-41), FEAT-008 (ADA-39) stay open: acceptance is not complete (real payments, partner order handling, production gates).

## KUNDE Grocery MVP (DEV pilot) — 2026-11-15

- Reuses the Food stack via `vertical=GROCERY` (Flyway V16, 4 synthetic stores, 45 products): same cart quote, idempotent orders, mock payment, simulated delivery, history; Flutter Home category «Продукты». Details/limits: [docs/product/food-mvp.md](docs/product/food-mvp.md#grocery-mvp-same-dev-pilot-same-gates). Verified locally: backend 233 tests pass on PostgreSQL 16, Flutter analyze clean and 155 tests pass. **Not verified:** DEV deploy of V16/Grocery, device run.

## KUNDE Food MVP (DEV pilot) — 2026-11-15

- **Product-first priority (owner, 2026-11-15):** a working Food scenario before more infrastructure. Backend merged in PR #92 (`1b12038`): Flyway V15, `/api/v1/food` (restaurants, menus, search, server-side cart quote, idempotent orders, history, cancel before acceptance, repeat), synthetic demo seed (8 invented restaurants, 56 dishes, KZT), DEV-only mock payment (`TEST_CARD` / cash on delivery) and **simulated** fulfillment by elapsed time. `FoodGuard` forbids it outside dev/local/test; ADR-014 default is unchanged. Details and limits: [docs/product/food-mvp.md](docs/product/food-mvp.md).
- **Verified (local):** backend `mvn test` on PostgreSQL 16 — 232 tests, 0 failures; real-HTTP smoke `scripts/dev/food_smoke.py` against a locally started jar — OK (order persisted, idempotent replay, restored after session refresh, cancel). Flutter (PR #93): `analyze --fatal-infos` clean, 153 tests pass incl. order → app restart → order in history on an in-memory backend.
- **Not verified:** DEV deployment of Food (needs Terraform apply with `replace_render=true`, owner approval; the Render URL changes on replace), install/use on a physical Samsung, TalkBack. No real payments, couriers, photos, notifications or serviceability zones; UI strings are Russian only.

## Audit 2026-11-15 (main `86a6c31`, PR #89)

- **GitHub:** all four automatic workflows (Backend, Flutter, Security, CI configuration) green on `86a6c31`; PR #84–#89 merged, no open PRs, #79 closed unmerged. Security CI `containers` job failed on three earlier main pushes (`a9cb8e0`, `ddc8ae4`, `254587b`) at step "Resolve immutable linux-amd64 manifests" (registry resolution, not a finding) and passed on later runs. CodeRabbit left only summary comments on #84–#89 (no inline threads found). **Not verifiable by the agent (API 403 through the proxy):** branch protection/required checks, Environments (`dev` reviewers), Secrets/Variables metadata, secret scanning; Dependabot alerts are disabled for the repository.
- **Backend:** `mvn clean verify` on PostgreSQL 16 locally — 223 tests, 0 failures (Flyway V1–V14).
- **DEV (live check):** Render `kunde-backend` was replaced on 2026-11-14 and now lives at `https://kunde-backend-ty81.onrender.com` (old `-5wwg` host returns `no-server`; workflow default and docs were stale and are fixed). Verified on it: liveness/readiness 200, `GET /categories` `[]`, `/me` 401 unauthenticated, phone OTP request 202, DEV login with a synthetic allowlisted number issues tokens and `/me` 200, wrong code 401. **Redeployed from `main` `86a6c31` on 2026-11-15 with owner approval (Render deploy `dep-dbsq2jgn74is73ajd050`, live; autoDeploy stays off):** Flyway V10–V14 applied (service starts, readiness 200); `/partner/*` and `/admin/*` now return 403 for a user without `kunde.partner`/`kunde.admin` (were 404 on the old build). No synthetic admin exists yet and `food-ordering` is still an unpublished DRAFT, so the partner→catalog scenario has not been run.
- **Linear:** ADA-69 (TASK-003) returned Done → In Progress (backlog is `partially_verified`); TASK-017 set to `in_progress` in the backlog to match Linear ADA-83; stale notes on TASK-005/015/016 amended. No duplicates; all 56 TASK IDs present.
- **Android Release APK:** run 43712714294 (workflow_dispatch on `main` `d6167ec`, `partner-features=true`, DEV OTP hint on, API `kunde-backend-ty81`) succeeded: analyze, tests, signed `flutter build apk --release` (arm64) and the *Verify APK* step (signature, appId, INTERNET, non-debuggable, arm64, API URL, no secrets). Artifact `KUNDE-dev-release` (id 14161252882, sha256 `d4db9b2a26fb801925bcecafaff27e0d3500cad090b01bed928760e59765a4da`, expires 2026-11-29). Not verified: install and use on a physical device, TalkBack. CodeRabbit does not auto-review this repository (fewer than 10 stars), so absence of inline comments is not review evidence.

## Verified main snapshot — 2026-11-13 (history; superseded by the audit above)

- **DEV deployed (2026-11-14, owner-approved applies, synthetic data only):** Terraform (`infrastructure/terraform`, PRs #71–#75) manages Render Free `kunde-backend` (Frankfurt, https://kunde-backend-5wwg.onrender.com) and Neon Free `kunde-dev` (`aws-eu-central-1`); state in HCP Terraform workspace `kunde-dev`; GitHub Actions `terraform-dev.yml` (validate, plan, cost gate `check_terraform_plan.py`, manual apply). Verified on the live service: `readiness`/`liveness` 200, protected endpoint 503 (fail-closed), OpenAPI 200, `GET /api/v1/categories` 200 `[]`, Flyway V1–V8 over TLS (`verify-full` + `DefaultJavaSSLFactory`). Known limits: Render provider 1.9.1 cannot update free services in place (issue #80) — changes need `replace_render`; free hours are shared with the owner's 6 other Render services and Neon Free has 100 CU-hours/month (cost not confirmed as $0); cold start ~1 min; Required reviewers on the `dev` Environment are **not** configured (apply ran without a pause). Production hosting/residency still blocked (TASK-051/D-08); TASK-052 stays not_started (no prod staged deploy/rollback); ADR-017 Proposed. Docs: [docs/infrastructure](docs/infrastructure/README.md).

- **D-03/D-04 APPROVED for a limited DEV pilot (2026-11-14, Product Owner):** pay on receipt, no online payment/provider, KUNDE takes no customer money; KZT, one final price, commission 0%, service fee 0, promo codes off, no tax logic. Temporary, not the production model; TASK-025/026/028 stay gated. Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md). Flyway V11 adds `offerings.price_minor`/`currency`(KZT)/`availability`; PUBLISHED needs a price; consumer offering API and Flutter list show the KZT price and availability. Backend `CatalogControllerTest` + `DomainSchemaOwnershipIntegrationTest` pass locally on PostgreSQL 16 (19 tests); Flutter not run locally (no SDK here), relies on CI.
- **D-14 / partner identity — ADR-018 ACCEPTED (2026-11-15, Product Owner):** [ADR-018](docs/architecture/adr/ADR-018-partner-and-admin-identity-roles.md) approved for synthetic DEV implementation (no Keycloak/ZITADEL; admin never via public registration; production admin needs step-up/dual control). Steps 1-5 done: step 5 = Flutter partner section behind `PARTNER_FEATURES_ENABLED` (off by default; Profile tab "For partners": apply, own partners with status/role, offerings page with KZT price, availability, create/edit/publish/withdraw, operators read-only; `GET /partner/categories` added for the form; workflow input `partner-features`); `flutter analyze --fatal-infos` clean, 148 `flutter test` pass, format clean (Flutter 3.47.9 run locally), no device/TalkBack run; admin screens are not part of the app (admin is API-only). Step 4 = admin partner verification API (`/api/v1/admin/partners`: queue, detail with history, decision; `kunde.admin` scope + per-request `PARTNER_VERIFICATION` grant, no personal data, self-review refused; end-to-end test apply → approve → publish → consumer sees it); step 3 = partner offerings API (`/partner/partners/{id}/offerings`: create/list/read/edit/publish/unpublish; publish only for APPROVED partners with a price; IDOR/role/limit tests; V14 offering audit); step 2 = `/api/v1/partner/applications`, `/partner/partners[/{id}]` (apply, list own, read, rename; membership re-checked per request, IDOR/revocation tests, V13 profile audit); also fixed public `GET /partners/{id}` being 401 under phone-auth. Step 1 (V12 `identity.admin_grants`, server-derived `kunde.partner`/`kunde.admin` token scopes, `RoleScopeIntegrationTest`; backend 222 tests pass locally on PostgreSQL 16). Next: Flutter partner/admin screens behind a flag. A DEV admin still has to be provisioned out of band (insert into `identity.admin_grants` by the owner; no endpoint creates grants); nothing is seeded, the public catalog stays empty until a real synthetic partner is approved and publishes.

- **Own phone-OTP authentication (2026-11-14, owner decision, merged in PR #80 `4a21db1`; ZITADEL draft PR #79 closed unmerged):** ADR-015 amended — no Keycloak/ZITADEL/external IdP; Spring Boot issues OTP-verified access JWT + rotating refresh tokens (`/api/v1/auth/otp/request|verify`, `/auth/token/refresh`, `/auth/logout`, Flyway V9, `OtpDeliveryProvider`). Off by default (`AUTH_PHONE_ENABLED`); DEV code `123456` only for allowlisted synthetic `+7700000XXXX` numbers in `KUNDE_ENVIRONMENT=dev|local|test` (startup aborts otherwise). No SMS/WhatsApp provider connected (D-11). Flutter phone/OTP screens behind `PHONE_AUTH_ENABLED`; profile/consents/addresses unchanged. Local: backend 200 tests pass on PostgreSQL 16, Flutter `analyze --fatal-infos` clean and 128 tests pass; no device run, nothing applied to Render/Neon (needs owner secret `AUTH_PHONE_SECRET` + approved Terraform apply). Production use gated (independent security review, OTP vendor, privacy/residency, key management). Docs: [phone-otp-auth](docs/identity/phone-otp-auth.md), [ADR-015](docs/architecture/adr/ADR-015-proposed-identity-provider.md).

- **DEV Android Release APK (2026-11-14, PR #77, `640add3`):** manual workflow `android-release.yml` builds a signed `flutter build apk --release` (arm64) against the Render API (`API_BASE_URL`, `API_TIMEOUT_SECONDS=90` for cold start). Signing only from GitHub secrets `ANDROID_KEYSTORE_BASE64/_PASSWORD`, `ANDROID_KEY_ALIAS/_PASSWORD` (owner-generated DEV key kept outside Git; no debug fallback). Run 43619187983 succeeded (analyze, test, signature/appId/INTERNET/non-debuggable/arm64/API-URL/no-secret checks; artifact `KUNDE-dev-release`, 14 days). Owner installed it on a Samsung phone; no functional phone checks reported yet. Before the phone-OTP PR this build had identity off (no IdP in DEV), so protected screens were unusable; applicationId is still `com.example.kunde_mobile`. Docs: [android-release-apk](docs/infrastructure/android-release-apk.md).

- **TASK-016 in_progress (merged: #81 `217f7a9`, #82 `7a7c243`, 2026-11-14):** Flyway V10 `marketplace.offerings.partner_id` (PUBLISHED requires a partner, DB check); consumer offering list/detail/search join APPROVED partners only and return `partnerId`/`partnerName`; public `GET /api/v1/partners/{id}` (APPROVED only, otherwise `404 PARTNER_NOT_FOUND`); Flutter search shows the partner name. Migrations seed no partners (test-guarded) — DEV catalog stays empty per ADR-014. Backend 203 tests pass on PostgreSQL 16 and required CI was green on both PRs. Missing: partner-scoped write/authorization API (needs partner-app audience and admin identity, D-14), price/availability (D-03/D-04, TASK-022/014), device checks. Linear synced 2026-11-14: ADA-79/80/87/97/107/114/116/122 moved Todo → In Progress to match the backlog (none are Done). Owner decision drafts: [D-03/D-04](docs/product/decision-drafts/P1-decisions-D-03-D-04-payments-commission.md).

- TASK-015 **in_progress**: partner persistence (Flyway V8 `marketplace.partners/partner_staff/*_events`, `PartnerService`): D-07 roles, partner isolation, revocation,
  append-only audit, verification gate (`mayProcessOrders` needs active staff + APPROVED). No HTTP API, documents/KYC or catalog link. Backend 164 tests pass locally against
  PostgreSQL 16 (155 existing + 9 new; temporary local cluster with synthetic credentials).

- **D-05/D-06/D-07 APPROVED (2026-11-13, Product Owner):** restaurant response 5 min / reminder 2 min / auto-timeout; free cancel before acceptance, no
  invented penalties or refunds; partner roles Owner/Manager/Operator + KUNDE Administrator with manual verification. Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md).
  TASK-021 blocked → in_progress (contract-only `OrderLifecycle`, 16 unit tests; no persistence/API/scheduler/payment link). TASK-027/028 stay blocked (D-03/D-04, D-14);
  D-03, D-04, D-08–D-15 unchanged. Backend: 88 non-DB tests pass locally; the 67 Spring/PostgreSQL tests were not run here (no DB credentials) and rely on CI.

- **D-02 APPROVED (2026-11-13, Product Owner):** phased hybrid fulfillment for Food Ordering (A pickup, B merchant delivery, C third-party logistics; no KUNDE courier
  fleet at start). Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md). TASK-019/029 moved blocked → in_progress (not Done); TASK-020/030 unchanged;
  D-03–D-15 unchanged. PR #63 (V7) added only the unpublished DRAFT `food-ordering` category.

- **D-01 PARTIALLY APPROVED (2026-11-13, Product Owner):** first category Food Ordering, first market Almaty. Cohort (8–12 restaurants), pilot zone and
  50–100 users are proposals only; D-02–D-15 unchanged. Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md). ADR-014 unchanged
  (catalog stays empty/non-orderable). Docs only; no task status changed. PR #61 (TASK-012) is merged with required CI green.

- **Home screen redesign (owner-approved visual reference, 2026-11-13):** Flutter `HomeScreen` is now the Super App home (header with Almaty chip, search,
  KUNDE AI card, 10-tile category grid, Food banner, quick actions, "Рядом с вами" empty state). Only Food is a first category and is active
  only when `marketplaceEnabled`; all other categories, AI, quick actions are explicit "Скоро"/disabled (no orders, no demo restaurants/ratings/times,
  no payments/delivery). Reference's 5-tab bottom bar (Главная/Поиск/Заказы/Избранное/Сервисы) differs from
  [docs/design/07](docs/design/07-consumer-app.md) — resolved by owner decision 2026-11-13: four tabs Главная/Поиск/Заказы/Профиль (DS-04), AI stays a Home block;
  Search/Orders/Profile show honest empty states without their capability; PRD-1.0 §navigation still says five (owner to update); no bell/profile
  icons (no backend); no photo assets (Material icons). Category grid is 5 columns from 360 px with muted "Скоро" tiles. `flutter analyze` clean, 113 `flutter test` pass locally; no device/TalkBack check.

- Merge reference at the time of this entry: `ab001ac18ec7dd98986aa77d67fb36f3970ed693` (PR #41); current main is in the audit section above.
- PRs #29–#37 (merged after #28), all with required CI green:
  #29 state/backlog sync; #30 TASK-055 domain schema ownership tests; #31 TASK-047
  correlation/log/Actuator tests; #32 TASK-053 secret-marker gate tests; #33 TASK-013
  Flyway V5 `marketplace.categories/offerings`; #34 owner standing merge permission
  (see AGENTS.md); #35 TASK-011 published-category search; #36 TASK-012 Flutter
  category search panel; #37 TASK-014 `GET /categories/{id}/offerings` (PUBLISHED
  only; no price, partner or availability).
- PRs #38–#41, all with required CI green: #38 state sync; #39 TASK-014 `GET /offerings/{id}`
  (404 `OFFERING_NOT_FOUND` unless PUBLISHED in a PUBLISHED category) and paginated offerings
  list (`limit`<=100, `offset`); #40 TASK-041 closed 27-event catalog and data-minimization
  validator (`EventCatalog`, contract only, nothing emitted or stored; see
  docs/engineering-foundation/event-taxonomy.md); #41 TASK-050 `KundeFormats.money`
  (integer minor units + ISO code, ru/kk/en; Flutter CI ran its tests, not a device).
- PRs #43–#46, all with required CI green: #43 TASK-010 explicit default-deny serviceability
  status in the address panel; #44/#45 backlog JSON fix and CI backlog validation; #46 TASK-008
  consent panel shows one row per policy in the reader's language (fallback order kk → ru → en,
  owner decision 2026-11-13) and states that policy text is not in the app yet. TASK-008 stays
  **in_progress** (needs approved policy text/link, TASK-007 legal wording, TalkBack/device checks).
- PRs #47–#49, required CI green: #47 state sync and Russian-language rule in AGENTS.md; #48 TASK-056
  local synthetic restore drill (`scripts/ci/restore_drill.sh`, not in CI, not production backup evidence);
  #49 TASK-048 draft incident runbook for existing signals (unapproved, no owners/SLOs). TASK-056 and
  TASK-048 are **in_progress**, not Done.
- TASK-015 **in_progress**: contract-only `PartnerVerification` state machine (draft PB-01/PB-02; no persistence, API,
  partner roles or catalog activation; ADR-014 unchanged). Backend unit tests only.
- TASK-037 **in_progress**: backend consumer support cases (Flyway V6, `/api/v1/me/support/cases`, idempotent create, owner-scoped reads,
  escalation request; see docs/engineering-foundation/api-contracts.md). No transaction link, staff side, SLA or notifications (D-11/D-12/D-14
  open); backend merged as PR #57 (`c70d783`).
- TASK-011/014 **in_progress**: `GET /api/v1/search/offerings` (published-only, ranked, paginated; public path added to security config; Backend 121 tests pass locally). Flutter search panel now shows published offerings too (77 `flutter test` pass locally; no device check).
- TASK-054 **in_progress**: backend concurrency/recovery tests for provisioning and support cases (found and fixed a support-case cap race);
  not the pilot E2E suite. Backend 119 tests pass locally (POC JWT test needs its own DB, not run).
- TASK-038 **in_progress**: Flutter `SupportPanel` on the profile screen (list/open/escalate, RU/KK/EN); `flutter analyze` and 73 `flutter test` pass locally; no device/TalkBack run. Backend 115 tests pass locally against PostgreSQL 16 (POC JWT test needs its own DB, not run).
- TASK-031 **in_progress**: contract-only `NotificationPolicy`/`Delivery` (PRD 1.1 §14); no provider (D-11), outbox,
  persistence or sending. Backend unit tests only.
- Catalog tasks TASK-011/012/013/014 remain **in_progress**: no seed data, offering search,
  price, partner link, serviceability or availability rules; ADR-014 (no default orderable
  catalog, `marketplaceEnabled=false`) still applies. TASK-041 and TASK-050 are also
  **in_progress**, not Done: analytics has no consent/residency/outbox/KPI approval and
  localization has pure plural/date/time helpers (unapproved layout) but lacks time-zone conversion, address/phone formats and approved critical copy (TASK-049).
- Earlier snapshot, retained as history: PR #25 (`af61a2e`).
- PR #23 / ADA-73: protected Consumer consent API, Flyway V4 ledger,
  approval-only policies, owner-scoped immutable grant/withdrawal history,
  active-user row lock; merged as `6d098c5`. Backend/Security/config CI green.
- PR #24 / ADA-74: Flutter authenticated consent management with RU/KK/EN,
  confirmation, fail-closed session behavior and tests; merged as `f85c7e0`.
  Flutter/Security/config CI green.
- PR #25 / ADA-76: Flutter saved addresses, manual WGS84 input,
  optimistic delete conflict handling, honest serviceability state and tests;
  merged as `af61a2e`. Flutter/Security/config CI green.
- Linear ADA-73, ADA-74 and ADA-76 remain **In Progress** where acceptance
  remains incomplete: legal/privacy policy approval, consent withdrawal effects,
  policy presentation, native accessibility, real zone/map UX and device checks.
  Do not infer Done from merged PRs.
- Next critical verification is ADA-72 / TASK-006: **native** refresh replay,
  provider outage/recovery, expiry, iOS, TalkBack/large text, physical devices
  and account session administration. Protocol and unit tests are not native proof.
- GHSA-r937 remains unresolved; no scanner suppression or production sign-off.
- The paragraphs below are retained as historical evidence and must not be read
  as the current main commit or current test count.

- PR #27 (ADA-72) is merged (`b91cad0`): provider network outage/recovery probe only.
- PR #28 (ADA-72) is merged (`5de3184`, 2026-11-12) and extends the Android35/Chrome124/AppAuth/Keycloak native harness.
  Hosted run 43270980722 (source `5159ae7`) passed with 17 completed checks, adding:
  provider outage **during refresh** with recovery, rotated refresh-token **replay**
  rejected natively (session cleared), same-canonical-account relogin, expired access
  token refreshed natively (real 310 s wait; no clock manipulation) and no JWT material in
  device log or plaintext vault file. Sanitized artifact `identity-e2e-sanitized` is retained.
  Required CI (configuration, dependencies, containers, secrets) passed; CodeRabbit did not
  review (manual trigger only) and the merge was owner-approved. TASK-006 stays in_progress; NOT_EXECUTED: iOS, TalkBack, large text, full RU/KK journeys, physical devices,
  account session administration (API returns 503). GHSA-r937 remains open.
- Linear ADA-72/ADA-73 were found in Done and returned to In Progress on 2026-11-12.

## Historical engineering notes

Reviewed 2026-11-12. Follow AGENTS.md; code and current CI are authoritative.

- ADA-72 PR #17 merged as afdab129 (2026-11-12). Hosted Android native E2E
  run 43219354337 succeeded with prerequisites and emulator jobs; the registration
  harness extends six prior checks to eleven. Sanitized CI artifact is retained.
  TASK-006 remains in_progress: replay, outage/expiry, iOS, accessibility,
  physical-device and session-administration evidence are still missing.

- Owner requested essential automatic CI: configuration, scoped backend/Flutter,
  and dependency/secret/container security checks. APK, SDK tooling and diagnostic
  workflows are manual; their evidence/DoD requirements remain. See
  docs/engineering-foundation/github-hosted-ci.md. GHSA-r937 remains OPEN.

- Main 51374d1 includes PRs #11–#13: bounded peer-IP admission and request body
  guard before JWT/controllers, followed by verified `(issuer, subject)` quotas.
  Backend 68/Flutter 33 checks pass; SDK GHSA-r937 remains open.
- TASK-006 PR #14 verifies six targeted native checks on source db13a26:
  Android35/Chrome124.0.6367.219 system-browser login/PKCE callback, profile edit,
  two vault/rotated-refresh restores, API offline retry, provider logout/relogin,
  plus welcome RU/KK/EN. Hosted run 43209945677 succeeds; sanitized report is
  retained in docs/identity/consumer-validation/native-evidence-2026-11-12.json.
  Fourteen local Python tests and separate Cloud Chromium S256/API checks pass.
- TASK-045 is partially_verified after a documented technical threat/default review;
  formal privacy/production threat, operations and audit coverage gates remain open.
  TASK-046 and TASK-006 stay in_progress. All 56 canonical TASK IDs are preserved.
- Stack: Java 21 / Spring Boot 4.0.9, PostgreSQL/Flyway V1–V2, Flutter 3.47.9.
- ADR-015 accepts Keycloak primary/ZITADEL fallback for synthetic development.
  Production privacy/residency, legal, OTP, operations and recovery gates remain open.
- Consumer identity owns canonical UUID/issuer-subject binding, lifecycle checks and
  optimistic profile updates. The new quota does not link IdP aliases or replace
  business authorization. Flutter has real AppAuth/PKCE/secure-vault flows; account
  session administration is still 503. PR #5's provider protocol fixture is not native
  Consumer browser/vault/accessibility proof.
- SDK GHSA-r937 remains open (two MODERATE matches in observed tooling graphs).
  Owner permitted merges #11 and #12 with this known finding; no production approval
  or scanner suppression follows. Trusted device, canonical-account-wide and
  distributed-edge/read-timeout/concurrency controls still need their contracts.
- Native scenario prerequisites now exist on PR #14. The manual gate requires six
  executed checks and keeps all remaining native/device/accessibility gaps explicit.
  TASK-006 remains the next controlled verification task. See NEXT_TASK.md,
  [security evidence](docs/security/TASK-046.md),
  [technical baseline](docs/engineering-foundation/authentication-and-security.md),
  [Consumer fixture](docs/identity/consumer-validation/README.md).
