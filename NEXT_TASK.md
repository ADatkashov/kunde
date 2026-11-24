# Следующие проверки

## KUNDE Beauty & Care 1.0

Consumer, Partner-обзор, Executor и Admin-аналитика готовы ([beauty-care.md](docs/product/beauty-care.md)). Дальше: Partner CRUD услуг/акций/расписания и модерация отзывов, Admin модерация и жалобы, перенос записи, hold и онлайн-оплата (провайдер), уведомления, нативные Android E2E, DEV-деплой и Release APK. Команды: `cd backend && ./gradlew test --tests '*Beauty*' --tests '*Booking*'`; `cd mobile && flutter test test/features/beauty test/features/booking`.

## KUNDE Delivery 1.0

Провести нативную DEV-приёмку Consumer → Executor → Partner/Admin на общей ревизии после интеграции KUNDE Maps. Критерии включают выбор адресов на карте, дорожную котировку, назначение, GPS, вручение и видимость по ролям. Сценарий оплаты проверяется после подключения утверждённого провайдера. [Аудит, очередь интеграции и ограничения](docs/product/delivery-1.0-audit.md).

## KUNDE Home Services 1.0

Связать [справочник V60](docs/product/home-services.md) с модерируемыми предложениями на существующих `booking_services`. Критерии: каталог возвращает только опубликованные предложения, выдача постраничная, Partner видит данные только своей организации, смена состояния требует гранта и записывается в аудит. Проверки текущего флага: `cd backend && mvn -Dtest=HomeServicesSettingsTest,PlatformControllerTest,BookingApiIntegrationTest test` и `cd mobile && flutter test test/features/booking/booking_flow_test.dart`.

## KUNDE Events & Tickets

1. Нативные Android E2E Partner/Admin/Executor для Events (создание события и сеансов, модерация с `EVENTS_OPERATIONS`, скан GATE внутри окна входа), стабилизация эмулятора CI (шаги потери сети и выключенного флага сейчас `UNVERIFIED`).
2. Partner: редактор схемы зала (сейчас схема задаётся при создании сеансов); Admin: промо отдельно по продукту. Затем установка четырёх APK на устройство, TalkBack, RU/KK/EN, сравнение скриншотов с референсами и синхронизация Linear. Команды: `python3 scripts/dev/events_smoke.py https://kunde-backend-ty81.onrender.com`, `python3 scripts/dev/leisure_smoke.py …`; `cd backend && ./gradlew test --tests '*Events*' --tests '*Leisure*'`. [Матрица](docs/product/events.md).

## KUNDE Groceries 1.0

1. Собрать четыре подписанных DEV Release APK из одного `main` SHA (`android-release.yml`: Consumer, `executor=true`, `admin=true`; `partner-release.yml`), проверить подпись, package ID, DEV URL, SHA-256; установить на эмулятор.
2. Нативный Android E2E Consumer (каталог → товар → корзина → checkout → заказ) и реальные скриншоты Consumer/Partner/Executor/Admin; сверка с референсом.
3. Открыто: корректировка суммы по фактическому весу, уведомления, лояльность (нужно решение владельца), карта и ETA (нужны координаты магазинов).
4. Команды: `cd backend && ./gradlew test --tests '*Groceries*' --tests '*FoodPartnerAdmin*'`; `cd mobile && flutter test test/features/groceries test/features/executor test/features/food_admin`.

## KUNDE Education

Завершить DEV/TEST-приёмку. Сверить SHA backend, проверить запись, TEST_CARD, уроки, тест и PDF через `scripts/dev/education_smoke.py`, затем подтвердить нативные сценарии четырёх приложений и установку подписанных APK. [Контракты, покрытие и ограничения](docs/product/education.md).

## KUNDE Food 2.0

1. DEV на `fd1fbb6` (V43) проверен смоуком; осталось выдать `FOOD_OPERATIONS` синтетическому сотруднику и вручную проверить Admin-экран.
2. Partner: экран аналитики (`GET …/food/summary`), CRUD секций и модификаторов меню, удаление/архив блюд; Admin: выдача `FOOD_OPERATIONS` синтетическому сотруднику на DEV и ручная проверка экрана.
3. Нативный Android E2E Food (вход → ресторан → блюдо → корзина → самовывоз/доставка → промокод → TEST_CARD → статус → отзыв), скриншоты Consumer/Partner/Admin для сравнения с референсом.
4. Команды: `cd backend && ./gradlew test --tests '*Food*'`; `cd mobile && flutter test test/features/food`.

## KUNDE Leisure

1. Установить подписанные DEV APK из [PROJECT_STATE](PROJECT_STATE.md) на устройство, пройти Consumer-сценарий (Досуг → места → TEST_CARD → QR) и Partner/Executor/Admin; сверить скриншоты с референсом (`reports/leisure-native` в артефакте E2E).
2. Выяснить, почему эмулятор CI теряется при запуске приложения против выключенного `LEISURE_ENABLED`, и вернуть шаг `ui_flag_off` в блокирующие.
3. Команды: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com`; `cd backend && ./gradlew test --tests '*Leisure*'`; `cd mobile && flutter test test/features/leisure`.

## Health & Wellness

Закрыть многоролевую приёмку синтетического Health в DEV. Перед выпуском проверить оставшиеся фильтры и выездные wellness-задания, отзывы, жалобы и возвраты. Выполнить нативные сценарии Partner и Admin, проверить утверждённый аккаунт с `HEALTH_OPERATIONS`, установку подписанных APK, TalkBack и полный RU/KK/EN. Consumer Android уже прошёл сценарий каталога, записи с тестовой картой и отмены. Результаты и оставшиеся продуктовые сценарии ведутся в [Health PRD](docs/product/health-wellness.md).

## KUNDE Control Center

Выполнить авторизованный Web E2E совмещённых #152/#159 на DEV с утверждённым синтетическим сотрудником. Критерии: вход, обзор и сводка Delivery, разрешённый реестр сотрудников, отказ 401/403 и выход. После зелёных обязательных проверок объединить #159 в `feat/delivery-admin-web`, затем заново проверить и объединить #152 в `main`.

Из итогового main запустить [Android Release APK (DEV)](https://github.com/ADatkashov/kunde/actions/workflows/android-release.yml) с `admin=true`, `executor=false` и штатным DEV API. Сверить исходный коммит, `com.kunde.admin`, release-подпись, отсутствие debug-настроек, размер и SHA-256 файла. Подтвердить установку и пройти Admin Android E2E, когда доступно тестовое устройство и синтетическая учётная запись.
