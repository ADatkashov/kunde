# Microservice readiness (аудит фактического кода)

Дата аудита: 2026-11-23, `main` @ `614033a`. Основание — исходный код `backend/` (175 Java-файлов, 62 миграции Flyway, 133 таблицы), а не ADR.
Решение остаётся прежним: **единый Spring Boot backend + PostgreSQL** ([ADR-001](adr/ADR-001-backend-architecture-style.md), [29-service-extraction-roadmap](29-service-extraction-roadmap.md)). Этот документ ничего не переводит на микросервисы, а фиксирует, где границы уже чистые, где нет, и как не дать связности вырасти.

Как воспроизвести цифры: `cd backend && mvn test -Dtest=ArchitectureBoundariesTest`; полный список связей — [`cross-module-baseline.txt`](../../backend/src/test/resources/architecture/cross-module-baseline.txt); владельцы таблиц — [`table-owners.txt`](../../backend/src/test/resources/architecture/table-owners.txt).

## 1. Текущая фактическая архитектура

- Один деплой `kunde-api`, плоские пакеты `kz.kunde.<module>` (подпакетов нет): `auth, identity, partner, admin, catalog, platform, config, auto, booking, health, food, groceries, delivery, rides, maps, leisure, events, education, support, fulfillment, order, notification, analytics`.
- Одна БД PostgreSQL, шесть схем (`identity, profile, marketplace, transactions, payments, support`; плюс `serviceability`). **Схемы разделены по типу данных, а не по домену**: таблицы food, rides, leisure лежат в одних и тех же `marketplace`/`transactions`. Владелец таблицы определяется только префиксом имени (реестр `table-owners.txt`).
- Доступ к данным — `JdbcTemplate` с SQL-строками прямо в контроллерах и сервисах; ORM и репозиторного слоя нет. Поэтому «чужая таблица» = «чужой SQL».
- Событий и outbox **нет**: `notification` и `analytics` — контракты без хранения и отправки (`Delivery`, `EventCatalog`); единственный фоновый код — два `@Scheduled` в `delivery/DeliveryMaintenance`. Модули общаются прямыми вызовами Java и общими таблицами. ~280 `@Transactional`; транзакции открывает владелец данных, но вызовы между модулями (например `groceries → FoodOrderService`) выполняются в одном процессе и одной БД-транзакции, поэтому при выделении станут распределёнными — это учтено в п.8.
- Feature flags: свойства окружения (`FOOD_ENABLED`, `RIDES_*`, `DELIVERY_*`, `MAPS_ENABLED` …) плюс runtime-переключатели `identity.feature_toggles` (`platform/FeatureToggles`) для девяти продуктов.
- Maps — уже **отдельный сервис** (репозиторий `kunde-maps`, ADR-020): в backend только HTTP-адаптер `maps/KundeMapsRideRouting` к порту `rides/RideRouting`.

## 2. Граф зависимостей (импорты между модулями, без `platform`/`identity`/`config`)

```text
admin ──► partner(11) food(2) leisure(2) delivery(1)
auto ──► booking(3)         health ──► booking, admin, partner
booking ──► partner(2)      groceries ──► food(1)
delivery ◄──► rides         (delivery→rides 8, rides→delivery 1)  ← цикл
delivery ──► admin, partner   rides ──► admin(2), partner
education ──► admin(2), partner(2)   food ──► partner(2)
events ──► leisure(2)       leisure ──► partner(4), auth(1)
maps ──► rides(3)  (адаптер порта RideRouting; направление верное)
support ──► delivery, rides
platform ──► auto, booking, delivery, education, events, groceries, health, leisure, rides (9)  ← инверсия
```

Числа — количество импортирующих файлов/типов в baseline. `platform` и `identity` тест считает общим ядром (все могут импортировать), поэтому обратное направление `platform → домены` отслеживается отдельным правилом.

## 3. Нарушения границ (доказанные, с местом и минимальным исправлением)

Исчерпывающий список (файл → цель) — в baseline; ниже — значимые группы. Номера строк не фиксируем (они плавают), ищутся по имени файла и таблице.

| # | Нарушение | Где | Почему плохо | Минимальное исправление | Статус |
|---|---|---|---|---|---|
| V1 | `platform` импортирует настройки 9 доменов | `platform/FeatureToggles.java` (импорты `*Properties/*Settings/*Flags`) | Ядро зависит от всех продуктов: любой домен нельзя вынести без `platform` + остальных восьми | Интерфейс `FeatureGate { Feature feature(); boolean allowedByEnvironment(); }` в `platform`, каждый домен реализует его своим bean-ом; `FeatureToggles` получает `List<FeatureGate>`. Публичные методы и JSON не меняются | **Предложение** (затрагивает конструктор, используемый тестами и 9 доменов) |
| V2 | Цикл `delivery ↔ rides`; Delivery берёт DTO у контроллера Rides | `delivery/DeliveryController, DeliveryExecutorController, DeliveryService, DeliveryCouriers, DeliveryTracking` → `rides.RideRoutingController.Coordinates`; `DeliveryDispatch` → `rides.RideMatching`; обратно `rides/RideDispatchService` → `delivery.DeliveryDispatch.ACTIVE_DELIVERY_STATES` и SQL к `transactions.deliveries`; `delivery/DeliveryDispatch` SQL к `transactions.rides` | Оба модуля нельзя разнести: каждый компилируется только вместе с другим; типы живут во внутреннем DTO контроллера | Вынести `Coordinates`/`Point` и порт `RideRouting` в нейтральный пакет (`platform.geo`), «занятость водителя» — через маленький интерфейс `ExecutorBusyness` в `platform`, реализуемый обоими модулями | **Предложение** (меняет FQCN, затрагивает Maps-адаптер и тесты; без изменения JSON) |
| V3 | Прямые SQL-записи в `support.cases`/`case_events` из delivery и rides | `delivery/DeliveryOperations`, `rides/RideOperationsService` | Support — владелец таблиц, но два других домена пишут в них своим SQL | Интерфейс `SupportCases` (создать/добавить событие) в Support, домены вызывают его | **Предложение** |
| V4 | `support` вызывает сервисы `rides` и `delivery` | `support/SupportCaseService` → `RideRequestService`, `DeliveryService` | Support зависит от двух доменов, дальше цикл по V3 | Интерфейс `CaseSubject` (проверка владения заказом) на стороне доменов | **Предложение** |
| V5 | `auto` работает напрямую с таблицами `booking` | `auto/AutoService, AutoPayments, AutoFeedbackService, AutoCatalogController` → `marketplace.booking_services/masters/venues`, `transactions.bookings/booking_events` (≈32 ссылки); обратное: `booking/BookingService` → `transactions.auto_payments`, `BookingPartnerService` → `auto_service_categories` | Auto по факту — вертикаль Booking на общих таблицах; отдельно их не разделить | Принять как один сервис «booking+auto+health» (см. п.5); убрать только обратные ссылки `booking → auto/health` через интерфейс категорий | Принято как ограничение, обратные ссылки — **предложение** |
| V6 | `health` — тонкая вертикаль Booking | `health/HealthAdminController, HealthDemoSeeder` → `booking_venues`, `bookings`; `booking/HealthFavoritesController`, `BookingCatalogController` → `health_categories/health_favorites` | То же | То же: один сервис | Принято |
| V7 | `groceries` — вертикаль Food на чужих таблицах | `groceries/GroceriesAccountController, GroceriesCatalogController` (≈31 ссылка на `food_*`), `GroceriesAccountController` → `food.FoodOrderService` | Нет собственного хранилища продуктов/заказов | Принять как часть сервиса Food | Принято |
| V8 | `events` построен на `leisure` | `events/EventsCatalogController, SearchRouteController` → `LeisureCatalogService` | V56 разделил продукты, но код общий | Принять как один сервис «leisure+events» | Принято |
| V9 | Организации партнёров читаются чужим SQL | `education`, `rides`, `leisure`, `food`, `catalog`, `auth` → `marketplace.partners / partner_staff` (≈20 ссылок) | `partner` — общее ядро B2B, но доступ не через контракт | Единый интерфейс `PartnerDirectory` (`staffRole(user, partner)`, `partnerName`) в `partner`; домены вместо SQL | **Предложение** (низкий риск, но много точек) |
| V10 | Пользователи читаются чужим SQL | `delivery/DeliveryDispatch`, `rides/RideDispatchService, RideFleetService`, `education/*`, `partner/PartnerService` → `identity.users`, `profile.consumer_profiles` | Ядро идентичности — общее | Допустимо до выделения Identity; затем — `UserDirectory` | Принято (общее ядро) |
| V11 | Admin читает и пишет данные 9 доменов своим SQL | `admin/Admin*Controller` (≈40 ссылок на `food_*`, `leisure_*`, `auto_*`, `booking_*`) и импорты сервисов доменов | Админ — единое окно, но не через контракты доменов | Админ-API каждого домена в самом домене (частично уже так: `HealthAdminController`, `RideAdminController`, `DeliveryAdminController`) | Тенденция верная, остальное — по мере выделения |
| V12 | Общие DTO-типы в контроллере | `RideRoutingController.Coordinates`, `PartnerService.Role/PartnerView`, `AdminGrants` в `admin` используется 5 доменами | Пакет `admin` стал ядром прав | Вынести `AdminGrants` в `platform.authz` (переименование пакета, без изменения таблицы) | **Предложение** |

Что **не** нарушено (проверено): Flyway-миграции создают таблицы только в известных схемах; межсхемные FK — это ссылки на `identity.users`/`marketplace.partners` и внутри одной вертикали (проверяет существующий `DomainSchemaOwnershipIntegrationTest`); истории не каскадируются; внешних вызовов между доменами по HTTP нет; публичные API не зависят от внутренних пакетов (путь `/api/v1/...` определяют контроллеры, `OpenApiController` — отдельный контракт).

## 4. Владельцы данных

Реестр префиксов → модуль: `backend/src/test/resources/architecture/table-owners.txt` (тест падает на таблице без владельца). Кратко:

| Модуль | Таблицы |
|---|---|
| identity | `identity.users`, `external_bindings`, `account_events`, `profile.*`, `serviceability.*` |
| auth | `identity.otp_challenges`, `auth_sessions`, `refresh_tokens`, `phone_identities`, `auth_events` |
| platform / admin | `identity.feature_toggle*` / `identity.admin_*` (грант-модель) |
| partner, catalog | `marketplace.partners, partner_staff, partner_*_events` / `offerings, categories` |
| food (+groceries) | `food_*`, `grocery_*`, `transactions.food_*` |
| booking (+health, auto) | `booking_*`, `home_service_*`, `bookings`; `health_*`; `auto_*`, `customer_vehicles` |
| rides / delivery | `ride_*`, `rides` / `deliver*` |
| leisure (+events) | `leisure_*` |
| education | `education_*` |
| support | `support.cases`, `case_events` |

Замечание: схемы `payments` создана, но таблиц нет; платежи — DEV-заглушки внутри доменов (`auto_payments`, `leisure_payments`, `education_payment_events`), отдельного Payments-домена в коде **нет**.

## 5. Рекомендуемые границы будущих сервисов

Границы выбраны по реальным связям (общим таблицам), а не по названиям пакетов:

1. **Maps** — уже отдельный (kunde-maps). Backend знает только порт `RideRouting`.
2. **Mobility = rides + delivery (+ maps adapter)** — после устранения V2; общий dispatch/геопозиции.
3. **Food + Groceries** — общие таблицы `food_*`; один сервис.
4. **Booking + Health + Auto + Home services** — общие `booking_*`/`bookings`; один сервис.
5. **Leisure + Events** — общий каталог и билеты.
6. **Education** — самый самостоятельный по данным (`education_*`), зависит только от `partner`, `identity`, `admin`-грантов.
7. **Ядро (остаётся в монолите)**: identity+auth, partner+catalog, admin+platform (гранты, toggles), support.
8. **Notifications / Payments / Analytics** — сейчас в коде отсутствуют (контракты без реализации); выделять нечего, это новые компоненты после решения владельца (ADR-006/010).

## 6. Порядок безопасного выделения

Готовность (по фактическим связям из baseline):

| Домен | Зависимости (код) | Владение данными | Связность | Готовность | Что нужно |
|---|---|---|---|---|---|
| Maps | порт `RideRouting` | своих таблиц нет, свой репозиторий | низкая | **Выделен** | — |
| Education | partner, admin-гранты, identity | `education_*` свои | низкая (≈11 SQL к partner/identity) | **Высокая** | V9, V12 (`PartnerDirectory`, `AdminGrants` в ядро) |
| Leisure+Events | partner, auth(1) | `leisure_*` свои; admin пишет туда (≈30) | средняя | Средняя | V9, перенос админ-SQL в домен, убрать `leisure → auth` (`phone_identities`) |
| Food+Groceries | partner, identity, delivery(1) | свои; admin читает (≈15) | средняя (groceries целиком на food) | Средняя | V9, `food → delivery_couriers` через интерфейс, админ-SQL в домен |
| Booking+Health+Auto | partner, admin | общие таблицы между тремя | высокая внутри, средняя наружу | Средняя/низкая | V5 обратные ссылки, V9 |
| Rides+Delivery | partner, admin, support, identity | свои, но перекрёстные SQL (`rides`↔`deliveries`) | **высокая (цикл)** | Низкая | V2, V3, V4 обязательны |
| Support | rides, delivery | `support.*`, в них пишут другие | высокая | Низкая | V3, V4 |
| Partner/Catalog/Identity/Auth/Admin/Platform | — | ядро | — | Остаются в монолите | V1, V12 |

Порядок: **(0)** держать baseline (сделано) → **(1)** V9/V12/V1 — общие контракты ядра, самые массовые и безопасные → **(2)** Education как пробный первый сервис (теневое чтение, см. п.8) → **(3)** V2+V3+V4, затем Mobility → **(4)** Food, Leisure → **(5)** Booking-кластер последним.

## 7. Когда разделение действительно необходимо

Делить только при измеримом основании ([29-service-extraction-roadmap](29-service-extraction-roadmap.md)): (а) независимое масштабирование/ресурсы (например GPS-поток Mobility вытесняет API Food на одной JVM/БД; p95 > SLO при нагрузке одного домена); (б) отдельная команда с собственным релизным циклом; (в) регуляторная/безопасностная граница (платёжные данные, мед-данные Health); (г) изоляция отказов (падение Delivery не должно ронять заказы). «Архитектурная эстетика» и число пакетов — не основание. Пока ни одного из условий нет: пилотный DEV, один backend-сервис, одна команда.

## 8. План миграции без остановки системы

Для каждого кандидата (повторяемый шаблон):

1. **Контракт в процессе**: домен получает интерфейс (`PartnerDirectory`, `SupportCases`…), потребители переходят с SQL/импортов на него; baseline сокращается. Внешний API не меняется.
2. **Изоляция данных**: таблицы домена остаются в той же БД; все остальные коды обращаются только через контракт; добавить FK-аудит (существующий `DomainSchemaOwnershipIntegrationTest`).
3. **Outbox/inbox** (появляется впервые, отдельное решение владельца по ADR-006) для событий, которые раньше были прямым вызовом; идемпотентность и DLQ.
4. **Деплой второго экземпляра** того же артефакта с включённым только нужным модулем (feature flags уже есть), трафик по маршруту через gateway/Render service — **без** смены кода; чтение с теневой сверкой.
5. **Один писатель**: переключение записи по флагу домена; чтение продолжает работать из общей БД.
6. **Разделение БД** (если нужно) — последним, через логическую репликацию таблиц модуля; старые таблицы сохраняются до конца окна отката.

Ничего из этого не выполняется сейчас; `terraform apply`, PROD, новые инфраструктурные сервисы вне задачи.

## 9. Стратегия отката

- Каждый шаг п.8 за флагом (`<DOMAIN>_ENABLED` / runtime-toggle) — откат = переключить флаг и маршрут обратно на монолит.
- До шага 6 данные остаются в общей БД, откат трафика не требует миграции данных.
- Миграции Flyway только вперёд и обратно совместимые (expand → migrate → contract); таблицы старой схемы удаляются отдельным релизом после окна наблюдения.
- Контракты и baseline версионируются в git; откат кода = откат PR.

## 10. Что можно оставить общим без риска

- Общая БД PostgreSQL на ранних стадиях (с запретом чужого SQL по baseline).
- Ядро: `platform` (ошибки, rate limit, correlation), `identity`/`auth` (JWT, пользователи), `partner`/`catalog`, `admin` (гранты), `fulfillment`/`order` (чистые политики без хранилища).
- Один артефакт сборки и один Flyway-набор миграций, одна CI-конвейерная цепочка.
- Общие токены/поставщик идентичности (ADR-013/015) — они и должны быть общими.

## Автоматическая защита (что внедрено)

`backend/src/test/java/kz/kunde/architecture/ArchitectureBoundariesTest.java` — быстрый тест без БД и Spring, шаг `Architecture boundaries (fast, no database)` в `.github/workflows/backend.yml` запускается до полной сборки:

- новая межмодульная связь (**IMPORT** класса другого модуля или **SQL** к чужой таблице) — падение с подсказкой;
- устранённая связь, оставшаяся в baseline, — тоже падение (долг только уменьшается);
- новая таблица без владельца в `table-owners.txt` — падение;
- `platform` не может обрастать новыми зависимостями от доменов (кроме замороженного `FeatureToggles`, V1).

Как осознанно добавить связь: строка в `cross-module-baseline.txt` в том же PR с обоснованием. Пересоздать baseline: `mvn test -Dtest=ArchitectureBoundariesTest -Dkunde.architecture.updateBaseline=true` (проверить diff вручную).
