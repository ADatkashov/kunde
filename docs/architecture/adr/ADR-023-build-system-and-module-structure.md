# ADR-023 — Система сборки и модульная структура backend

- Status: **Accepted** — владелец утвердил решения 2026-11-24 (чат, ответ на PR #258; раздел «Решения владельца» ниже заменяет прежний раздел «Что нужно решить владельцу»). Переход на Gradle остаётся условным: Maven удаляется только после gate эквивалентности.
- Date: 2026-11-24
- Scope: Maven vs Gradle, гранулярность модулей, правила зависимостей, Flyway, CI/Docker, порядок миграции
- Builds on: ADR-001 (modular monolith), [project-structure-audit](../project-structure-audit.md), [microservice-readiness](../microservice-readiness.md)

## Context
Факты аудита (PR A): один Maven-модуль, 23 плоских пакета, 216 main-файлов; 159 междоменных связей в baseline, из них 44 — импорты и **115 — SQL в чужие таблицы**.
Импорты уже ацикличны, кроме `platform → delivery, rides`. Сборочная система упомянута в 14 workflow, 7 CI-скриптах и в `Dockerfile` (Maven 3.10.0 с зафиксированным SHA-256).
Референс владельца — ZAIRO: `backend/` на Gradle Kotlin DSL, 39 модулей в корне, Spring Boot 4.1.1, общая настройка в `subprojects {}` корневого `build.gradle.kts`, один запускаемый модуль `platform-api`, JPA. Что полезно: плоский `include(...)`, зафиксированный toolchain Java 21, BOM Spring Boot для всех модулей, `-parameters`. Что **не** переносим: 39 модулей на ~каждую сущность (у KUNDE 216 файлов), JPA (у KUNDE `JdbcTemplate`), отсутствие convention plugins и dependency locking.

Ключевое наблюдение: **модульная сборка гарантирует только импорты**. 72% связей KUNDE — SQL; компилятор их не видит. Любой вариант ниже дополняет, но не заменяет `ArchitectureBoundariesTest`.

## Alternatives
1. **Остаться на одном Maven-модуле, только переложить пакеты.** Минимальный риск, но границы остаются соглашением, проверяемым одним тестом; зависимость одного домена от другого нельзя ограничить на уровне сборки. Не даёт «Gradle проверяет границы».
2. **Multi-module Maven** (parent POM + `<modules>`). Сохраняет текущие CI/Docker/кэш; Spring Boot плагин, Flyway и Surefire работают как сейчас. Минусы: многословный XML, нет инкрементальной сборки и build cache «из коробки», повторяющаяся настройка модулей решается только parent POM и `dependencyManagement`.
3. **Multi-module Gradle (Kotlin DSL) + convention plugins (рекомендуется).** Плюсы: инкрементальная сборка и build cache (важно при 15–20 модулях и 30 workflow), `java-library` с `api`/`implementation` — зависимость модуля A от внутренностей B не компилируется, convention plugins (`buildSrc` или `build-logic`) убирают дублирование, version catalog, dependency locking/verification, единая модель с ZAIRO. Минусы: переписать 14 workflow, 7 скриптов и Dockerfile; Gradle Wrapper и его проверка добавляют артефакты в supply chain; нужна проверка security baseline (`scripts/ci/security_baseline.py`, `docs/security/baseline-actionable-dependencies.json`), которая сегодня разбирает Maven-граф.
4. **Сразу `services/<domain>` + Gradle одним PR.** Отклонено: нарушает требование «не одним огромным PR» и не позволяет доказать эквивалентность.

Нельзя утверждать, что Gradle лучше Maven сам по себе: для 216 файлов выигрыш по скорости сборки небольшой. Аргументы за — проверяемые границы через `api`/`implementation`, convention plugins, build cache и единообразие с ZAIRO; против — стоимость миграции и риск для supply-chain и релизного конвейера.

## Decision (предлагаемое)
1. **Gradle Kotlin DSL multi-module**, при условии прохождения «gate эквивалентности» (ниже). Если gate не проходит, остаёмся на варианте 2 (multi-module Maven) — структура модулей та же.
2. **Порядок**: сначала внутри Maven-модуля убрать `platform → delivery, rides` и выделить `beauty`/`homeservices` из `booking` (PR B0/B, значения для baseline не растут); затем Gradle параллельно с Maven (PR C); затем перенос доменов (PR D…); затем переключение CI/Docker и удаление Maven (PR E). Maven и Gradle одновременно источниками истины не остаются.
3. **Модули** (не пустые, каждый — существующий код): `app`, `platform`, `services/{identity, partner, food, groceries, booking, beauty, homeservices, health, auto, rides, delivery, maps, leisure, events, education, support, admin}`. `identity` включает `auth`, `partner` — `catalog`. `fulfillment/order/notification/analytics` переносятся в `platform` (после подтверждения владельцем; ни один не вызывается из кода). Отдельных `api`-подмодулей нет; они вводятся только когда реальный цикл невозможно разорвать контрактом в `platform` (сейчас таких случаев нет — контракты `PartnerDirectory`, `SupportCaseDirectory`, `ActiveWork`, `RoutingProvider` уже в `platform`).
4. **Правила зависимостей** (проверяются сборкой и тестом): `app → всё`; `services/* → platform`; домен → домен только по существующим однонаправленным рёбрам (`groceries→food`, `beauty/health/auto→booking`, `events→leisure`, `admin→домены`, домены→`partner`/`identity`); обратные рёбра и циклы запрещены (Gradle сам отвергает циклы проектов); `platform` не зависит ни от одного `services/*`. Зависимости объявляются `implementation`; `api` — только когда тип модуля выходит в публичную сигнатуру.
5. **Flyway**: миграции остаются **одним деревом** в `app/src/main/resources/db/migration` (единый порядок версий V1…V68+; перенос в модули изменил бы classpath-путь, а при `locations` на нескольких путях — риск порядка и checksum). Владение таблицами фиксируется `table-owners.txt` и `DomainSchemaOwnershipIntegrationTest`, как сейчас. Применённые файлы не переименовываются и не меняются.
6. **Тесты**: unit/application — в модуле домена; интеграционные тесты, которым нужен весь контекст (13 штук в корне `src/test`), и `architecture/` — в `app` (или `testing/` позже); `ArchitectureBoundariesTest` и SQL-ратчет читают исходники всех модулей и продолжают работать.
7. **Что не меняется**: единый Spring Boot jar (`app`), одна БД, URL и контракты API, отсутствие отдельных исполняемых сервисов, версии Spring Boot 4.0.9 и Java 21 (повышение Boot — отдельное решение).

### Gate эквивалентности Maven ⇄ Gradle (условие переключения CI)
- Тот же набор тестов (число и имена из surefire против Gradle test reports), все зелёные; `ArchitectureBoundariesTest` без роста baseline.
- Boot-jar запускается и проходит `scripts/ci/smoke_backend.py`; список зависимостей runtime совпадает с Maven (сравнение `dependencies` отчёта).
- Flyway применяет V1…V68 на чистой БД и на копии DEV-схемы без изменения checksum.
- Docker-образ собирается на закреплённом образе JDK с проверяемым Gradle (wrapper с `distributionSha256Sum`, `gradle/actions/wrapper-validation` в CI); `security_baseline.py` адаптирован и даёт тот же или более строгий результат.
- Релизные APK и E2E (`*-native-e2e.yml`) используют backend из нового артефакта без изменения секретов; сам Android-конвейер не затрагивается.

## Consequences
- Плюс: границы импортов проверяются сборкой; новый домен — одна папка с `build.gradle.kts`; будущее выделение домена в сервис требует перенести модуль и его таблицы, а не разбирать пакеты.
- Минус: переписать CI/Docker/скрипты (PR E), поддерживать два сборщика на время перехода (PR C–E).
- Ограничение: SQL-связи остаются ратчетом тестом, пока домены не получат контракты (V5–V11 в microservice-readiness); модули не делают домены независимыми по данным.
- Риски: (R1) security baseline завязан на Maven-граф — адаптировать до PR E; (R2) Dockerfile с фиксированным Maven — заменить на wrapper с проверкой checksum; (R3) разные версии Boot у KUNDE (4.0.9) и ZAIRO (4.1.1) — не выравниваем; (R4) в этом окружении неизвестна доступность Gradle-дистрибутива через прокси — проверить в PR C; (R5) Flutter SDK для проверки PR по приложениям — проверить до первого Flutter-PR.

## Решения владельца (2026-11-24)

Заменяют предложения выше там, где отличаются. Прежние пункты ниже сохранены как история вопроса.

1. **Gradle Kotlin DSL multi-module** — утверждён при подтверждении эквивалентности (gate выше). Временная сетевая ошибка или отсутствие локального SDK — не причина отказа от Gradle; сначала устраняем.
2. **`booking`, `beauty`, `homeservices` — три самостоятельных модуля.** Общий механизм записи — контракт Booking, не копия реализации. Таблицы, флаги, Flutter-фичи и тесты переезжают вместе; история Flyway не меняется.
3. **`fulfillment`, `order`, `notification`, `analytics` не переносятся в `platform` автоматически.** Анализ (2026-11-24, код и ссылки): все четыре — контракты без вызовов из кода (только свои тесты и docs); решение по каждому — раздел «Судьба заготовок».
4. **Публичные API** сохраняются, если изменение не даёт архитектурной пользы; фундаментально плохие допустимо исправлять с обновлением клиентов, OpenAPI, тестов и совместимостью установленных APK.
5. **Четыре самостоятельных Flutter-приложения** (`apps/{consumer,partner,executor,admin}`) с общими пакетами (`packages/{design_system,api_client,localization}` — только для реально общего кода), прежними application ID и подписью. Отдельное приложение не граница безопасности: роли проверяются на backend.
6. **Конституция создаётся сразу** (`docs/architecture/CONSTITUTION.md`) и уточняется по ходу.
7. Каждый PR — отдельная ветка от актуального `main`; squash merge после зелёного обязательного CI (AGENTS.md).

### Судьба заготовок

| Пакет | Что внутри | Решение |
|---|---|---|
| `order` (`OrderLifecycle`, `ResponsePolicy`) | жизненный цикл заказа Food и политика ответа ресторана (D-05) | бизнес-контракт **Food** → `food` (подпакет `order`); общий домен `orders` создаётся только когда второй продукт реально разделит его |
| `fulfillment` (`PickupFulfillment`, `FulfillmentPolicy`, `FulfillmentMethod`) | самовывоз Food (D-02) | **Food** (подпакет `fulfillment`) |
| `notification` (`Delivery`, `NotificationPolicy`) | цепочка попыток доставки и допустимость каналов/дедупликация | техническая инфраструктура доставки → `platform.notifications`; бизнес-тексты и триггеры — в доменах; отдельный домен `notifications` появится при реальной бизнес-ответственности (провайдер D-11) |
| `analytics` (`EventCatalog`) | закрытый каталог бизнес-событий + шлюз минимизации данных | шлюз — `platform.analytics`; определения событий переедут к доменам-владельцам при подключении эмиссии |

Пустые модули не создаются; переносы — отдельным PR с тестами (имена пакетов тестов меняются вместе с кодом).

### История: что предлагалось решить владельцу (закрыто)
1. Подтвердить Gradle (Kotlin DSL) при условии gate эквивалентности — или выбрать multi-module Maven.
2. Подтвердить выделение `beauty` и `homeservices` из `booking` (меняет FQCN и владельцев таблиц `marketplace.beauty_`, `marketplace.home_service`; API и данные не меняются).
3. Подтвердить, что `fulfillment/order/notification/analytics` переезжают в `platform`.
4. Подтвердить, что API-маршруты остаются прежними (изменение публичных API в этом плане не требуется; переименование маршрутов только ради единообразия не предлагается).

## Статус реализации
- **PR C (Gradle foundation)** — `backend/build.gradle.kts`, `settings.gradle.kts`, version catalog `gradle/libs.versions.toml`, wrapper 8.14.3 с `distributionSha256Sum` и хэшем `gradle-wrapper.jar`; workflow `backend-gradle.yml` идёт рядом с Maven. Локальная проверка эквивалентности (PostgreSQL 16): `mvn verify` и `./gradlew build` — по 506 тестов, 0 ошибок, 2 пропущено; набор `BOOT-INF/lib` (80 jar) и число классов (842) совпадают; packaged-JAR smoke на Gradle-jar — PASS. Maven остаётся источником истины для CI и Docker до PR E.
- Ограничение окружения: Maven Central через прокси отвечает 429 при параллельной загрузке; локально использовался `mavenLocal()` через init-скрипт вне репозитория. В CI (GitHub-hosted) ограничения нет.
