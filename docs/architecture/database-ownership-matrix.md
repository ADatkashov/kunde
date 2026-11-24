# Database Ownership Matrix

Состояние: 2026-11-24. Одна БД PostgreSQL, схемы `identity, profile, marketplace, transactions, payments, support, serviceability, platform` разделены **по типу данных, а не по домену**; владение задано префиксами в [`table-owners.txt`](../../backend/app/src/test/resources/architecture/table-owners.txt) (тест `everyTableHasADeclaredOwner` падает на таблице без владельца). Таблица строится `python3 scripts/dev/architecture_matrix.py ownership`.

| Владелец | Таблиц | Входящих чужих SQL-ссылок | FK наружу | FK внутрь |
|---|---|---|---|---|
| auth | 5 | 2 | 3 | 0 |
| identity | 10 | 20 | 0 | 79 |
| partner | 6 | 18 | 6 | 14 |
| catalog | 3 | 3 | 3 | 0 |
| admin | 4 | 0 | 3 | 0 |
| support | 2 | 0 | 4 | 0 |
| food | 16 | 26 | 12 | 5 |
| groceries | 6 | 2 | 9 | 1 |
| delivery | 9 | 2 | 7 | 1 |
| rides | 10 | 1 | 7 | 1 |
| maps | 0 | 0 | 0 | 0 |
| booking | 8 | 30 | 9 | 19 |
| beauty | 6 | 2 | 10 | 0 |
| homeservices | 3 | 2 | 1 | 0 |
| health | 3 | 2 | 6 | 1 |
| auto | 14 | 6 | 19 | 2 |
| leisure | 19 | 11 | 16 | 0 |
| events | 0 | 0 | 0 | 0 |
| education | 14 | 0 | 6 | 0 |
| platform | 4 | 0 | 2 | 0 |

Всего таблиц: 142; FK между владельцами: 123.

«Входящих чужих SQL-ссылок» — сколько файлов других доменов (включая `admin`) называют таблицы владельца в своём SQL; для ядра (`identity`, `auth`, `partner`, `catalog`) такие ссылки — ожидаемое направление и не штрафуются в оценке готовности. «FK» — внешние ключи между таблицами разных владельцев (заморожены в [`cross-owner-foreign-keys.txt`](../../backend/app/src/test/resources/architecture/cross-owner-foreign-keys.txt); тест `noNewCrossOwnerForeignKeys`).

## Классификация внешних ключей между владельцами

| Группа | Пример | Что мешает | Путь |
|---|---|---|---|
| FK на `identity.users` | почти все домены | Пока `users` в общей БД — не мешает; при отдельной БД ссылка превращается в «id без констрейнта» + проверка через контракт identity | Единая политика: для новых таблиц хранить `user_id` без FK нельзя менять задним числом, поэтому FK остаются до этапа раздельных БД (решение владельца) |
| FK на `marketplace.partners`, `serviceability.cities` | booking, education, food, delivery, rides, leisure, catalog | то же: ядро-справочник | `PartnerDirectory` (ADR-021) уже закрывает чтение; FK заменяются при выделении |
| Вертикаль → движок | `beauty_*`, `health_*`, `auto_*` → `booking_*`, `bookings` | Вертикали и движок — одна семья | Выделять **вместе** («booking family») |
| Движок → вертикаль | `booking_services → auto_service_categories, health_categories`; `booking → customer_vehicles` | Обратная зависимость: движок не выделяется без вертикалей | Заменить на универсальную категорию (`BookingCategory`) |
| `groceries → food_*`, `food → grocery_categories` | `grocery_*` ссылается на `food_dishes/restaurants/orders` | Groceries — надстройка над Food | Выделять **вместе** («food family») |
| `support → deliveries/rides` | `support.*` | Поддержка знает чужие агрегаты | `CaseSubjectOwnership` уже в коде; FK убрать в отдельной миграции expand→contract |

## Анализ 102 SQL-связей

Каждая строка baseline — «файл домена A называет таблицу домена B». Группы по причине и по необходимому лекарству:

| Группа | Связей | Примеры | Лекарство | Срочность |
|---|---|---|---|---|
| A. Чтение ядра (`identity`, `partner`, `auth`, `catalog`) | 31 | `rides/delivery/education → identity.users`, `* → marketplace.partners` | Контракты ядра: `PartnerDirectory` (есть), `UserDirectory`/`ConsumerDirectory` (нет) | Низкая: направление верное |
| B. Admin → любые таблицы (включая ядро) | 44 | `admin → food_*` (14), `leisure_*` (11), `auto_*` (4), `booking_*` (4), `beauty_*`, `home_service_*`, `grocery_*` | Админ-API внутри домена (`<Domain>AdminApi` в модуле домена) или read model; Admin — только маршрутизация и права | **Высокая** |
| C. Движок → вертикали (обратные рёбра) | 4 | `booking → auto_service_categories/auto_payments`, `booking → health_categories` (прямые рёбра вертикаль → движок, 36 файлов, записаны в `allowed-module-edges.txt` и в baseline не входят) | Убрать обратные рёбра через `BookingCategory`; прямые оставить | Средняя |
| D. Food ↔ Groceries ↔ Delivery ↔ Rides | 15 | `groceries → food_*` (11), `food → grocery_categories`, `food → delivery_couriers`, `delivery → rides`, `rides → deliveries` | Один сервис «food family»; для Mobility — порт `ActiveWork`/`RideRouting` | Средняя |
| E. Демо-сиды | 8 | `PartnerOpsDemoSeeder` (7: `food_restaurants`, `booking_venues`, `identity.*`), `LeisureDemoSeeder → partners` (1) | Перенос сидов в `backend/app` | **Высокая** (дёшево и рвёт узел циклов) |

Сумма: 31 + 44 + 4 + 15 + 8 = 102. Итого после A…E остаётся «чистое» ядро чтения + Admin через контракты. Группа A **не** блокирует выделение: ядро выделяется последним (или остаётся в монолите).
