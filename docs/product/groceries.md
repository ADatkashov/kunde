# KUNDE Groceries 1.0 — DEV/TEST (обновлено 2026-11-21)

Groceries — самостоятельный домен поверх общей платформы: магазины и товары в таблицах Food (`vertical = 'GROCERY'`), заказы, промокоды, резерв остатков, самовывоз и оплата DEV переиспользуются из Food 2.0. Отдельного backend нет. Флаг `GROCERIES` (env `GROCERIES_ENABLED`, пусто = следует среде; переключатель Admin; `/capabilities.groceriesEnabled`): выключен → каталог, корзина, списки и новые заказы дают 409 `GROCERIES_DISABLED`, история, отмена, повтор и удаление своих данных работают.

## Миграции Groceries

| V | Содержание |
|---|---|
| V45 | флаг `GROCERIES`, 12 категорий RU/KK/EN, атрибуты товара (бренд, страна, состав, хранение, КБЖУ, цена «до скидки»), избранное, списки, серверная корзина |
| V46 | фото товаров (HTTPS-ссылки, до 6, первое — обложка) |
| V47 | интерактивная сборка: позиция «собрано / нет в наличии / замена», предложение замены клиенту |
| V50 | задачи курьера для доставки (`food_courier_tasks`), актор `COURIER` в событиях заказа |
| V51 | scoped-грант `GROCERIES_OPERATIONS` |
| V52 | проверенные отзывы на товары и рейтинг |

(V48–V49 заняты Education.)

## Матрица «функция → статус»

| Функция | Статус | Доказательство |
|---|---|---|
| Категории, поиск, фильтры (категория, магазин, цена, наличие, акции, новинки, бренд, рейтинг), сортировка (популярность, цена, новинки, скидка, рейтинг), пагинация — на сервере | Готово | `GroceriesApiIntegrationTest` |
| Карточка товара: состав, КБЖУ, хранение, страна, связанные, вес по 100 г, обязательные опции, галерея фото | Готово | тесты backend и Consumer |
| Системный Share (`share_plus`) | Готово | виджет-тест через канал платформы |
| Избранное, списки покупок, корзина на сервере (ownership, пересчёт, смена цены/остатка) | Готово | интеграционные тесты |
| Checkout, самовывоз, промокоды, оплата DEV, идемпотентность, резерв, отмена | Переиспользовано из Food | `FoodApiIntegrationTest` |
| Partner: карточка товара, фото, весовые товары, остатки, цены/«до скидки», очередь заказов, принятие, интерактивная сборка, замены, выдача и передача курьеру | Готово | `FoodPartnerAdminApiIntegrationTest`, 120 тестов Partner |
| Согласование замены клиентом, пересчёт суммы, блокировка выдачи до завершения сборки | Готово | backend + Consumer-тест |
| Executor: задачи магазинов (атомарное принятие, забор, маршрут через карты с запасным копированием адреса, доставка, история) | Готово | backend + 12 тестов Executor |
| Admin: Groceries Control Center (KPI, график, категории, склад, магазины, заказы, возвраты, акции, отзывы, жалобы, аудит), scoped RBAC | Готово | backend + 17 тестов Admin |
| Проверенные отзывы на товары и рейтинг | Готово | backend + Consumer-тест |
| Сквозной сценарий Consumer → Partner → Executor → Consumer → Admin | Готово (integration test на PostgreSQL) | `groceriesEndToEndConsumerPartnerExecutorConsumerAdmin` |
| Корректировка суммы по фактическому весу | Не сделано | — |
| Лояльность | Не сделано: правила не утверждены владельцем (`docs/business/13`), по ТЗ остаётся выключенной | — |
| Уведомления (in-app/push) | Не сделано: нет провайдера и хранилища уведомлений; статусы обновляются опросом | — |
| Карта и маршрут в Consumer, ETA, расстояния | Не сделано: у магазинов нет координат; адрес курьеру открывается во внешних картах | — |
| Загрузка файлов фото | Не сделано: нет хранилища, только HTTPS-ссылки | — |
| Нативный Android E2E Consumer (debug APK, эмулятор API 35, реальный бэкенд + PostgreSQL, синтетический магазин) | Выполнен: вход → Продукты → товар → корзина → оформление → заказ PLACED в API; скриншоты в [`evidence/groceries-native`](evidence/groceries-native/) (workflow `groceries-native-e2e.yml`). Это debug-сборка с локальным URL, не Release APK; Partner/Executor/Admin и TalkBack/тёмная тема/200 % на устройстве NOT VERIFIED | workflow run 44938792992 |
| Подписанные DEV Release APK из одного SHA | Собраны (см. ниже); установка и запуск на устройстве NOT VERIFIED | workflow-проверка подписи |

## DEV (Render `kunde-backend-ty81`)

Развёрнут `main` `3faa0ee` (V45–V52): `/capabilities.groceriesEnabled=true`, `/groceries/*` отвечают, `scripts/dev/food_smoke.py` → `SMOKE OK`. Полный сценарий на DEV не прогонялся: нужны синтетические партнёр, курьер и сотрудник Admin с грантом, а выдача грантов вне разрешения (AGENTS.md).

## Проверки (запущены)

Backend `mvn verify` на PostgreSQL 16 — 389 тестов, 0 падений. Consumer: analyze + 353 теста; Partner: analyze + 120 тестов. Golden-рендеры экранов: `mobile/test/features/groceries/goldens/`.

## DEV Release APK из `main` `e22727a` (2026-11-21)

Собраны workflow `android-release.yml` / `partner-release.yml`; шаг «Verify APK» (подпись v2/v3, не debug-сертификат, package ID, INTERNET, не debuggable, DEV URL `kunde-backend-ty81`) прошёл. **Установка на устройство, запуск и нативный E2E не выполнялись.** Это не финальная приёмка: лояльность, уведомления, карта и нативный E2E остаются открытыми.

| Приложение | Package | Run | SHA-256 |
|---|---|---|---|
| Consumer | `com.example.kunde_mobile` | [44933153682](https://github.com/ADatkashov/kunde/actions/runs/44933153682) | `287997a721a863fe575750195f366005d9689ec836810b09bb05611b60f7304d` |
| Executor | `com.kunde.executor` | [44933156811](https://github.com/ADatkashov/kunde/actions/runs/44933156811) | `fccc63a147632767fa3de54ca0c5053ac353b1463cb9128118b02ce515e0d4f4` |
| Admin | `com.kunde.admin` | [44933159731](https://github.com/ADatkashov/kunde/actions/runs/44933159731) | `0f9315824356f0e7cbe0dbdc5ec51944b6f060af9b715b98536f32f99074fb0b` |
| Partner | `com.kunde.kunde_partner` | [44933162682](https://github.com/ADatkashov/kunde/actions/runs/44933162682) | `139869c772a293bb39fff09ff024185d05696973783cdb2582b7cb757aee56fa` |

Артефакты хранятся 14 дней в соответствующих запусках.

### Замечания по реальным скриншотам

- Эмулятор запущен в английской локали: часть экранов Food (корзина, статус заказа) показывает русский текст — это общий код Food, не Groceries.
- В демо-каталоге у «Яблоки Айдаред» в плитке показана иконка корзины вместо 🍎 (нет соответствия эмодзи) — косметика, не исправлено.

### Нативный E2E исполнения заказа (Partner APK)

Workflow `groceries-roles-native-e2e.yml` (эмулятор API 35, debug Partner APK, реальный бэкенд и PostgreSQL, синтетические роли в изолированной CI-БД): заказ клиента (API) → в приложении Partner принять, начать готовить, «Собрано», «Заказ готов» → курьер (Executor **через API**: взять, забрал, доставил) → Admin Control Center (**через API**: сводка и список заказов). Статус PASSED, скриншоты в [`evidence/groceries-roles-native`](evidence/groceries-roles-native/). Экраны Executor и Admin на устройстве, замена позиции с ответом клиента, debug-сборки (не Release) — NOT VERIFIED.
