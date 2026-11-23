# Database sharding readiness (по городам)

Дата аудита: 2026-11-23, `main` @ `3e92f47` (backend: 262 Java-файла, 62 миграции до этой задачи, 133 таблицы). Основание — исходный код и миграции, а не ADR.
Решение не меняется: **один Spring Boot backend, один PostgreSQL** ([ADR-001](adr/ADR-001-backend-architecture-style.md), [microservice-readiness](microservice-readiness.md)). Этот документ описывает, как подготовить данные к будущему разделению по городам, что сделано сейчас и чего делать нельзя без решений владельца.

> **Вывод: система НЕ готова к физическому sharding.** Сделан только фундамент (Phase 1). Блокеры перечислены в разделе 5; пока они открыты, переносить город в отдельную БД нельзя.

## 1. Что было до изменений (факты из кода)

- **Понятия города нет.** Ни таблицы городов, ни `city_id`. Единственные следы: `marketplace.education_courses.city` (свободный текст `varchar(100)`, фильтр `lower(city)=lower(:city)` в `EducationCatalogController`), `region_code` в админ-грантах (`identity.admin_role_assignments`, `AdminGrants.Scope`) и `timezone` по умолчанию `Asia/Almaty` у площадок. Зон обслуживания (`serviceability.zones`) нет в данных: V3 намеренно ничего не включает.
- **В API нет городского контекста**: ни одного `@RequestHeader` с городом, ни параметра `cityId` (кроме текстового фильтра образования). Значит «подмена города» сейчас невозможна, и задача — не допустить её появления (тест, раздел 8).
- Заказы привязаны к партнёрской точке (`food_orders.restaurant_id`, `bookings.venue_id`, `leisure_orders.venue_id`), поездки и доставки (`rides`, `deliveries`) — только к координатам, без привязки к месту.
- Один PostgreSQL, шесть схем + `serviceability`; JDBC без ORM, ~280 `@Transactional`; событий/outbox нет; два `@Scheduled` (оба в `delivery/DeliveryMaintenance`).
- 65 внешних ключей на `identity.users`, 6 на `marketplace.partners` (список — `DomainSchemaOwnershipIntegrationTest`).
- Helm-чарт есть (`replicaCount: 2`, `maxUnavailable: 0`, startup/liveness/readiness-пробы, PDB); HPA нет. DEV — Render + Neon, `DB_POOL_SIZE=5`.

## 2. Целевая архитектура

```text
Flutter apps → LB/Gateway → Backend pods (stateless)
                                   │
                         Domain services (модули монолита)
                                   │  ShardResolver (ShardKey → ShardLocation)
              ┌────────────────────┼─────────────────────┐
        Global PostgreSQL     Shard "almaty"        Shard "other"
   identity, users, partners,   food/booking/rides/    остальные города
   cities (+shard_id), flags    delivery/leisure/…
```

Сейчас существует только логический shard `default` = текущая БД. Физические shards, дополнительные `DataSource`, Kafka и Redis **не создаются**.

## 3. Три разных понятия

| Понятие | Статус в KUNDE | Решение |
|---|---|---|
| `tenant_id` | Multi-tenancy как изоляция арендаторов в продукте не обнаружена (изоляция — по партнёру: `partner_staff`, гранты) | **Не вводится.** Город не называем tenant-ом |
| `city_id` | Город оказания услуги; ключ размещения операционных данных | Вводится как nullable `uuid` на корнях агрегатов (V63) |
| `shard_key` | `ShardKey(domain, scope, cityId)` — логическая адресация | Только в коде (`platform.placement`), в таблицах не хранится; shard города — `serviceability.cities.shard_id` |

`city_id` **не механизм авторизации**: доступ определяется владельцем/ролью/грантом, `city_id` только отвечает «где лежат данные».

## 4. Матрица владения данными (global vs city-scoped)

Единый источник — `backend/src/test/resources/architecture/placement-registry.txt` (тест `PlacementRegistryTest` падает на любой таблице без класса). Классы: **GLOBAL**, **CITY_ROOT** (корень агрегата, несёт `city_id`), **CITY_CHILD** (размещение через FK корня, своей копии нет), **EXECUTOR** (исполнитель работает в нескольких городах), **UNDECIDED** (код не даёт ответа; блокер).

| Область | Класс | Корень размещения / комментарий |
|---|---|---|
| Identity, auth, профиль, адреса, согласия, админ-гранты, feature toggles | GLOBAL | Пользователь работает в любых городах; адрес редактируется свободно и **не** определяет размещение старых заказов |
| Партнёры, сотрудники, каталог категорий/офферов | GLOBAL | Партнёр — одна организация с филиалами в разных городах |
| Реестр городов `serviceability.cities` | GLOBAL | Содержит `shard_id` |
| Food: рестораны, меню, заказы, отзывы, акции, курьерские задачи | CITY_ROOT `food_restaurants` | Заказ наследует город ресторана |
| Booking/Health/Home services: площадки, мастера, услуги, записи | CITY_ROOT `booking_venues` | Запись наследует город площадки |
| Auto: roadside-заявки | CITY_ROOT `auto_jobs` | Город точки поломки |
| Leisure/Events: площадки, сеансы, заказы, билеты | CITY_ROOT `leisure_venues` | |
| Education: курсы, потоки, записи, сертификаты | CITY_ROOT `education_courses` | Свободный текст `city` остаётся только витринным полем, не ключом |
| Rides | CITY_ROOT `rides` | Город точки подачи; события/офферы/оценки — дети |
| Delivery | CITY_ROOT `deliveries` | Город точки забора |
| Водители, курьеры, автомобили, автопарки, специалисты | EXECUTOR | Глобальная личность, доступность по городам — будущая работа |
| Платежи (`auto_payments*`, `leisure_payments*`, `education_payment_events`) | **UNDECIDED** | Отдельного Payments-домена нет; финансовая целостность важнее городской локальности |
| `support.*` | **UNDECIDED** | Обращение глобально по пользователю, но FK на `rides`/`deliveries` |
| `ride_fare_quotes`, `delivery_quotes` | **UNDECIDED** | Котировка существует до строки поездки/доставки; нужен свой `city_id` или TTL |
| `food_favorites`, `grocery_*` (корзина/списки/избранное) | **UNDECIDED** | Пользовательские данные поверх блюд ресторанов из разных городов |
| `auto_roadside_tariffs` | **UNDECIDED** | Тарифы по городам различаются, правила нет |
| Wallets, Loyalty, Subscriptions, Chat, Notifications, Search, Analytics | — | В коде отсутствуют (подтверждено [microservice-readiness](microservice-readiness.md) п.4): классифицировать нечего |

Cross-City заказы: **в коде не существуют** (каждый заказ — одна площадка = один город). Явное правило на будущее: заказ принадлежит городу корня и не может сочетать позиции разных городов; межгородская операция — это два отдельных агрегата, связанных мягкой ссылкой, без распределённой транзакции.

## 5. Блокеры физического sharding (подтверждены кодом/схемой)

| # | Блокер | Где | Что нужно (не сделано) |
|---|---|---|---|
| B1 | **Города не существуют как данные**, `city_id` у всех существующих строк NULL | вся схема | Решение владельца: список городов, правила определения города (по зоне/адресу площадки/координате). Backfill **не выполнен** |
| B2 | 65+6 внешних ключей из операционных таблиц на `identity.users`/`marketplace.partners` | см. `DomainSchemaOwnershipIntegrationTest` | При физическом разделении FK на глобальную БД невозможны → «мягкие» ссылки + проверка существования в приложении |
| B3 | `support.cases` ссылается FK на `rides` и `deliveries` | `V6`, support | Мягкая ссылка + тип/ID субъекта |
| B4 | Глобальные инварианты: `UNIQUE rides_one_pending_per_customer(user_id)`, `deliveries_active_courier(courier_id)`, `food_restaurants.slug`, `booking_venues.slug`, `leisure_venues.slug` | миграции V22, V28, V15, V18, V40 | Решить: инвариант на уровне города (допустимо) или глобальный реестр/lock. Сейчас пользователь теоретически мог бы иметь по одной активной поездке в каждом городе |
| B5 | Цикл `delivery ↔ rides` и SQL «занят ли исполнитель» через обе таблицы | microservice-readiness V2 | Интерфейс занятости исполнителя в `platform` |
| B6 | Платежи/возвраты без домена и владельца | `*_payments` | Решение по Payments (отдельная глобальная БД платежей vs по городу) |
| B7 | Транзакции через домены: `groceries → FoodOrderService` (одна БД-транзакция); `delivery/rides → support` SQL | microservice-readiness V3/V7 | Для Groceries допустимо (тот же shard, что Food); остальное — контракты/события |
| B8 | Executors: поиск ближайшего водителя/курьера читает координаты по всем городам | `RideDispatchService`, `DeliveryDispatch` | Диспетчер должен получать `ShardKey` заявки и искать исполнителей в её shard-е; модель «исполнитель в нескольких городах» не определена |
| B9 | Фоновые задачи без контекста размещения | `DeliveryMaintenance` (опрашивает все `SEARCHING_COURIER`) | Итерация по городам/shard-ам |
| B10 | Нет outbox/событий | — | Нужен до CDC-переноса (ADR-006), не внедрялся |

Пока B1–B4, B6 не закрыты, объявлять систему готовой к sharding нельзя.

## 6. Что сделано в этой задаче (Phase 1)

1. **Миграция `V63__city_placement_registry.sql`** (только expand, совместима с DEV и с откатом приложения):
   - `serviceability.cities` — глобальный реестр (`code`, `country_code`, `name`, `timezone`, `shard_id default 'default'`, `enabled default false`). **Пустая**: список городов — решение владельца, ничего не засеяно.
   - nullable `city_id uuid REFERENCES serviceability.cities` на 7 корнях: `food_restaurants`, `booking_venues`, `leisure_venues`, `education_courses`, `rides`, `deliveries`, `auto_jobs`. `ADD COLUMN` без default — изменение каталога без перезаписи таблицы.
   - триггер `serviceability.forbid_city_change()`: города можно присвоить (NULL → значение), но нельзя изменить или обнулить. Перенос города — только контролируемая миграция (отключить триггер на время окна, см. п.11).
   - частичные индексы `WHERE city_id IS NOT NULL` только на малых каталогах; на `rides/deliveries/auto_jobs` индекс **намеренно не создан** — его строят `CREATE INDEX CONCURRENTLY` вместе с backfill, а не внутри транзакционной миграции Flyway.
   - Backfill: **нет**. Существующие строки остаются `city_id IS NULL` («unplaced»), ничего не подставляется.
2. **`kz.kunde.platform.placement`** (`ShardKey`, `ShardLocation`, `ShardResolver`, `SingleShardResolver`, `PlacementLocator`, `SqlPlacementLocator`, `PlacementService`). `SingleShardResolver` всегда отвечает `default`. Нет ThreadLocal: ключ передаётся параметром, поэтому нет утечек контекста между потоками пула, `@Async` и `@Scheduled`. Будущий мульти-shard резолвер **обязан** отказывать для `UNPLACED` (fail-closed).
3. **Локаторы агрегатов в доменах** (`FoodPlacement`, `BookingPlacement`, `LeisurePlacement`, `EducationPlacement`, `RidesPlacement`, `DeliveryPlacement`, `AutoPlacement`): «по ID записи найти город» из **хранимых данных**, а не из выбранного пользователем города. Они не подключены ни к одному эндпоинту — это инфраструктура; существующие API и ответы не менялись.
4. Тесты и CI — раздел 8.

Что намеренно **не** делалось: перенос `city` образования в `city_id` (нужен справочник городов и сопоставление), `city_id` на `ride_fare_quotes`/`delivery_quotes` (триггер неизменяемости квот и UNDECIDED), любые изменения публичного API, DataSource/реплики/Kafka/Redis.

## 7. Миграция существующих данных (план backfill, не выполнен)

Expand → backfill → validate → contract:

1. **Expand** — V63 (выполнено).
2. **Решение владельца** — список городов и правила (B1). Заполнить `serviceability.cities` отдельной утверждённой миграцией/операцией.
3. **Backfill небольшими пачками**, идемпотентно, вне Flyway-транзакции: для площадок — по адресу/координате площадки; для `rides`/`deliveries`/`auto_jobs` — по координате точки подачи/забора (нужен утверждённый справочник границ). Для образования — сопоставление `lower(city)` со справочником; несопоставленные значения остаются NULL. Пример отчёта исключений для образования (read-only):
   ```sql
   SELECT city, count(*) FROM marketplace.education_courses
   WHERE city_id IS NULL GROUP BY city ORDER BY count(*) DESC;
   ```
   Аналогично: `SELECT count(*) FROM transactions.rides WHERE city_id IS NULL;`. Строки, город которых определить нельзя, не угадываются; они попадают в отчёт на ручной разбор.
4. **Validate** — `SELECT count(*) … WHERE city_id IS NULL` по всем корням = 0 (или явно согласованный остаток), `CONSTRAINT … CHECK (city_id IS NOT NULL) NOT VALID` затем `VALIDATE CONSTRAINT`.
5. **Contract** — `SET NOT NULL` только после `VALIDATE`; приложение начинает присваивать `city_id` при создании корня; индексы `CONCURRENTLY` на крупных таблицах.

Откат каждого шага: колонка nullable и не используется кодом до шага 5, поэтому откат приложения не требует отката схемы; `DROP COLUMN` возможен до contract-фазы.

## 8. Безопасность и изоляция

- Город **никогда** не принимается из заголовка как владелец записи. Тест `PlacementRegistryTest.noEndpointTakesTheOwningCityFromARequestHeader` падает, если появляется `@RequestHeader(...city...)`/`getHeader("...city")`.
- `PlacementService.belongsToCity(aggregate, id, claimedCity)` только **сравнивает** заявленный город с хранимым и возвращает `false` при подмене, отсутствии, неразмещённой или несуществующей записи.
- Размещение не даёт доступа: проверки владельца заказа, членства партнёра (`partner_staff`) и грантов `AdminGrants` остаются обязательными и не менялись. Регион в админ-грантах (`region_code`) — отдельное поле scope, его связь с `cities.code` требует решения.
- Fail-closed: `ShardKey` отвергает неконсистентные комбинации, `PlacementService` падает на неизвестном агрегате.

## 9. Тесты (что и чем доказано)

| Требование | Тест |
|---|---|
| Пользователь в нескольких городах; заказы городов не смешиваются | `CityPlacementIntegrationTest.ordersOfDifferentCitiesStayInTheirCityAndOneUserCanOrderInBoth` |
| Смена адреса/города не двигает старый заказ | `…changingTheUsersAddressOrCityDoesNotMoveAnExistingOrder` |
| Партнёр с филиалами в нескольких городах | `…partnerBranchesInSeveralCitiesAreAddressedIndependently` |
| Определение владельца по ID; неразмещённые не угадываются | `…unplacedRecordsAreReportedAsUnplacedNotGuessed`, `PlacementServiceTest` |
| Неизменяемость ключа; конкуренция (ровно один победитель) | `…placementKeyIsImmutableOnceAssignedButCanBeAssignedOnce`, `…concurrentAssignmentOfTwoCitiesToOneRecordHasExactlyOneWinner` |
| Свободный текст `city` не влияет на ключ | `…educationFreeTextCityDoesNotChangeThePlacementKey` |
| `SingleShardResolver` → `default`; подмена/отсутствие города | `PlacementServiceTest` |
| Миграция на чистой схеме, пустой реестр, ничего не засеяно | `…migrationStartsWithNoCitiesAndNoInventedPlacement`, `DomainSchemaOwnershipIntegrationTest`, `PlatformMigrationIntegrationTest` |
| Каждая таблица классифицирована; корни имеют `city_id` и триггер; дети не дублируют; UNDECIDED объяснён | `PlacementRegistryTest` (быстрый, без БД) |
| Нет запрещённых зависимостей | `ArchitectureBoundariesTest` (baseline не менялся) |

Исполнитель, сменивший город (п.4 задания), в схеме не выражается: поездка хранит город подачи (корень), а исполнитель — EXECUTOR без городской привязки. Отдельный тест не добавлен, т.к. модель «город исполнителя» не определена (B8); это зафиксировано как блокер, а не имитировано.

CI: быстрый шаг `Architecture boundaries (fast, no database)` в `backend.yml` теперь запускает также `PlacementRegistryTest` и `PlacementServiceTest` (секунды, без БД). Интеграционные тесты идут в существующем `mvn verify`. Политика обязательных/ручных проверок и security gates не менялась.

## 10. Масштабирование PostgreSQL помимо sharding

**Пулы соединений.** `application.yml`: `maximum-pool-size = DB_POOL_SIZE` (по умолчанию 10, DEV Render — 5), `connection-timeout 3000`; `max-lifetime`/`idle-timeout`/`leak-detection` не заданы (значения Hikari по умолчанию). Нагрузка на БД = pods × pool:

| Pods | pool 5 | pool 10 |
|---|---|---|
| 5 | 25 | 50 |
| 10 | 50 | 100 |
| 20 | 100 | 200 |
| 50 | 250 | 500 |

Лимит `max_connections` зависит от тарифа Neon — **проверить в консоли**, в репозитории числа нет. Рекомендации: для >5 pod-ов использовать pooled-эндпоинт Neon (PgBouncer, transaction mode) для приложения и **direct** (non-pooled) только для Flyway (`modules/neon/outputs.tf` это уже различает); при pooled-режиме отключить server-side prepared statements (`prepareThreshold=0`); не использовать `pg_advisory_xact_lock` вне транзакции (он используется в идентичности/Groceries внутри `@Transactional` — совместимо с transaction pooling). Размер пула считать от `max_connections / pods` с запасом на Flyway и админ-доступ. Значения не менялись.

**Read replicas (рекомендация, не включено).** Первыми кандидатами на чтение с реплики — публичные каталоги (food/booking/leisure/education каталоги, поиск). Заказы/платежи/статусы сразу после записи читать только с primary (read-after-write). Для пользовательского «мои заказы» после создания — читать с primary в течение N секунд или передавать LSN/метку. Механизм маршрутизации появится вместе с `ShardResolver` (отдельный `DataSource` на shard), поэтому сейчас не вводится.

**Транзакции и гонки (проверено в коде).** Идемпотентность по `Idempotency-Key` есть у доставки, брони, записи на курс, заказов (UNIQUE `(user_id, key)`). Диспетчеризация доставки берёт `FOR UPDATE` по строке доставки и курьера (`DeliveryDispatch`, `DeliveryTracking`); уникальный частичный индекс `deliveries_active_courier` не даёт назначить курьеру две активные доставки; запись на курс — `FOR UPDATE` по потоку/пользователю. Долгих транзакций с внешними вызовами не обнаружено, но это **не** нагрузочно проверялось.

**Производительность / партиционирование.** Анализ реальных запросов и объёмов не проводился (нет продовых данных) — партиционирование **не внедряется**. Кандидаты по природе роста: `ride_events`, `delivery_events`, `delivery_locations` (уже чистится раз в минуту), `food_order_events`, `auth_events`, `leisure_tickets`; решение — после измерения `pg_stat_user_tables`/`pg_stat_statements` на реальной нагрузке.

## 11. Kubernetes readiness

| Тема | Факт | Рекомендация |
|---|---|---|
| Stateless | JWT, сессий нет, `/tmp` — emptyDir | OK |
| Пробы/shutdown | startup/liveness/readiness в Helm; `server.shutdown: graceful`, `timeout-per-shutdown-phase: 20s` | `terminationGracePeriodSeconds` ≥ 30 s и `preStop` sleep проверить в чарте |
| HPA | нет | Добавить после измерения CPU/латентности; потолок `maxReplicas × pool ≤ max_connections` (п.10) |
| Flyway при нескольких pod-ах | Flyway выполняется при старте приложения; параллельные старты сериализуются блокировкой Flyway | Для production — отдельный migration Job/initContainer на direct-эндпоинте; миграции только expand-совместимые (при rolling update старые pod-ы работают на новой схеме — V63 это соблюдает) |
| Scheduled jobs | `DeliveryMaintenance.updateSearches` (5 с) и `expireLocations` (60 с) выполняются **в каждом pod-е**. Безопасно (`FOR UPDATE` по доставке, удаление идемпотентно), но нагрузка растёт ×N | При >2 pod-ов ограничить лидером: `pg_try_advisory_lock` или Kubernetes CronJob/отдельный worker (`replicaCount` для worker = 1) |
| Shared cache / locks | Кэш `FeatureToggles` — in-process на 5 с; rate-limit — in-process (на pod) | Лимиты считаются на pod, при N pod-ах эффективный лимит ×N; общий Redis не нужен, пока это приемлемо — решение владельца |
| Идемпотентность | есть на ключевых записях | OK |

Helm не расширялся, Render DEV не менялся.

## 12. Перенос города в отдельную БД (будущий план)

Phase 1 — выполнено: один PostgreSQL, логические границы (этот документ, V63).
Phase 2 — пулы/PgBouncer, настройка запросов, реплики **при необходимости** (п.10).
Phase 3 — самый нагруженный город на отдельный PostgreSQL.
Phase 4 — группы городов, реестр shard-ов (`cities.shard_id` + таблица shard-ов с DSN в секретах), инструмент перемещения.
Phase 5 — независимое масштабирование доменов при доказанной необходимости.

Предусловия Phase 3: закрыты B1–B4, B6, B8, B9; backfill выполнен и проверен; FK на глобальные таблицы заменены мягкими ссылками; есть outbox или иной механизм CDC.

Безопасный перенос города X (**zero-downtime не обещается**; доступный механизм — окно ограничения записи):
1. Подготовка: shard-приёмник с той же схемой Flyway; логическая репликация по `city_id = X` для корней и их детей (publication на таблицы корней + дочерние через фильтрацию по родителю или копирование по выборке); глобальные таблицы не копируются, на shard-е нужны их мягкие ссылки.
2. Initial copy + CDC (логическая репликация PostgreSQL) до догона.
3. Сверка: количества и контрольные суммы по таблицам/пачкам, выборочное сравнение заказов; расхождение — стоп.
4. Cutover: включить режим «только чтение»/отклонять записи города X (отдельный флаг на `cities.enabled`/сервисном уровне), дождаться нулевого лага, финальная сверка, `UPDATE cities SET shard_id='x'` (одна запись реестра), включить записи.
5. Откат: до удаления данных в старой БД — вернуть `shard_id='default'` (записи, сделанные на новом shard-е за окно, нужно обратно реплицировать или потерять — поэтому окно записи минимально, а старые данные хранятся до конца окна наблюдения).
6. Только затем — очистка данных города X на `default` отдельным подтверждённым действием.

Для переноса **Алматы** потребуется: утверждённый список городов и backfill (B1), мягкие ссылки вместо FK на users/partners (B2), решение по `support` (B3) и платежам (B6), диспетчер исполнителей по shard-у (B8), перебор shard-ов в фоновых задачах (B9), подключение `PlacementService`/`ShardResolver` к репозиториям через `DataSource`-маршрутизацию (сейчас не подключено ни к одному эндпоинту), тест целостности на копии данных. Terraform apply, PROD-миграции и реальный перенос — только с отдельного явного подтверждения владельца.

## 13. Риски и ограничения

- Backfill невозможен без бизнес-данных: до него `city_id` NULL везде, и все ключи — `UNPLACED`.
- Один `city_id` на корне не выражает исполнителей в нескольких городах и межгородские поездки (в коде их нет).
- Триггер неизменяемости усложняет «исправление ошибки города»: оно делается контролируемой операцией, не обычным UPDATE.
- Пулы/реплики/производительность оценены по коду и конфигурации, нагрузочные тесты не запускались.
- Документ не отражает продовое состояние (PROD нет).
