# Event Catalog (integration events)

Статус: **каталог кандидатов, ни одно событие не публикуется** (состояние 2026-11-24: `OutboxWriter` не вызывается ни одним доменом). Механика — [ADR-022](adr/ADR-022-transactional-outbox.md); общая архитектура событий — [14-event-driven-architecture](14-event-driven-architecture.md); аналитические события продукта — отдельный закрытый каталог ([event-taxonomy](../engineering-foundation/event-taxonomy.md), `platform.analytics.EventCatalog`) и с интеграционными не смешиваются.

## Правила

| Правило | Содержание |
|---|---|
| Имя | `kunde.<aggregate>.<fact>` в прошедшем времени, нижний регистр (`kunde.partner.approved`) |
| Версия | `schema_version` целое; в пределах версии допускается только добавление полей; несовместимое изменение — новая версия, обе публикуются параллельно, пока есть потребители ADR-022 |
| Владелец | Событие публикует **только владелец агрегата** (по [матрице владения](database-ownership-matrix.md)); потребитель не публикует чужие факты |
| Состав | Идентификаторы и факт, без ПДн и без свободного текста (как в ADR-022: payload не логируется); потребитель, которому нужны данные, запрашивает их по контракту владельца |
| Идемпотентность | Доставка at-least-once; потребитель хранит `event_id` в inbox (есть в `platform.inbox_events`); внешние побочные эффекты — собственный ключ идемпотентности |
| Порядок | Только внутри агрегата; потребитель устойчив к перестановке между агрегатами |
| Повторы и DLQ | Экспоненциальная задержка с jitter; после `app.outbox.max-attempts` — `DEAD`; мёртвое письмо блокирует свой агрегат намеренно; разбор — оператором (инструмента ещё нет: V16) |
| Транзакция | Запись в outbox — в той же транзакции, что и изменение состояния; финансовые потоки подключаются последними после отдельного разбора корректности |

## Кандидаты и что они заменяют

Приоритет — по числу SQL/импортов, которые событие или контракт убирает ([матрица](domain-dependency-matrix.md)). Статус везде: **не реализовано**.

| Событие | Владелец | Потребители (кандидаты) | Заменяет | Приоритет |
|---|---|---|---|---|
| `kunde.partner.approved` / `suspended` / `staff_changed` v1 | partner | auth (роль в токене), поиск, уведомления | `auth → partner_staff` SQL, кэш проверки `PartnerDirectory` | 1 (нефинансовое, первый продюсер) |
| `kunde.offering.published` / `unpublished` v1 | catalog | поиск/каталожные проекции | `partner → offerings` чтение каталога из других доменов | 1 |
| `kunde.order.created` / `status_changed` / `completed` v1 (food, groceries) | food | admin-сводки, уведомления, support | `admin → food_orders` (14 SQL), `groceries → food_orders` | 2 |
| `kunde.ride.completed` / `kunde.delivery.completed` v1 | rides / delivery | support, аналитика, выплаты | `support → rides/deliveries` (FK), диспетчерские SQL | 2 |
| `kunde.booking.confirmed` / `cancelled` v1 | booking | вертикали (beauty/health/auto), admin | `admin → bookings`, `auto → bookings` | 2 |
| `kunde.leisure.ticket_issued` / `refunded` v1 | leisure | admin, support | `admin → leisure_*` (11 SQL) | 3 |
| `kunde.payment.completed` / `failed` / `refund.completed` v1 | будущий Payments (ADR-010, домена в коде нет) | заказ-владельцы | прямые вызовы `*Payments` | 4 — только после отдельного решения и проверки корректности |

Каждая строка превращается в запись реестра (событие, версия, схема payload, потребители, контрактный тест) **в том PR, который впервые публикует событие**; пока продюсера нет, схемы не пишутся (нет исполняемого описания — нечему устаревать).
