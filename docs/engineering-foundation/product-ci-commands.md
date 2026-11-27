# Команды разработки по продуктам и матрица тестов (ADR-027)

Статус ADR-027 — PROPOSED. Таблица строится из `scripts/ci/product-registry.json`; граф зависимостей читается из Gradle/pubspec (`python3 scripts/ci/detect_affected.py --print-graph`).

## Что запускать локально

| Продукт | Backend (unit) | Flutter feature-тесты (приложение: директории) | Существующие native E2E |
|---|---|---|---|
| home-services | `:services:homeservices:test` | consumer: home, home_services; executor: home_services; admin: home_services_admin; partner: home_services | нет |
| beauty | `:services:beauty:test` | consumer: beauty; executor: beauty; admin: beauty | нет |
| taxi | `:services:rides:test` | consumer: rides; admin: rides_admin | rides-native-e2e |
| delivery | `:services:delivery:test` | consumer: delivery; admin: delivery_admin; partner: delivery | delivery-native-e2e |
| food | `:services:food:test` | consumer: food; admin: food_admin | нет |
| groceries | `:services:groceries:test` | consumer: groceries | groceries-native-e2e, groceries-roles-native-e2e |
| education | `:services:education:test` | consumer: education; partner: education | education-native-e2e, education-roles-native-e2e |
| health | `:services:health:test` | consumer: health; admin: health | health-native-e2e |
| events | `:services:events:test` | — | нет |
| leisure | `:services:leisure:test` | consumer: leisure; executor: leisure; admin: leisure_admin, leisure; partner: leisure | leisure-native-e2e |
| auto | `:services:auto:test` | consumer: auto; admin: auto_admin | auto-native-e2e |
| flowers-gifts | `:services:flowers:test` | consumer: flowers | нет |

Backend, один продукт: `cd backend && ./gradlew :services:<module>:test` (Gradle собирает только его зависимости); интеграционные тесты домена лежат в `:app` — `./gradlew :app:test --tests 'kz.kunde.<package>.*'` (нужен PostgreSQL, `DB_URL`/`DB_USERNAME`/`DB_PASSWORD`).
Flutter, одна фича: `cd apps/<app> && flutter test test/features/<dir>`. Выборочный запуск не заменяет `flutter analyze --fatal-infos` и сборку: приложение компилирует все продукты.
Что запустит CI для вашей правки: `git diff --name-only origin/main... | python3 scripts/ci/detect_affected.py --files-from -`.

## Что запускает CI

| Проверка | Когда | Как выбирается |
|---|---|---|
| Backend CI, Flutter CI (Consumer/Executor/Admin) | PR и push в `main` (по paths) | детектор: `full` / `selective` / `skip` внутри job |
| Partner Flutter CI | то же | целиком (плоские тесты) |
| CI configuration, Security CI | всегда | без фильтра |
| **Required CI Gate** (`ci-pr.yml`) | каждый PR | сводит остальные проверки; **в required checks добавляет владелец** |
| Product E2E (`product-e2e.yml`) | вручную | `gh workflow run product-e2e.yml --ref main -f product=taxi -f suite=multi-role` |
| E2E suite (`e2e-suite.yml`) | вручную | флажки по приложениям |

Product E2E собирает изолированный стек из `ref` (локальный PostgreSQL), поэтому поля DEV/TEST нет. Продукт без существующего E2E (home-services, beauty, food, events, flowers-gifts) даёт `NOT AVAILABLE` и красный запуск — «нет E2E» не выдаётся за «прошёл». Suite `api` = выборочный Product API E2E (`product-api-e2e.yml`): `:services:<module>:test` продукта + HTTP/PostgreSQL-тесты его пакетов в `:app` (`kz.kunde.<package>.*`); для Home Services это в том числе сквозной `HomeServicesJourneyIntegrationTest` (оффер → модерация → заказ → приём → визит → завершение, отмена, доступ, повторы, недопустимые переходы).

## DEV-ready / E2E-verified / PROD-ready

- **DEV-ready**: required CI зелёный, merge в `main`, подписанный DEV APK и DEV backend собраны. E2E не требуется.
- **E2E-verified**: Product E2E (или E2E suite) этого SHA прошёл; без запуска статус всегда «E2E NOT RUN».
- **PROD-ready**: E2E-verified + Full Regression на SHA + решение владельца. Full Regression и ночной прогон **ещё не реализованы** (следующий PR).

## Профили продуктов DEV/TEST (PR 6)

`python3 scripts/dev/product_profile.py dev-home-services` печатает переменные окружения с **существующими** именами флагов (`HOME_SERVICES_ENABLED`, `BOOKING_ENABLED`, `FOOD_ENABLED`, …); все остальные флаги и demo-сидеры явно `false`, поэтому другие продукты не запускают планировщики (`DeliveryMaintenance` — `@ConditionalOnProperty app.delivery.enabled`), не создают демо-данные и не вызывают интеграции. Идентификация/вход остаются включёнными, Flyway не затрагивается. Профили: `dev-<продукт>` для каждого продукта реестра и `dev-all`; `--yaml` — блок `env:` для GitHub Actions. Профиль **никогда** не применяется к PROD (флаги PROD принадлежат владельцу). Проверки: `test_product_profile.py` (каждое имя флага есть в `application.yml`) и `ProductProfileIsolationIntegrationTest` (при выключенных продуктах нет Delivery-планировщика, демо-сидеров и `outboxRelayJob`, а `/capabilities` показывает только Home Services и Booking).
Применение к DEV-сервису — переменными окружения на Render/compose (по действующим правилам AGENTS.md); `scripts/dev/*_smoke.py` проверяют результат.

## Full Regression и Nightly (PR 6)

`full-regression.yml`: ночью (02:17 Asia/Almaty), вручную и как `workflow_call` перед PROD. Состав: Backend CI (FULL), четыре Flutter-приложения (FULL), все существующие native E2E (`product-e2e.yml` product=all suite=full). Отчёт требует успеха **каждой** части (skipped не засчитывается); продукты без native E2E перечислены как «не верифицированы E2E». Не блокирует merge и DEV APK. PROD-пайплайна в репозитории нет: требование «релиз ссылается на успешный Full Regression этого SHA» зафиксировано здесь и в ADR-027, автоматически не исполняется.

## DEV Release по затронутым приложениям (PR 6)

`release_targets.py` теперь берёт зависимости общих пакетов из `pubspec.yaml` (например, `kunde_maps` → Consumer и Executor, а не все четыре); `kunde_operator` → Consumer, Executor, Admin (Consumer зависит от него по pubspec — прежнее правило этого не учитывало). Неизвестный пакет или нечитаемый граф → все четыре. Ручная сборка всех четырёх: `gh workflow run release-apk-on-merge.yml --ref main` (по умолчанию все `true`). Сборка APK не ждёт E2E.

## Кэш сборки backend (PR 6)

`setup-gradle` (уже закреплён в репозитории) вместо `cache: gradle`; `org.gradle.caching=true`; тесты **не кэшируются** (зависят от PostgreSQL и времени). На PR кэш только читается, пишется с `main`. Gradle configuration cache и параллельный запуск модулей не включены: тесты `:app` делят одну БД, эффект не измерен. Flutter: `flutter-action cache: true` (SDK + pub cache) уже был. Эффект измеряется по длительности `backend` на `main` до/после (см. отчёт).
