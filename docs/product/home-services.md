# KUNDE «Дом и быт»

Home Services использует общий Booking Engine. Новый справочник классифицирует работы. Цена, длительность и наличие слотов должны определяться на уровне предложения партнёра и его расписания. V60 публикует классификацию без выдуманных тарифов и доступности.

| Компонент | Состояние после аудита main 6349b13 | Переиспользование и работа |
| --- | --- | --- |
| Каталог | Уборка с тремя синтетическими услугами, категория CLEANING | V60 добавляет 8 категорий и 55 наименований RU/KK/EN, активность и порядок. Описания, фото, региональные правила и связь с предложениями открыты. |
| Booking | Живое сохранение, слоты, вычисление по площади, отмена, ограничения пересечений, идемпотентность и доступ владельца | Сохранить таблицы, интервалы и ограничения. Добавить подтверждение партнёра, переназначение и приёмку клиентом. |
| Pricing и Payments | Уборка рассчитывается на сервере по площади, подтверждение синтетическое, оплата на месте | Сверить сценарий согласованной цены с Auto и состояние присоединяемого платёжного ledger. Credentials нужны для проверок реального провайдера. |
| Partner | Общие партнёры, членство, бронирования и управление ресурсами | Добавить собственные предложения, районы и управление расписанием и исполнителями для Home Services. |
| Executor | Роль и экраны существуют для других вертикалей | Добавить назначения, проверки доступа и переходы для Home Services. |
| Admin | Общие гранты и переключатели, отдельные операционные панели вертикалей | V59 добавляет аудируемый переключатель. V61 добавляет управление категориями через Admin API. Редактор Admin Flutter использует V61. Модерация предложений открыта. |
| Consumer | Плитка, раздел, форма уборки, история | V59 добавляет серверный флаг для входов. Требуются поиск по предложениям, карточки, оформление и статус выполнения. |
| Сопровождение | Общие компоненты уведомлений и поддержки, примеры отзывов в других вертикалях | Нужны доменные события, отзывы и споры с разграничением доступа. |
| Инфраструктура | CI, Release APK workflows, Render DEV, Neon PostgreSQL 16 | Neon DEV проверен чтением Flyway V58. Миграции V59/V60 проверены локально. Приёмка на DEV и подписанные сборки Home Services открыты. |

## API справочника

`GET /api/v1/home-services/categories` возвращает активные категории по порядку отображения. `GET /api/v1/home-services/definitions` возвращает активные наименования из активных категорий. Для определений поддерживается точный фильтр `category`. Оба списка поддерживают `limit` от 1 до 50 и `offset` от 0 до 10000. При выключенном флаге возвращается `404 HOME_SERVICES_DISABLED`.

Коды стабильны и не зависят от языка. Отдельные строки занесены в PostgreSQL. Выдача справочника не означает доступность работ в городе. Слоты и существующий пилот уборки продолжают обслуживаться в [Booking API](booking-mvp.md).

## Проверка

На локальном PostgreSQL 16 проверены переход Flyway с V59 на V60, пагинация, локализованные имена, скрытие неактивной категории и запрет работы справочника при выключенном флаге. Команда `cd backend && mvn -Dtest=BookingApiIntegrationTest,DomainSchemaOwnershipIntegrationTest test`.

## Управление категориями

Сотрудник с грантом `HOME_SERVICES_CATALOG` может читать все категории через `GET /api/v1/admin/home-services/categories` и сохранять категорию через `PUT /api/v1/admin/home-services/categories/{code}`. Для создания передаётся `expectedVersion: 0`, для обновления — текущая версия. Конфликт версии возвращает `409`. Смена сохраняется в одной транзакции с записью аудита. Деактивация скрывает категорию и её наименования из публичной выдачи. Администратор может подготовить справочник до включения пилота.

На PostgreSQL 16 прошли `FeatureTogglesApiIntegrationTest` и `DomainSchemaOwnershipIntegrationTest` (15 тестов). Проверены отсутствие доступа без гранта, создание, деактивация, конфликт версии и история аудита.

## Модерируемые предложения (V69)

Предложение — это существующая услуга Booking (`booking_services` площадки категории `CLEANING`), отнесённая к определению справочника и прошедшая модерацию. Цена, длительность и слоты остаются в Booking Engine; предложение добавляет модель цены (`FIXED`, `FROM`, `HOURLY`, `PER_SQM`, `PER_UNIT`, `DIAGNOSTIC`, `QUOTE`), выезд на дом и гарантию в днях (0–1095). Гарантия не подразумевается по умолчанию: `warrantyDays = 0`.

Состояния: `DRAFT → PENDING` (партнёр, `SUBMIT`), `PENDING → PUBLISHED | REJECTED` (сотрудник, `APPROVE`/`REJECT`), `PUBLISHED ⇄ SUSPENDED` (сотрудник, `SUSPEND`/`RESTORE`), `PENDING | PUBLISHED → DRAFT` (партнёр, `WITHDRAW`), `REJECTED → PENDING` (повторная подача). Допустимость перехода, версия и роль проверяются в одном месте (`HomeServiceOffers`); каждое изменение пишет неизменяемое событие в `home_service_offer_events` (роль, прежний и новый статус, причина).

| Метод и путь | Доступ | Назначение |
| --- | --- | --- |
| `GET /api/v1/home-services/offers?category=&definition=&limit=&offset=` | публично, при включённом флаге | Только `PUBLISHED` предложения открытых площадок и доступных услуг; `limit` 1–50 |
| `GET/POST /api/v1/partner/partners/{partnerId}/home-services/offers` | список — активный сотрудник одобренного партнёра; запись — `OWNER`/`MANAGER` | Список своих предложений; создание (`DRAFT`) только для услуги собственной площадки партнёра |
| `POST …/offers/{offerId}/transition` | то же | `SUBMIT` или `WITHDRAW` с `expectedVersion`; чужое предложение даёт `404 OFFER_NOT_FOUND` |
| `GET /api/v1/admin/home-services/offers?status=` | грант `HOME_SERVICES_CATALOG` | Очередь модерации, работает при выключенном флаге |
| `POST /api/v1/admin/home-services/offers/{offerId}/decision` | тот же грант | `APPROVE`, `REJECT`, `SUSPEND`, `RESTORE` с `expectedVersion` и причиной от 3 символов |

Права партнёра проверяются через публичный технический порт `kz.kunde.platform.partner.PartnerDirectory` (ADR-021, Конституция §4), а не импортом `partner.*`: список — `isActiveStaffOfApprovedPartner`, запись — `lockCatalogManager` внутри транзакции записи (общая блокировка партнёра и членства: приостановка партнёра или отзыв сотрудника ждёт и не теряется). Какие роли управляют предложениями (`OWNER`, `MANAGER`; `OPERATOR` только читает) решает Partner в `JdbcPartnerDirectory`. Принадлежность площадки партнёру — данные Booking (`booking_venues.partner_id`) и читается по записанному ребру `homeservices → booking`. Не участник одобренного партнёра получает `404 PARTNER_NOT_FOUND`, участник без полномочия — `403 PARTNER_ROLE_FORBIDDEN`. Baseline границ не расширялся.

Коды ошибок: `PARTNER_NOT_FOUND` (404), `PARTNER_ROLE_FORBIDDEN` (403), `VERSION_CONFLICT` и `INVALID_TRANSITION` (409), `OFFER_EXISTS` (409), `SERVICE_NOT_FOUND` и `OFFER_NOT_FOUND` (404), `DEFINITION_INACTIVE` (422), `REASON_REQUIRED` и `PRICING_MODEL_INVALID` (400).

Ограничения: смена цены или доступности уже опубликованной услуги идёт через существующий Booking API партнёра и повторную модерацию не запускает; фотографии, районы обслуживания, мастера и коммерческая модель комиссии пока не входят. Экраны (Flutter, локально проверены `flutter analyze --fatal-infos` и `flutter test`): Consumer — «Мастера и услуги» (каталог предложений, карточка, постатейная котировка с учётом срочности и площади; кнопка «Заказать» пока ведёт в существующий поток уборки); Partner — «Дом и быт: мои услуги» (список, подача и отзыв, только `OWNER`/`MANAGER`; иконка в шапке при `homeServicesEnabled`); Admin — очередь модерации (`HOME_SERVICES_CATALOG`). Partner также создаёт черновик предложения (площадка `CLEANING` → услуга → вид работ → модель цены → выезд, гарантия). Открыто: редактирование зон и тарифов в Partner, заказ по конкретному предложению, мастера и назначение.

Проверка: `cd backend && ./gradlew :app:test --tests '*HomeServicesOffersApiIntegrationTest'` на PostgreSQL 16 (`DB_USERNAME=postgres`).

## Зоны обслуживания, тарифы и расчёт (V70)

Зона — круг (центр, радиус 300 м – 100 км) площадки `CLEANING`. Площадка без активных зон обслуживает весь город; с зонами адрес должен лежать в одной из них (расстояние — `platform.geo.Geo`). Тариф предложения — выездной сбор, надбавка за срочность и вечернюю надбавку (процент от цены, время «вечера» задаёт партнёр); тариф действует только у опубликованного предложения.

Цену считает один метод (`HomeServicePricing.charges`): Booking Engine вызывает его через хук `BookingCategory.surchargeMinor` при создании записи, публичная котировка — при запросе, поэтому котировка и запись не расходятся. Список цен остаётся в Booking (`BookingSlots.Service.listPriceMinor`); `BookRequest` получил необязательные `latitude`, `longitude`, `urgent`, прежние клиенты не меняются. Для `CLEANING` теперь проверяется и `expectedPriceMinor`, если он передан (`409 BOOKING_PRICE_CHANGED`).

| Метод и путь | Доступ | Назначение |
| --- | --- | --- |
| `GET /api/v1/home-services/offers/{offerId}/quote?areaSqm=&startsAt=&lat=&lng=&urgent=` | публично, при включённом флаге | Постатейная цена опубликованного предложения; `404 OFFER_NOT_FOUND` для остальных |
| `GET/POST /api/v1/partner/partners/{partnerId}/home-services/zones`, `PUT …/zones/{zoneId}` | чтение — персонал; запись — `OWNER`/`MANAGER` | Зоны своих площадок; `expectedVersion`, `active=false` выводит зону из работы |
| `PUT /api/v1/partner/partners/{partnerId}/home-services/offers/{offerId}/tariff` | `OWNER`/`MANAGER` | Тариф; `expectedVersion` 0 создаёт, иначе версия должна совпасть |

Коды: `LOCATION_REQUIRED` и `OUT_OF_ZONE` (422), `LOCATION_INVALID` (400), `ZONE_NOT_FOUND`, `VENUE_NOT_FOUND`, `OFFER_NOT_FOUND` (404), `VERSION_CONFLICT` (409). Публичный каталог и котировка показывают только предложения партнёров со статусом `APPROVED` (`PartnerDirectory.approvedPartnerIds`); приостановка партнёра скрывает их сразу, восстановление возвращает. Открыто: мастера и графики используют существующие `booking_masters`/`booking_working_hours` без изменений; полигональные зоны и районы — позже.

## Визит мастера (V71)

Мастер (Executor) ведёт визит; клиент видит ход работ. Статусы брони остаются статусами Booking Engine (`CONFIRMED → IN_PROGRESS → COMPLETED`); «в пути» и «на месте» уточняют `CONFIRMED` и хранятся в `home_service_visits` (владелец — Home Services). Мастер — запись `booking_masters`, привязанная к аккаунту по одноразовому коду-приглашению; чужую бронь он видит как `404 JOB_NOT_FOUND`.

| Метод и путь | Доступ | Назначение |
| --- | --- | --- |
| `POST /api/v1/executor/home-services/link` `{code}` | аккаунт | Привязка к мастеру по коду; `404 INVITE_INVALID` |
| `GET /api/v1/executor/home-services/jobs` | привязанный мастер | Свои работы на 7 дней вперёд (`CONFIRMED`, `IN_PROGRESS`) со стадией и ETA |
| `PUT …/jobs/{id}/stage` `{stage: EN_ROUTE\|ARRIVED, etaMinutes?}` | мастер брони | «В пути» (ETA можно обновлять), затем «на месте» |
| `POST …/jobs/{id}/start`, `…/complete` | мастер брони | Начать только после «на месте»; завершить только начатую |
| `GET /api/v1/home-services/bookings/{id}/visit` | клиент брони | Статус, стадия и ETA; чужая бронь — `404` |

Нарушение порядка даёт `409 JOB_STATE_INVALID`; при выключенном флаге — `404 HOME_SERVICES_DISABLED`. Consumer показывает ход визита в карточке брони (`HomeServiceVisitCard`, обновление раз в 15 с), Executor — экран «Дом и быт: мои заказы» (привязка по коду, выезд с ETA, прибытие, старт, завершение). Если Executor передаёт позицию мастера, ETA считает сервер по дорожному маршруту KUNDE Maps (`RoutingProvider`: адрес брони геокодируется; синтетические маршруты, сбой и отсутствие провайдера не показываются как реальные), иначе остаётся ETA, введённый мастером. Роли используют уже разрешённое ребро `homeservices → booking`; baseline не расширялся. Проверка: `cd backend && ./gradlew :app:test --tests '*HomeServicesVisitApiIntegrationTest'` на PostgreSQL 16 (локально не запускалось: нет Docker; проверяет CI).

## Мастера партнёра и коды-приглашения (H1, 2026-11-27)

Партнёр сам заводит мастеров своих площадок `CLEANING` и выдаёт им одноразовый код для Executor (раньше мастера появлялись только из демо-сидера: `createPost` в Booking работает только для AUTO). Мастер — ресурс Booking Engine (`booking_masters`): новый мастер получает все услуги площадки и график пн–сб 09:00–18:00, изменения пишутся в журнал каталога партнёра через порт `PartnerDirectory.recordCatalogChange`.

| Метод и путь | Доступ | Назначение |
| --- | --- | --- |
| `GET /api/v1/partner/partners/{partnerId}/home-services/masters` | активный сотрудник одобренного партнёра | Активные мастера; код виден, пока мастер не привязал аккаунт |
| `POST …/masters` `{venueId, name}` | `OWNER`/`MANAGER` | Создать мастера и код `HXXXX-XXXXX`; не более 50 активных на площадку (`409 TOO_MANY_MASTERS`) |
| `POST …/masters/{masterId}/invite` | `OWNER`/`MANAGER` | Выдать новый код (старый перестаёт работать); `409 MASTER_LINKED`, если аккаунт уже привязан |
| `POST …/masters/{masterId}/deactivate` | `OWNER`/`MANAGER` | Вывести мастера из работы; `409 MASTER_HAS_BOOKINGS`, пока есть открытые брони |

Коды ошибок: `PARTNER_NOT_FOUND`, `VENUE_NOT_FOUND`, `MASTER_NOT_FOUND` (404), `PARTNER_ROLE_FORBIDDEN` (403), `NAME_INVALID` (400). Мастер привязывается кодом в Executor (`POST /executor/home-services/link`). Проверка: `cd backend && ./gradlew :app:test --tests 'kz.kunde.homeservices.HomeServicesMastersApiIntegrationTest'`. Экран Partner: «Дом и быт → Мастера и коды» (`apps/partner/lib/features/home_services/home_services_masters_screen.dart`): список с кодом (копирование), новый мастер, новый код, вывод из работы с подтверждением; роли без права управления видят только список.
