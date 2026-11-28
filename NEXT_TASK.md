# Следующие проверки

## Home Services MVP: аудит и недостающие функции (приоритет P0)

Engineering Foundation 2.0 завершён технически ([ADR-027](docs/architecture/adr/ADR-027-product-based-selective-ci.md), [пилот](docs/engineering-foundation/selective-ci-pilot-2026-11-27.md)); остальные продукты и архитектурные улучшения заморожены, общие компоненты — только при необходимости Home Services или для критических ошибок. Задача: полный аудит Home Services от Consumer до Partner, Executor и Admin ([docs/product/home-services.md](docs/product/home-services.md)), список недостающих бизнес-функций и их реализация до пилота с реальными клиентами и мастерами в Алматы. Сделано: H1 (мастера и коды), H2 (адрес на карте). Следующее: H8 панель заказов Admin, H6 отзывы, H7 споры, H10 отказ мастера/переназначение; перед проверкой на телефоне — деплой DEV и пересборка APK. Бэклог MVP: **нативный multi-role Android E2E Home Services** (Journey-тест — API-интеграция, не замена), проверка на реальном устройстве, оплата/возвраты/уведомления (за провайдерскими gate-ами), подключение реальных исполнителей.

Владельцу: подключить «Required CI Gate» к branch protection по [инструкции](docs/engineering-foundation/branch-protection-required-ci-gate.md) (старые required checks пока не отключать). Проверка: `python3 -m unittest discover -s scripts/ci -p 'test_*.py'`; `cd backend && ./gradlew :services:homeservices:test :app:test --tests 'kz.kunde.homeservices.*'`; `cd apps/executor && flutter test test/features/home_services`.

## Микросервисная готовность: следующие PR

1. Вынести демо-сиды (`PartnerOpsDemoSeeder`, `LeisureDemoSeeder`) в `backend/app` — рвёт узел циклов вокруг `partner`; нужен PostgreSQL для интеграционных тестов.
2. `LeisureAdminApi`/`FoodAdminApi` вместо SQL в `Admin*Controller` (25 из 44 SQL Admin); HTTP-контракты без изменений.
3. Расширить `BookingCategory`, убрать `booking → auto/health`; порт доступности для `rides ↔ delivery`.
4. Первые нефинансовые продюсеры (`partner.*`, `offering.*`), инструмент DLQ и retention до включения relay; `correlation_id` в событиях.
5. Принять или изменить ADR-025; по разрешению — деплой DEV из `main` (Flyway, health/readiness, вход четырёх ролей, контракты с актуальными APK).


## Архитектура: готовность к микросервисам (комплексный аудит)

Реструктуризация и авторизация завершены (ADR-023, ADR-024). Следующий шаг — комплексный аудит готовности KUNDE к микросервисной архитектуре **без физического разделения backend**: по доменам (реестр `docs/architecture/domain-registry.md`) проверить владение данными (115 SQL-связей в baseline, прежде всего `admin`), публичные контракты между модулями, события/outbox (ADR-022), готовность к выделению каждого модуля и порядок. Проверки: `cd backend && ./gradlew build`; `cd apps/<app> && flutter analyze --fatal-infos && flutter test`.

## KUNDE Beauty & Care 1.0

Consumer, Partner-обзор, Executor и Admin-аналитика готовы ([beauty-care.md](docs/product/beauty-care.md)). Дальше: Partner CRUD услуг/акций/расписания и модерация отзывов, Admin модерация и жалобы, перенос записи, hold и онлайн-оплата (провайдер), уведомления, нативные Android E2E, DEV-деплой и Release APK. Команды: `cd backend && ./gradlew test --tests '*Beauty*' --tests '*Booking*'`; `cd apps/consumer && flutter test test/features/beauty test/features/booking`.

## KUNDE Delivery 1.0

Провести нативную DEV-приёмку Consumer → Executor → Partner/Admin на общей ревизии после интеграции KUNDE Maps. Критерии включают выбор адресов на карте, дорожную котировку, назначение, GPS, вручение и видимость по ролям. Сценарий оплаты проверяется после подключения утверждённого провайдера. [Аудит, очередь интеграции и ограничения](docs/product/delivery-1.0-audit.md).

## KUNDE Home Services 1.0

Готово: backend предложений, тарифов и визита мастера (V69–V71, ETA через `RoutingProvider`); экраны Consumer (каталог, котировка, заказ с `expectedPriceMinor`, ход визита), Partner (список, создание, подача), Admin (модерация) и Executor (визит). Дальше по порядку: (1) Partner — зоны и тарифы, выдача кода-приглашения мастеру; (2) смета и доп. работы с согласием клиента, фотоотчёты, отзывы, гарантийные обращения; (3) сидер DEV, многоролевой нативный E2E, деплой DEV и четыре Release APK. Команды: `cd backend && ./gradlew :app:test --tests '*HomeServices*' --tests '*Booking*'`; `cd apps/consumer && flutter test test/features/home_services test/features/booking/booking_flow_test.dart`; `cd apps/executor && flutter test test/features/home_services`.

## KUNDE Events & Tickets

1. Нативные Android E2E Partner/Admin/Executor для Events (создание события и сеансов, модерация с `EVENTS_OPERATIONS`, скан GATE внутри окна входа), стабилизация эмулятора CI (шаги потери сети и выключенного флага сейчас `UNVERIFIED`).
2. Partner: редактор схемы зала (сейчас схема задаётся при создании сеансов); Admin: промо отдельно по продукту. Затем установка четырёх APK на устройство, TalkBack, RU/KK/EN, сравнение скриншотов с референсами и синхронизация Linear. Команды: `python3 scripts/dev/events_smoke.py https://kunde-backend-ty81.onrender.com`, `python3 scripts/dev/leisure_smoke.py …`; `cd backend && ./gradlew test --tests '*Events*' --tests '*Leisure*'`. [Матрица](docs/product/events.md).

## KUNDE Groceries 1.0

1. Собрать четыре подписанных DEV Release APK из одного `main` SHA (`android-release.yml`: Consumer, `executor=true`, `admin=true`; `partner-release.yml`), проверить подпись, package ID, DEV URL, SHA-256; установить на эмулятор.
2. Нативный Android E2E Consumer (каталог → товар → корзина → checkout → заказ) и реальные скриншоты Consumer/Partner/Executor/Admin; сверка с референсом.
3. Открыто: корректировка суммы по фактическому весу, уведомления, лояльность (нужно решение владельца), карта и ETA (нужны координаты магазинов).
4. Команды: `cd backend && ./gradlew test --tests '*Groceries*' --tests '*FoodPartnerAdmin*'`; `cd apps/consumer && flutter test test/features/groceries test/features/executor test/features/food_admin`.

## KUNDE Education

Завершить DEV/TEST-приёмку. Сверить SHA backend, проверить запись, TEST_CARD, уроки, тест и PDF через `scripts/dev/education_smoke.py`, затем подтвердить нативные сценарии четырёх приложений и установку подписанных APK. [Контракты, покрытие и ограничения](docs/product/education.md).

## KUNDE Food 2.0

1. DEV на `fd1fbb6` (V43) проверен смоуком; осталось выдать `FOOD_OPERATIONS` синтетическому сотруднику и вручную проверить Admin-экран.
2. Partner: экран аналитики (`GET …/food/summary`), CRUD секций и модификаторов меню, удаление/архив блюд; Admin: выдача `FOOD_OPERATIONS` синтетическому сотруднику на DEV и ручная проверка экрана.
3. Нативный Android E2E Food (вход → ресторан → блюдо → корзина → самовывоз/доставка → промокод → TEST_CARD → статус → отзыв), скриншоты Consumer/Partner/Admin для сравнения с референсом.
4. Команды: `cd backend && ./gradlew test --tests '*Food*'`; `cd apps/consumer && flutter test test/features/food`.

## KUNDE Leisure

1. Установить подписанные DEV APK из [PROJECT_STATE](PROJECT_STATE.md) на устройство, пройти Consumer-сценарий (Досуг → места → TEST_CARD → QR) и Partner/Executor/Admin; сверить скриншоты с референсом (`reports/leisure-native` в артефакте E2E).
2. Выяснить, почему эмулятор CI теряется при запуске приложения против выключенного `LEISURE_ENABLED`, и вернуть шаг `ui_flag_off` в блокирующие.
3. Команды: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com`; `cd backend && ./gradlew test --tests '*Leisure*'`; `cd apps/consumer && flutter test test/features/leisure`.

## Health & Wellness

Закрыть многоролевую приёмку синтетического Health в DEV. Перед выпуском проверить оставшиеся фильтры и выездные wellness-задания, отзывы, жалобы и возвраты. Выполнить нативные сценарии Partner и Admin, проверить утверждённый аккаунт с `HEALTH_OPERATIONS`, установку подписанных APK, TalkBack и полный RU/KK/EN. Consumer Android уже прошёл сценарий каталога, записи с тестовой картой и отмены. Результаты и оставшиеся продуктовые сценарии ведутся в [Health PRD](docs/product/health-wellness.md).

## KUNDE Control Center

Выполнить авторизованный Web E2E совмещённых #152/#159 на DEV с утверждённым синтетическим сотрудником. Критерии: вход, обзор и сводка Delivery, разрешённый реестр сотрудников, отказ 401/403 и выход. После зелёных обязательных проверок объединить #159 в `feat/delivery-admin-web`, затем заново проверить и объединить #152 в `main`.

Из итогового main запустить [Android Release APK (DEV)](https://github.com/ADatkashov/kunde/actions/workflows/android-release.yml) с `admin=true`, `executor=false` и штатным DEV API. Сверить исходный коммит, `com.kunde.admin`, release-подпись, отсутствие debug-настроек, размер и SHA-256 файла. Подтвердить установку и пройти Admin Android E2E, когда доступно тестовое устройство и синтетическая учётная запись.
