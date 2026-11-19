# KUNDE Auto 1.0 — backend (DEV/TEST)

Автомобильные услуги построены **на существующем Booking Engine** (`category = AUTO`): станция или мойка — это venue, пост обслуживания — «master», слоты, защита от двойной записи и партнёрский inbox общие. Отдельной архитектуры нет. Flyway [V34](../../backend/src/main/resources/db/migration/V34__auto_services.sql).

## Статус

| Статус | Состояние |
|---|---|
| Core E2E Complete | **Нет.** Android E2E не выполнялся. |
| Functional DEV/TEST Ready | **Нет.** Готов только backend-срез (ниже). |
| External Integration Pending | Платежи (реальных нет), маршрутизация выездной помощи, проверка документов специалистов. |
| Production Launch Blocked | Да. `AUTO_ENABLED=false` по умолчанию, `AutoConfiguration` запрещает флаг вне dev/local/test и без `BOOKING_ENABLED`. |

## Что реализовано (backend)

- Каталог: `GET /api/v1/auto/categories|venues?category=&q=|venues/{id}|slots` (публичные; при выключенном флаге пустые). 8 категорий (мойка, шиномонтаж, масло, диагностика, ТО, ремонт, выездная помощь, прочее). Цена услуги: `FIXED` / `FROM` / `DIAGNOSTIC`, условия, длительность.
- Автомобили (`/vehicles`): марка, модель, год, номер необязательный, до 5, optimistic locking, архивирование, изоляция по владельцу (404 для чужих).
- Котировка `POST /quotes` → цена только на сервере, срок 10 минут, слот должен быть в списке слотов движка. Запись `POST /bookings {quoteId}` + `Idempotency-Key`; повтор → 200 с той же записью; ключ для другой котировки → 409.
- Двойная запись: EXCLUDE-constraint по посту (PENDING/CONFIRMED/CHECKED_IN/IN_PROGRESS/COMPLETED), advisory lock на пост, буфер между визитами (`booking_venues.buffer_minutes`), один автомобиль не может быть в двух записях сразу, недоступные периоды (`booking_time_off`), часовой пояс Asia/Almaty.
- Перенос (`/reschedule`, ≥2 ч до начала, не более 2 раз), отмена (до начала; <2 ч — пометка `LATE_CANCEL`, платежей нет), история с таймлайном.
- Партнёр (существующий `/api/v1/partner/partners/{id}/booking`): CONFIRM, REJECT, CANCEL, CHECK_IN, START, PROPOSE_PRICE, COMPLETE, NO_SHOW; недоступные периоды `…/venues/{id}/time-off` (409 при пересечении с записями). Для `FROM`/`DIAGNOSTIC` итог предлагает партнёр, клиент подтверждает `POST /bookings/{id}/price-decision`; без подтверждения завершить нельзя; `FIXED` изменить нельзя.
- Admin (`/api/v1/admin/auto`, разрешение `AUTO_OPERATIONS` проверяется на каждый запрос): включение категорий, блокировка venue, мониторинг записей без персональных данных; журнал `auto_admin_events` только на добавление.
- Флаг: `GET /capabilities` → `autoEnabled`. При выключенном флаге новые котировки и записи отклоняются (`AUTO_DISABLED`), прежние записи можно отменить или завершить.

## Consumer Flutter (PR 2)

`mobile/lib/features/auto/`: плитка «Авто» на главной (только при `autoEnabled` из `/capabilities`), поиск и фильтр по категориям, карточка СТО/мойки с видом цены и условиями, мои автомобили (добавление, правка, архив, валидация), выбор автомобиля → даты → свободного слота (список слотов с сервера) → серверная котировка → запись (ключ идемпотентности один на попытку), мои записи (активные/история), детали с таймлайном, перенос, отмена, согласование итоговой цены, повторная запись. RU/KK/EN; состояния загрузки, ошибки с повтором и пустые. Тесты: `mobile/test/features/auto/` (7), весь набор `flutter test`: 234 прошли локально (Flutter 3.47.9). Не проверено: устройство, TalkBack, тёмная тема вручную, KK-тексты не вычитаны.

## Partner Flutter + backend управления (PR 2b)

`partner_app`: действия CHECK_IN, START, NO_SHOW, PROPOSE_PRICE (диалог суммы в ₸ → тийн), автомобиль и вид цены в записи, правка услуги (название, цена, длительность, вид цены, условия), добавление услуги и поста для AUTO-заведений, страница недоступных периодов. Backend: `PUT/POST …/booking/venues/{id}/services`, `POST …/masters`, права Owner/Manager, аудит, прежние записи сохраняют цену, устаревшая котировка → `QUOTE_STALE`. Тесты: 112 Partner (7 новых), `AutoApiIntegrationTest` +1. Не сделано: сотрудники, статистика отдельным экраном, перенос записи партнёром.

## Backend Executor / выездные задания (V35)

Отдельные от Rides и Delivery таблицы и права: `auto_specialists` (PENDING → APPROVED/BLOCKED админом, допуск по мобильным категориям `auto_specialist_categories`, журнал `auto_specialist_reviews` только на добавление, самопроверка запрещена), выездные заявки `auto_jobs` по тарифу `auto_roadside_tariffs` (цена «от», итог предлагает специалист и согласует клиент). API: клиент `/api/v1/auto/jobs` (идемпотентная заявка, отмена до прибытия, решение по цене); специалист `/api/v1/executor/auto/{profile,availability,location,jobs/available,jobs,jobs/{id}/accept,jobs/{id}/progress}`; админ `/api/v1/admin/auto/{specialists,jobs}`. Принятие атомарно (блокировка строки, уникальные индексы: одна активная заявка на автомобиль и одна на специалиста); адрес и точные координаты видны только назначенному специалисту, до принятия — расстояние. При выключенном флаге новые заявки и принятия отклоняются, назначенные задания можно вести дальше. Тесты: `AutoJobApiIntegrationTest` (5). `mvn verify`: 322 теста, 0 ошибок.

## Не реализовано (следующие PR)

Flutter Executor (экран AUTO_SPECIALIST) и Admin-экраны; специализация `AUTO_SPECIALIST` и выездной сценарий Executor; жалобы, отзывы и повторная запись; платёжный DEV-контракт (возвраты); Android E2E и подписанные APK; Linear — задач Auto в рабочем пространстве нет, дубли не создавались.

## Проверка

```bash
cd backend && DB_USERNAME=… DB_PASSWORD=… mvn verify   # PostgreSQL 16; POC JWT-тест требует БД на :5544
```

Локальный результат на этом коммите: 316 тестов, 0 ошибок (включая `AutoApiIntegrationTest`, `AutoFlagOffIntegrationTest`, `AutoConfigurationTest`). DEV: `AUTO_ENABLED=true`, `AUTO_SEED_DEMO=true` (+ `BOOKING_ENABLED`) создают два синтетических заведения.
