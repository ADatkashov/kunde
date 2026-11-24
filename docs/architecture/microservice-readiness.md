# Microservice readiness (аудит фактического кода)

Дата аудита: 2026-11-24, `main` @ `cab484f` (после ADR-023/ADR-024). Основание — исходный код `backend/` (Gradle: `platform`, `app`, 17 модулей `services/*`; 68 миграций Flyway, 142 таблицы), а не документация. Заменяет аудит от 2026-11-23 (`@ 614033a`): часть его нарушений (V1–V4, V9 частично, V12) закрыта, список ниже актуален.

Решение прежнее: **единый Spring Boot backend + PostgreSQL** ([ADR-001](adr/ADR-001-backend-architecture-style.md), [Конституция §3.2](CONSTITUTION.md)). Документ ничего не переводит на микросервисы: он фиксирует, где границы уже честные, где нет, и в каком порядке и по какому критерию их можно будет применить ([ADR-025](adr/ADR-025-gradual-service-extraction.md)).

Связанные документы (не дублируются здесь): [domain-registry](domain-registry.md) · [domain-dependency-matrix](domain-dependency-matrix.md) · [database-ownership-matrix](database-ownership-matrix.md) · [domain-readiness-scores](domain-readiness-scores.md) · [event-catalog](event-catalog.md) · [fitness-functions](fitness-functions.md) · [29 roadmap](29-service-extraction-roadmap.md) · [30 риски](30-architecture-risks.md) · [диаграмма компонентов](diagrams/14-domain-components.md) · [database-sharding-readiness](database-sharding-readiness.md).

Воспроизвести цифры: `cd backend && ./gradlew :app:test --tests 'kz.kunde.architecture.*'`; таблицы — `python3 scripts/dev/architecture_matrix.py {matrix|ownership|readiness}`.

## 1. Фактическое состояние

- Один деплой `kunde-api` (`:app` собирает `platform` + 17 библиотечных модулей). Зависимости Gradle: `platform` не зависит ни от кого; `services/*` → `platform` (+ `identity`, `partners`, `booking`, `food`, `leisure` по записанным рёбрам); циклов между Gradle-модулями нет (тест `gradleModuleGraphIsLayeredAndAcyclic`).
- Одна БД, 142 таблицы, 18 владельцев ([матрица](database-ownership-matrix.md)). Доступ — `JdbcTemplate` с SQL в контроллерах и сервисах, ORM и репозиториев нет; поэтому «чужая таблица» = «чужой SQL».
- Связи между пакетами: 42 импорта и 102 SQL в baseline (144), плюс 36 намеренных рёбер «вертикаль → Booking». Из них 20 рёбер лежат на циклах и образуют **один узел из 10 пакетов** ([матрица зависимостей](domain-dependency-matrix.md)).
- 123 внешних ключа между таблицами **разных владельцев** (79 из них на `identity.users`): физическое разделение БД невозможно без их замены.
- События: инфраструктура есть ([ADR-022](adr/ADR-022-transactional-outbox.md): `platform.outbox_events/inbox_events`, `OutboxWriter` с `MANDATORY`, `OutboxRelay` с `SKIP LOCKED`, порядок по агрегату, DLQ-статус `DEAD`, версия схемы, метрики `kunde.outbox.*`), relay выключен, **ни один домен не публикует события**; средства разбора мёртвых писем и retention не построены.
- Идемпотентность HTTP — по ключу в таблицах 8 доменов (auto, booking, delivery, education, food, leisure, rides, support).
- Кэширования нет (`@Cacheable`/Redis отсутствуют) — и это правильно на текущей нагрузке.
- Наблюдаемость: Actuator, `X-Correlation-ID` → MDC (`RequestCorrelationFilter`), метрики outbox. Распределённой трассировки нет; корреляция не передаётся в исходящие HTTP (только `maps`).
- Единственный внешний сервис — KUNDE Maps (отдельный репозиторий, порт `RideRouting`, ADR-020).

## 2. Паспорта доменов

Колонки: **Назначение · Владелец данных (таблицы) · Публичный контракт · Входящие / исходящие зависимости · Взаимодействия · Выделяемость**. Количества — из матриц; подробные оценки и блокеры — [domain-readiness-scores](domain-readiness-scores.md).

| Домен (пакет → модуль) | Назначение | Данные | Публичный контракт | Входящие / исходящие | Sync / async | Выделяемость |
|---|---|---|---|---|---|---|
| identity, auth (`services/identity`) | Профиль, адреса, согласия; вход по телефону, JWT | 15 (`identity.users`, `profile.*`, `serviceability.*`, `auth_*`) | HTTP `/me`, `/auth`; ядро для всех | Входящих: все (79 FK); исходящие: `auth → partner_staff` (роль в токене) | sync | Последним; остаётся в монолите |
| partners, catalog (`services/partners`) | Организации, персонал, каталог | 9 | `PartnerDirectory` (platform, ADR-021), `PartnerAccessPolicy` | Входящих 18 SQL; исходящие — демо-сид (`food`, `booking`, `auth`) | sync | Ядро; сначала убрать обратные рёбра |
| admin (`services/admin`) | Единое окно оператора, права (`identity.admin_*`) | 4 | `AdminGrants` (platform.authz) | Исходящие: 44 SQL + 9 импортов в 8 доменов | sync | Не выделяется; см. §4 |
| support | Обращения, события обращений | 2 | `SupportCaseDirectory`, `CaseSubjectOwnership` (platform) | Исходящих нет; FK на `deliveries/rides` | sync | Хорошая |
| food (`services/food`) | Еда: рестораны, заказы, самовывоз, курьер | 16 | HTTP `/food`, `FoodPromotionService`, `FoodOrderService` | Входящих 26 SQL (groceries 11, admin 14); исходящие: `grocery_categories`, `delivery_couriers` | sync | С Groceries как «food family» |
| groceries | Продукты на таблицах Food | 6 | HTTP `/groceries` | Исходящих 11 SQL в `food_*` | sync | Только с food |
| delivery | Доставка: курьеры, диспетчеризация | 9 | `ActiveWork`, HTTP `/deliveries` | `delivery ↔ rides` по SQL | sync + `@Scheduled` | В «mobility» с rides |
| rides | Такси: заказы, водители, парк | 10 | `RideRouting` (порт), `ActiveWork` | Исходящие: `deliveries`, партнёры | sync | С delivery (пока цикл) |
| maps (`services/maps`) | Адаптер к внешнему KUNDE Maps | 0 | `RideRouting`-реализация | Исходящих HTTP 1 | sync (HTTP) | **Выделен** |
| booking (`services/booking`) | Движок записи (слоты, брони) | 8 | `BookingCategory`, `BookingSlots`, `BookingService`, `BookingPayments` | Входящих 30 SQL; FK 19 внутрь; исходящие: `auto_*`, `health_categories` | sync | Семьёй (booking+beauty+homeservices+health+auto) |
| beauty, homeservices, health, auto | Вертикали Booking | 6 / 3 / 3 / 14 | HTTP по продуктам | `→ booking` (намеренно); `booking → auto/health` (обратно) | sync | Только с движком |
| leisure, events | Досуг, билеты; события поверх досуга | 19 / 0 | HTTP | `admin → leisure` 11 SQL; `leisure → auth/partner` | sync | Хорошая, после переноса админ-SQL |
| education | Курсы, записи, сертификаты | 14 | HTTP `/education` | Входящих 0; исходящие — ядро | sync | **Лучшая** (первый кандидат) |
| platform (`backend/platform`) | Техническое ядро: ошибки, rate limit, correlation, events, geo, placement, feature toggles | 4 | всё перечисленное | Бизнес-импортов нет | — | Остаётся |

## 3. Значимые нарушения (состояние на 2026-11-24)

| # | Нарушение | Где | Статус | Следующий шаг |
|---|---|---|---|---|
| V1 | `platform` импортировал настройки доменов | — | **Закрыто** (PR #260) | — |
| V2 | Цикл `delivery ↔ rides` по импортам | — | **Закрыто по импортам** (#253); остаётся по SQL (`delivery → rides`, `rides → deliveries`) | порт «доступность исполнителя» в `platform.dispatch` |
| V3/V4 | Support пишет/читает чужие домены | — | **Закрыто** (#254, #255) | убрать FK `support → deliveries/rides` |
| V5 | `booking → auto/health` по SQL | `BookingService`, `BookingCatalogController` | Открыто (4 SQL) | расширить `BookingCategory` данными категории |
| V7 | `groceries` целиком на `food_*` | `GroceriesAccountController`, `GroceriesCatalogController` | Принято: одна «food family»; открыто для продуктовых данных | собственные таблицы Groceries — только по решению владельца |
| V9 | Партнёры читаются чужим SQL | education, rides, leisure, food, auth | Частично (`PartnerDirectory`, #256); остаток — 18 SQL | перевести потребителей на `PartnerDirectory` по одному домену за PR |
| V11 | Admin читает/пишет данные 8 доменов | `Admin*Controller` | **Открыто, главная проблема** | §4 |
| **V13** | **Демо-сиды — SQL в чужие таблицы из продуктовых модулей** | `PartnerOpsDemoSeeder`, `LeisureDemoSeeder` | **Новое, открыто** | перенос сидов в `backend/app` (разрывает узел циклов вокруг `partner`); чинить отдельным PR с интеграционными тестами (нужен PostgreSQL) |
| **V14** | **123 FK между владельцами** | миграции V1–V68 | **Новое, зафиксировано** (`noNewCrossOwnerForeignKeys`) | политика: новые таблицы не ссылаются FK на чужую таблицу, кроме `identity.users`/`partners`/`cities` (ядро) |
| **V15** | **Нет корреляции и трассировки между модулями/сервисами** | `RequestCorrelationFilter` кладёт id в MDC, исходящие HTTP его не передают; контекст outbox — `correlation_id` в envelope | Открыто | §6, шаг 3 |
| V16 | `OutboxRelay` без инструмента разбора DLQ и retention | `platform.events` | Открыто (описано в ADR-022) | операторская команда повторной отправки + job очистки до первого продюсера |

## 4. Admin: как не связать все домены

Сейчас Admin — единственный модуль с исходящими зависимостями почти от всех бизнес-доменов: `admin → food` (14 SQL + 2 импорта), `leisure` (11 + 3), `auto` (4 + 3), `booking` (4), `beauty` (2), `homeservices` (2), `groceries` (1), `delivery` (1 импорт), плюс ядро. Это 44 из 102 SQL-связей baseline. При выделении любого из этих доменов Admin сломался бы по SQL, а не по контракту.

Рекомендация (в духе «без моды»), по возрастанию стоимости:

1. **Админ-контракт внутри домена (делать сейчас, малыми PR).** Каждый домен публикует в своём модуле узкий интерфейс `<Domain>AdminApi` (`list`, `moderate`, `complaints`, `summary`) со своими DTO; SQL переезжает из `Admin*Controller` в домен; контроллер Admin остаётся тонкой маршрутизацией и проверкой `AdminGrants`. Направление зависимости `admin → domain` остаётся (Конституция допускает), но по контракту, а не по таблицам; каждый перенос уменьшает baseline. Начать с `leisure` и `food` (25 из 44), HTTP-контракты не меняются.
2. **Права остаются общими.** `AdminGrants` уже в `platform.authz`; новые домены не добавляют собственных таблиц прав в Admin.
3. **Read model / CQRS — только там, где оправдано.** Сводки, сквозные дашборды и поиск по нескольким доменам (например, обзор оператора) — единственный случай, где проекция в `admin` из событий окупается: она убирает N синхронных запросов к N доменам. CRUD и модерация проекций **не** требуют. Проекции появятся не раньше, чем домены начнут публиковать события (§6, шаг 2), и только для конкретного экрана с измеренной проблемой.
4. **При выделении домена** реализация `<Domain>AdminApi` подменяется удалённым адаптером без правки Admin.

## 5. Сквозной аудит

| Область | Факт (проверено) | Риск | Действие |
|---|---|---|---|
| Транзакции | `@Transactional` в 52 классах 14 модулей; транзакция одного HTTP-запроса может охватывать SQL нескольких доменов (например, `groceries → food_orders`) | При выделении граница транзакции превращается в сагу/согласованность в конечном счёте | `PartnerDirectory.lock…` уже документирует замену; для остальных — описывать при выделении (ADR-025) |
| Domain events / outbox | Инфраструктура готова, продюсеров нет, relay выключен | Первый продюсер — финансовый поток, нужна отдельная проверка корректности (ADR-022) | Первый продюсер — нефинансовый (§6 / [event-catalog](event-catalog.md)) |
| API-контракты | Маршруты — публичный контракт (Конституция §8); OpenAPI в `platform.OpenApiController`; контрактных тестов потребитель↔поставщик нет | Изменение DTO ломает установленные APK | Контрактный тест: снимок OpenAPI + проверка совместимости (§ fitness, TARGET) |
| Identity/RBAC | Fail-closed JWT/OIDC, роли `kunde.partner/executor/admin`, гранты `admin_*`; Admin App — не граница безопасности | — | Без изменений |
| Кэширование | Нет | Нет | Не добавлять до измеренного триггера |
| Observability | Actuator, correlation в MDC, метрики outbox | Нет trace id между сервисами | OpenTelemetry — **только** при первом вынесенном сервисе (ADR-025), до этого `correlation_id` в envelope |
| Масштабирование | Состояние не в памяти процесса (Конституция §7), `SKIP LOCKED`, placement registry | Одна БД и одна JVM | Горизонтальные копии монолита — первый шаг масштабирования |
| Отказоустойчивость | Render Free (1 экземпляр), health-пробы | Холодный старт ≈ 1 мин | Не PROD-конфигурация |
| Безопасность | `check_secrets.py`, security baseline, OSV-аудит в CI | — | Без изменений |
| CI/CD | `backend.yml` (архитектура → тесты → jar → smoke), независимые CI на приложения, E2E вручную; **сборка Docker-образа добавлена в этом PR** (раньше не проверялась) | — | — |
| IaC | `infrastructure/terraform` (modules `render`, `neon`, `country-cell`; environments `dev`, `prod`), `helm/kunde-backend`; `terraform-dev.yml` | Не проверялось применением (запрещено условиями) | Только чтение |
| DR | `restore_drill.sh` (локально, синтетика), [23-reliability](23-reliability-and-disaster-recovery.md) | Нет доказательства PROD-бэкапа; doc `restore-drill.md` ссылается на старый путь миграций | Обновить путь при следующем касании |

## 6. План подготовки (без физического разделения)

1. **Границы честные** (идёт): ратчеты baseline, циклов, FK, слоёв — [fitness-functions](fitness-functions.md). Каждый PR уменьшает числа.
2. **Контракты вместо SQL**: `<Domain>AdminApi`; демо-сиды в `app`; расширение `BookingCategory`; `PartnerDirectory` для остатка V9.
3. **События**: первые нефинансовые продюсеры (`kunde.partner.approved`, `kunde.catalog.offering_published` — потребитель: поисковая проекция/уведомления), relay на DEV, инструмент DLQ и retention; `X-Correlation-ID` → `correlation_id`.
4. **Контрактные тесты** потребитель↔поставщик для каждого порта (`PartnerDirectory`, `SupportCaseDirectory`, `RideRouting`) и снимок OpenAPI.
5. **Независимые миграции**: правило «expand → migrate → contract» + префикс владельца; каталог `db/migration` остаётся один до решения о разделении БД (политика уже в [database-and-migrations](../engineering-foundation/database-and-migrations.md)).
6. **Первый кандидат на реальное выделение** — только при выполнении критерия ADR-025; по данным — `education`, затем `leisure+events`.

## 7. Что можно оставить общим без риска

Общая БД на ранних стадиях (с запретом нового чужого SQL), `platform`, `identity`/`auth`, `partner`/`catalog`, один артефакт и один набор миграций, общий поставщик идентичности (ADR-013/015).

## Автоматическая защита

`backend/app/src/test/java/kz/kunde/architecture/` — `ArchitectureBoundariesTest` (ратчет рёбер и владельцев таблиц) и `ArchitectureFitnessTest` (форма графа). Запускаются в `backend.yml` первым шагом, без БД и Spring. Правило снижения: baseline только уменьшается; регенерация — `-Dkunde.architecture.updateBaseline=true` / `-Dkunde.architecture.updateKnown=true` с ручной проверкой diff.
