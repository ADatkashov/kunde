# KUNDE Events & Tickets 1.0 (DEV/TEST) — разделение с Leisure

## Решение по архитектуре
Аудит 2026-11-21 показал: движок билетов уже существует внутри Leisure 1.0 ([leisure](leisure.md), Flyway V40): сеансы, схемы мест (`SEAT_MAP`), квоты (`GENERAL_ADMISSION`), удержание 10 мин, идемпотентные заказы, `TEST_CARD`, QR `KT1.…` с серверной проверкой и журналом `leisure_checkins`, возвраты, Executor, Partner, Admin. **Второй движок не создаётся.** Events — продуктовое представление этого движка для датированных билетных событий; Leisure — для бронирования активностей.

| Продукт | Категории (`marketplace.leisure_categories.product`) | Типичный тип |
|---|---|---|
| EVENTS | CINEMA, CONCERT, THEATER, EXHIBITION, SPORT, FESTIVAL, SHOW, STANDUP, KIDS_SHOW | SEAT_MAP / GENERAL_ADMISSION |
| LEISURE | BOWLING, KARAOKE, QUEST, KIDS_CENTER, TRAMPOLINE, GAMING_VR, BILLIARDS, MASTERCLASS, EXCURSION, ACTIVE, FAMILY, OTHER, KARTING, LASER_TAG, CLIMBING, PAINTBALL, BOARD_GAMES | TIME_SLOT / CAPACITY / PRIVATE_SESSION |

Один коммерческий объект — одна каноническая карточка и один inventory: `GET /api/v1/leisure/events/{id}` и `/api/v1/events/{id}` читают одну строку; `product` в ответе показывает, к какому продукту она относится, а `/events/{id}` для объекта Leisure отвечает 404.

## Что сделано (Flyway V50, backend)
- `leisure_categories.product`, 5 новых категорий Events и 5 новых Leisure.
- Флаг `EVENTS` (`EVENTS_ENABLED`; пусто = включён в local/dev/test, выключен в production, явное `true` вне них — отказ при старте). Админ может переключать его как остальные (`/admin/features/EVENTS`), `GET /capabilities` → `eventsEnabled`.
- Публичный каталог `GET /api/v1/events`, `/events/categories`, `/events/home`, `/events/{id}`, `/events/{id}/sessions`; места — общий `GET /leisure/sessions/{id}/seats`. Каталог Leisure больше не показывает категории Events.
- Покупка идёт по общим `POST /leisure/sessions/{id}/holds` и `/leisure/orders`; блокировка новых продаж зависит от флага продукта сеанса (`EVENTS_DISABLED` / `LEISURE_DISABLED`). Существующие заказы, билеты и возвраты остаются доступны.
- Тесты (PostgreSQL 16): `EventsApiIntegrationTest` (разделение, каноническая карточка, покупка места), `EventsFlagOffIntegrationTest` (Events выключен — Leisure продаёт); существующая гонка за место `LeisureConcurrencyIntegrationTest` проверяет общий движок.

## Клиенты (Flutter) и роли
- **Consumer:** плитка «События» (флаг `eventsEnabled`) открывает те же экраны Leisure, параметризованные продуктом (`LeisureProduct.events`, `LeisureServices.forProduct`): каталог `/api/v1/events`, детали, сеансы, выбор мест, TEST_CARD, QR, «Мои билеты». Плитка «Досуг» остаётся отдельной (иконка контроллера) и читает `/api/v1/leisure`. Новые категории имеют иконки и градиенты.
- **Admin:** два отдельных центра управления на одном экране; права раздельные (V52): `EVENTS_OPERATIONS` для Events и `LEISURE_OPERATIONS` для Leisure, проверка в БД на каждый запрос, действия по id (решение по событию, отмена заказа, возврат, категории) проверяют продукт самого объекта; площадки, жалобы, отзывы и журнал общие и открыты любому из двух грантов: `GET /admin/leisure/{summary,events,orders,categories}?product=EVENTS|LEISURE`; переключатель `EVENTS` в «Функциях».
- **Partner:** два входа («События», «Досуг») на одном экране с серверным фильтром `?product=` для событий, броней и статистики; для Events в назначении роль только `GATE`.
- **Executor (контролёр):** V51 — роль `GATE`. Организатор назначает контролёра на сеанс, тот принимает назначение и сканирует `POST /api/v1/executor/leisure/checkins`: без принятого назначения на сеанс ответ `ACCESS_DENIED` без данных билета, иначе та же серверная проверка (`ADMITTED` один раз, затем `DUPLICATE`, `CANCELLED`, `EXPIRED`, `TOO_EARLY`, `INVALID`). Offline-проверки нет: при потере сети экран говорит «билет не проверен».
- Тесты: `EventsApiIntegrationTest` (4, в т.ч. контролёр и фильтр Partner), `EventsFlagOffIntegrationTest`; Flutter: Events/Leisure на общих экранах, Admin `product=EVENTS`, Partner, gate-экран (допуск, отказ, потеря сети).
- Нативный E2E `scripts/ci/leisure_native_e2e.py`: покупка мест через плитку «События» в приложении, QR, скан, повтор, отзыв, потеря сети; HTTP: разделение каталогов, бронь Leisure (боулинг) с возвратом, гонка за место, идемпотентность, оба флага выключены.

## Глобальный поиск
`GET /api/v1/search/route?q=` (публично) определяет, куда вести запрос: ключевое слово называет категорию (концерт/театр/кино/спорт → Events; квест/боулинг/VR/караоке/мастер-класс → Leisure), иначе решает содержимое каталогов (`EVENTS`/`LEISURE`/`BOTH`/`NONE`). Во вкладке «Поиск» Consumer поле «События и досуг» открывает нужный список или предлагает выбор из двух.

## Не сделано (честно)
- Проверка скриншотами Android и сравнение с референсом; нативные E2E Partner/Admin/Executor (покрыты виджет-тестами и HTTP); TalkBack на устройстве; полный RU/KK/EN-обзор казахских строк.
- CRUD схемы зала, отчёты по продажам Events в Partner, перенос/обмен билетов, уведомления, Wallet (нет интеграции), промо/жалобы Events отдельно от Leisure (общие разделы Admin).
- Демо-данные для спорта/фестиваля/шоу; PROD (флаг выключен), DEV deploy, подписанные APK.
