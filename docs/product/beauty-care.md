# KUNDE Beauty & Care 1.0

Статус: **в разработке (DEV, синтетические данные)**. Продукт строится внутри текущего KUNDE на Booking Engine; публичное включение — только с отдельного разрешения владельца. Флаг `BEAUTY_ENABLED` по умолчанию выключен.

## Аудит `main` (2026-11-23, SHA `1c184fb`)

| Область | Состояние | Доказательство |
|---|---|---|
| Запись в барбершоп (категория `BARBER`) | Реализовано | [Booking MVP](booking-mvp.md), V18, `BookingApiIntegrationTest` (12 тестов) |
| Защита от двойной записи мастера | Реализовано | `EXCLUDE USING gist (master_id, tstzrange)` для `CONFIRMED/COMPLETED` + advisory lock пользователя |
| Слоты (рабочие часы, перерывы, 15 мин, горизонт 14 дней, часовой пояс заведения) | Реализовано | `BookingSlots` |
| Идемпотентность, отмена до начала, история | Реализовано | `BookingService`, `Idempotency-Key` |
| Partner-управление заведениями и расписанием | Частично | `BookingPartnerService` (653 строки), `V20__partner_operations` |
| Feature flag + Admin-переключатель + аудит | Паттерн готов | `FeatureToggles`, `HomeServicesSettings`, V59 |
| Плитка «Красота» и экран «Барбершопы» в Consumer | Частично | `BeautyCategoryScreen`, остальные виды — «Скоро» |
| Категории Beauty, фильтры, каталог салонов, карточка услуги | **Отсутствует** | — |
| Выбор мастера отдельным экраном, перенос записи | Отсутствует (мастер выбирается на экране записи, переноса нет) | `booking-mvp.md` «Not included» |
| Hold (временный резерв) и оплата записи | Отсутствует | оплата на месте, `DEV_MOCK` подтверждение |
| Возвраты, сертификаты, отзывы мастеров, избранное салонов | Отсутствует (избранное есть для Health) | `HealthFavoritesController` |
| Уведомления о записи | Отсутствует | в MVP не включены |
| Executor/Partner/Admin экраны Beauty | Отсутствуют | — |
| KUNDE Maps (адрес, «Рядом», маршрут) | Backend за `MAPS_ENABLED`, клиентских экранов нет | `PROJECT_STATE.md` |
| Внешние зависимости | Реальный платёжный провайдер не подключён; проверка на Samsung — только владелец | — |

Решение: Beauty — расширение Booking Engine (категории `BARBER` и новые), а не новый модуль. Запись в барбершоп остаётся под `BOOKING_ENABLED` и **не** зависит от `BEAUTY_ENABLED` (иначе сломался бы действующий пилот); `BEAUTY_ENABLED` закрывает новый публичный Beauty API.

## Сделано в этой ветке (Phase 1 — Foundation, часть 1)

- `BEAUTY_ENABLED` (`app.beauty.enabled`): выключен по умолчанию, допускается только в явном окружении `local/dev/test` при `BOOKING_ENABLED=true` (`BeautySettings`), управляется Admin API переключателей (`Feature.BEAUTY`, аудит, версия) и отражается в `GET /api/v1/capabilities` как `beautyEnabled`.
- Flyway **V63**: допустимые значения `feature_toggles(.events)` расширены `BEAUTY`; таблица `marketplace.beauty_categories` (RU/KK/EN, 8 плиток главной + 4 в «Ещё»).
- `GET /api/v1/beauty/categories?featured&limit&offset` (публичный, пагинация, `404 BEAUTY_DISABLED` при выключенном флаге).
- Flutter: `PlatformSnapshot.beautyEnabled`, подпись переключателя «Красота и уход» в Admin.
- Проверено локально (PostgreSQL 16): `Beauty*`, `PlatformControllerTest`, `HomeServicesSettingsTest`, `FeatureTogglesApiIntegrationTest`, `BookingApiIntegrationTest` — 29 тестов, 0 ошибок. Flutter-тесты не запускались (SDK в окружении нет).

## План (по фазам из ТЗ)

1. **Foundation** (продолжение): салоны/филиалы поверх `booking_venues` (рейтинг, адрес, координаты, фото, модерация), DEV-fixtures (LUNA, Scala, Aura, Barber House — синтетические), каталог с серверными фильтрами и сортировкой.
2. **Consumer Discovery:** главная «Красота и уход», поиск, каталог, карточка услуги, избранное.
3. **Booking:** профили мастеров, квалификации, hold с TTL, перенос записи, конкурентные тесты (два клиента — один слот).
4. **Payments:** сессия оплаты через существующий провайдер, webhook с идемпотентностью, возвраты; без реальных денег в DEV.
5. **Partner / 6. Executor / 7. Admin**, 8. **Качество** (E2E-01…07), 9. **Поставка** (PR, DEV deploy по действующему разрешению из AGENTS.md, четыре Release APK).

Заблокировано/требует владельца: включение в PROD, реальные платежи и возвраты, подарочные сертификаты (нужна модель баланса), проверка на реальном Samsung.
