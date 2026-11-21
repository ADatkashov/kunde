# KUNDE Leisure & Entertainment 1.0 (DEV/TEST)

Одна доменная модель на существующей платформе (без нового сервиса и без пятого приложения): кинотеатры, боулинг, караоке, квесты, детские центры, батуты, VR, бильярд, концерты, театры, выставки, мастер-классы, экскурсии, активный отдых, семейные развлечения, другое (16 категорий, таблица `marketplace.leisure_categories`).

## Типы бронирования
`TIME_SLOT` (ресурс на время: дорожка, стол), `CAPACITY` (ограниченные места), `SEAT_MAP` (конкретные места), `GENERAL_ADMISSION` (билет без места), `PRIVATE_SESSION` (вся комната/площадка, ёмкость сеанса = 1). Цена: `PER_TICKET` (за человека) или `PER_BOOKING` (за дорожку/комнату; для TIME_SLOT и PRIVATE_SESSION обязательна).

## Данные и целостность (Flyway V40)
`marketplace`: `leisure_categories`, `leisure_venues` (модерация DRAFT→PENDING→APPROVED/REJECTED/BLOCKED), `leisure_events` (DRAFT→PENDING→PUBLISHED/REJECTED/ARCHIVED/BLOCKED), `leisure_ticket_types`, `leisure_sessions`, `leisure_seats`, `leisure_audit` (append-only).
`transactions`: `leisure_holds` + `leisure_hold_lines`, `leisure_orders`, `leisure_tickets`, `leisure_checkins` (append-only), `leisure_order_events` (append-only), `leisure_payments` + `leisure_payment_events` (append-only), `leisure_reviews`, `leisure_favorites`, `leisure_complaints`, `leisure_assignments`.
Деньги — целые тиын (KZT), время — `timestamptz` (сутки считаются по Asia/Almaty).
- **Overselling:** любое изменение запаса сначала берёт `FOR UPDATE` на строку сеанса; занято = живые билеты + активные удержания. Место дополнительно защищено частичным уникальным индексом `leisure_tickets_seat_uq`.
- **Идемпотентность:** `Idempotency-Key` на заказе, `UNIQUE (user_id, idempotency_key)`; параллельные повторы возвращают один заказ.
- **Удержание:** 10 минут, цену считает только сервер из типов билетов.
- **QR:** `KT1.<ticketId>.<128-битный случайный секрет>`; персональных данных нет, секрет сравнивается за постоянное время, строка билета блокируется — два параллельных скана пропустят один раз. Каждый исход (в т.ч. отказ) пишется в `leisure_checkins`. Исходы: `ADMITTED`, `DUPLICATE`, `INVALID`, `WRONG_ORGANIZATION` (без раскрытия данных), `WRONG_SESSION`, `CANCELLED`, `NOT_CONFIRMED`, `EXPIRED`, `TOO_EARLY` (вход за 2 ч до начала).

## API
Публично (пусто при выключенном флаге): `GET /api/v1/leisure/categories|home|events|events/{id}|events/{id}/sessions|events/{id}/reviews|sessions/{id}/seats`.
Consumer: `POST /leisure/sessions/{id}/holds`, `GET|DELETE /leisure/holds/{id}`, `POST /leisure/orders` (Idempotency-Key), `GET /leisure/orders[?scope=upcoming|completed|cancelled]`, `GET /leisure/orders/{id}`, `POST …/cancel`, `POST …/review`, `PUT|DELETE /leisure/favorites/{eventId}`, `POST /leisure/complaints`.
Partner `/api/v1/partner/partners/{id}/leisure/…`: venues, events, ticket-types, sessions, orders (+`action` CONFIRM/REJECT/CANCEL), `checkins`, `stats`, `history`, assignments. Роли: OWNER/MANAGER управляют каталогом и отменяют, OPERATOR (Staff) видит брони, подтверждает/отклоняет и проверяет билеты.
Admin `/api/v1/admin/leisure/…` (грант `LEISURE_OPERATIONS`): summary, venues/events + `decision`, categories, orders (+cancel), tickets, payments (+refund), complaints (+resolve), reviews/hide, audit.
Executor `/api/v1/executor/leisure/assignments` (+`step` ACCEPT/DECLINE/START/COMPLETE/CANCEL) — только для событий с `needs_executor` (экскурсии, мастер-классы, активный отдых).

## Оплата
Только DEV/TEST: `TEST_CARD` (запись в леджер HOLD→CAPTURE→REFUND/VOID, без данных карты и без списаний) и `PAY_ON_SITE` (без движения). Возврат: полный при отмене, полный/частичный админом. Реальный провайдер, Apple/Google Pay и банковские карты **не** подключены — их нет и в UI.

## Флаг `LEISURE_ENABLED`
Пусто = включён в `local|dev|test`, выключен в production (явное `true` вне dev/local/test — отказ при старте). Админ может выключить/включить во время работы (`/admin/features/LEISURE`, V40 расширяет `feature_toggles`). Выключено: каталог пуст, новые holds/orders/venues/events/sessions → `409 LEISURE_DISABLED`; существующие заказы читаются и отменяются, данные не удаляются. `GET /capabilities` → `leisureEnabled`.

## Демо-данные
`LEISURE_SEED_DEMO=true` (только dev/local/test, идемпотентно): 9 синтетических площадок у двух демо-партнёров, все названия помечены «синтетика», фото нет (приложение рисует иллюстрацию по категории).

## Проверка
- Backend: `mvn test` на PostgreSQL 16 (348 тестов до Executor; `LeisureApiIntegrationTest` 8, `LeisureFlagOffIntegrationTest` 1, `LeisureConcurrencyIntegrationTest` 3 — гонка за последнее место, одно кресло, повтор оплаты с одним ключом).
- Flutter: mobile 269 тестов, partner_app 114 (сценарий покупки мест до QR, занятое место, потеря сети, флаг выключен, RU/KK/EN × текст 100/200%).
- DEV: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com` → `SMOKE OK` (2026-11-20, main `e0039ce`, deploy `dep-dc09vk6tlv9c739ka4dg`): hold с серверной ценой, конфликт места, заказ + идемпотентный повтор, QR без ПД, отказ Apple Pay, чужой заказ 404, скан партнёром, `INVALID`, статистика, отмена с возвратом и освобождением места.

## Не проверено / ограничения
Нативный E2E на эмуляторе и скриншоты для сверки с референсом, TalkBack на устройстве, карта (нет картографического провайдера), загрузка фото (только https-ссылки), push-уведомления, реальные платежи, PROD (флаг выключен). Linear не синхронизирован (коннектор недоступен в сессии).
