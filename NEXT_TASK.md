# Следующие проверки

## KUNDE Events & Tickets

1. Дождаться зелёных обязательных проверок PR #196 (включая `Leisure Android E2E`), снять Android-скриншоты Events/Leisure (Android visual CI), перевести PR из Draft и слить. Глобальный поиск «концерт» → Events, «боулинг» → Leisure ещё не сделан.
2. DEV: после merge развернуть `main`, проверить V45, `eventsEnabled: true`, купить место через `TEST_CARD`, проверить QR. Команды: `cd backend && mvn test -Dtest='Events*,Leisure*'`. [Матрица](docs/product/events.md).

## KUNDE Education

Провести первый курс от публикации до подтверждения записи через поток и тестовый ledger. Критерии: модерация курса, серверная цена, транзакционная защита вместимости, идемпотентная запись, подтверждённая тестовая оплата. [Матрица и контракт](docs/product/education.md).


## KUNDE Food 2.0

1. DEV на `fd1fbb6` (V43) проверен смоуком; осталось выдать `FOOD_OPERATIONS` синтетическому сотруднику и вручную проверить Admin-экран.
2. Partner: экран аналитики (`GET …/food/summary`), CRUD секций и модификаторов меню, удаление/архив блюд; Admin: выдача `FOOD_OPERATIONS` синтетическому сотруднику на DEV и ручная проверка экрана.
3. Нативный Android E2E Food (вход → ресторан → блюдо → корзина → самовывоз/доставка → промокод → TEST_CARD → статус → отзыв), скриншоты Consumer/Partner/Admin для сравнения с референсом.
4. Команды: `cd backend && mvn test -Dtest='Food*'`; `cd mobile && flutter test test/features/food`.

## KUNDE Leisure

1. Установить подписанные DEV APK из [PROJECT_STATE](PROJECT_STATE.md) на устройство, пройти Consumer-сценарий (Досуг → места → TEST_CARD → QR) и Partner/Executor/Admin; сверить скриншоты с референсом (`reports/leisure-native` в артефакте E2E).
2. Выяснить, почему эмулятор CI теряется при запуске приложения против выключенного `LEISURE_ENABLED`, и вернуть шаг `ui_flag_off` в блокирующие.
3. Команды: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com`; `cd backend && mvn test -Dtest='Leisure*'`; `cd mobile && flutter test test/features/leisure`.

## Health & Wellness

Закрыть многоролевую приёмку синтетического Health в DEV. Перед выпуском проверить оставшиеся фильтры и выездные wellness-задания, отзывы, жалобы и возвраты. Выполнить нативные сценарии Partner и Admin, проверить утверждённый аккаунт с `HEALTH_OPERATIONS`, установку подписанных APK, TalkBack и полный RU/KK/EN. Consumer Android уже прошёл сценарий каталога, записи с тестовой картой и отмены. Результаты и оставшиеся продуктовые сценарии ведутся в [Health PRD](docs/product/health-wellness.md).

## KUNDE Control Center

Выполнить авторизованный Web E2E совмещённых #152/#159 на DEV с утверждённым синтетическим сотрудником. Критерии: вход, обзор и сводка Delivery, разрешённый реестр сотрудников, отказ 401/403 и выход. После зелёных обязательных проверок объединить #159 в `feat/delivery-admin-web`, затем заново проверить и объединить #152 в `main`.

Из итогового main запустить [Android Release APK (DEV)](https://github.com/ADatkashov/kunde/actions/workflows/android-release.yml) с `admin=true`, `executor=false` и штатным DEV API. Сверить исходный коммит, `com.kunde.admin`, release-подпись, отсутствие debug-настроек, размер и SHA-256 файла. Подтвердить установку и пройти Admin Android E2E, когда доступно тестовое устройство и синтетическая учётная запись.
