# KUNDE Events & Tickets 1.0 (DEV/TEST) — разделение с Leisure

## Решение по архитектуре
Аудит 2026-11-21 показал: движок билетов уже существует внутри Leisure 1.0 ([leisure](leisure.md), Flyway V40): сеансы, схемы мест (`SEAT_MAP`), квоты (`GENERAL_ADMISSION`), удержание 10 мин, идемпотентные заказы, `TEST_CARD`, QR `KT1.…` с серверной проверкой и журналом `leisure_checkins`, возвраты, Executor, Partner, Admin. **Второй движок не создаётся.** Events — продуктовое представление этого движка для датированных билетных событий; Leisure — для бронирования активностей.

| Продукт | Категории (`marketplace.leisure_categories.product`) | Типичный тип |
|---|---|---|
| EVENTS | CINEMA, CONCERT, THEATER, EXHIBITION, SPORT, FESTIVAL, SHOW, STANDUP, KIDS_SHOW | SEAT_MAP / GENERAL_ADMISSION |
| LEISURE | BOWLING, KARAOKE, QUEST, KIDS_CENTER, TRAMPOLINE, GAMING_VR, BILLIARDS, MASTERCLASS, EXCURSION, ACTIVE, FAMILY, OTHER, KARTING, LASER_TAG, CLIMBING, PAINTBALL, BOARD_GAMES | TIME_SLOT / CAPACITY / PRIVATE_SESSION |

Один коммерческий объект — одна каноническая карточка и один inventory: `GET /api/v1/leisure/events/{id}` и `/api/v1/events/{id}` читают одну строку; `product` в ответе показывает, к какому продукту она относится, а `/events/{id}` для объекта Leisure отвечает 404.

## Что сделано (Flyway V45, backend)
- `leisure_categories.product`, 5 новых категорий Events и 5 новых Leisure.
- Флаг `EVENTS` (`EVENTS_ENABLED`; пусто = включён в local/dev/test, выключен в production, явное `true` вне них — отказ при старте). Админ может переключать его как остальные (`/admin/features/EVENTS`), `GET /capabilities` → `eventsEnabled`.
- Публичный каталог `GET /api/v1/events`, `/events/categories`, `/events/home`, `/events/{id}`, `/events/{id}/sessions`; места — общий `GET /leisure/sessions/{id}/seats`. Каталог Leisure больше не показывает категории Events.
- Покупка идёт по общим `POST /leisure/sessions/{id}/holds` и `/leisure/orders`; блокировка новых продаж зависит от флага продукта сеанса (`EVENTS_DISABLED` / `LEISURE_DISABLED`). Существующие заказы, билеты и возвраты остаются доступны.
- Тесты (PostgreSQL 16): `EventsApiIntegrationTest` (разделение, каноническая карточка, покупка места), `EventsFlagOffIntegrationTest` (Events выключен — Leisure продаёт); существующая гонка за место `LeisureConcurrencyIntegrationTest` проверяет общий движок.

## Не сделано (честно)
- **Flutter:** отдельная плитка «События» и экраны Events в Consumer/Partner/Executor/Admin, поиск «концерт → Events / боулинг → Leisure», бегущий скриншот-сравнение с референсом. Пока приложение Consumer продолжает открывать Leisure; кино/концерты/театры исчезли из списка категорий Leisure до появления интерфейса Events (данные и покупка через API работают). Flutter SDK в этой сессии отсутствовал — UI не менялся.
- Отдельный Admin-центр Events, CRUD-схемы зала в Partner, Executor-смены, отчёты, перенос/обмен билетов, уведомления, Wallet (нет интеграции), нативные E2E, TalkBack, подписанные APK, PROD (флаг выключен).
- Seed Events использует существующие синтетические данные Leisure (кино, концерт, выставка); демо-данных для спорта/фестиваля/шоу ещё нет.
