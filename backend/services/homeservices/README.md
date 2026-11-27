# `:services:homeservices` — «Дом и быт»

Вертикаль Booking Engine (`:services:booking`): каталог предложений мастеров по категориям работ, расчёт цены на сервере, модерация предложений и визит мастера. Пакет `kz.kunde.homeservices`. Продуктовая картина — [docs/product/home-services.md](../../../docs/product/home-services.md); решения по структуре — [ADR-023](../../../docs/architecture/adr/ADR-023-build-system-and-module-structure.md), CI — [ADR-027](../../../docs/architecture/adr/ADR-027-product-based-selective-ci.md).

## Что внутри

| Контроллер | Маршрут `/api/v1/…` | Кто |
|---|---|---|
| `HomeServicesCatalogController` | `home-services/categories`, `home-services/definitions` | любой |
| `HomeServicesOffersController` | `home-services/offers`, `home-services/offers/{id}/quote` | Consumer (публично) |
| `HomeServicesPartnerOffersController` | `partner/partners/{partnerId}/home-services/offers` (+ `/{id}/transition`) | Partner |
| `HomeServicesPartnerPricingController` | `partner/partners/{partnerId}/home-services/zones`, `offers/{id}/tariff` | Partner |
| `HomeServicesPartnerMastersController` | `partner/partners/{partnerId}/home-services/masters` (+ `/{id}/invite`, `/{id}/deactivate`) | Partner: мастера и коды-приглашения для Executor |
| `HomeServicesAdminOffersController` | `admin/home-services/offers` (+ `/{id}/decision`) | Admin (грант `HOME_SERVICES_CATALOG`) |
| `HomeServicesVisitController` | `executor/home-services/{link,jobs,jobs/{id}/stage,start,complete}`, `home-services/bookings/{id}/visit` | Executor, Consumer (своя запись) |

Заказ создаётся общим `POST /booking/bookings` (идемпотентно, `Idempotency-Key`); Partner подтверждает через `partner/partners/{id}/booking/bookings/{id}/action`. Порядок визита (`EN_ROUTE → ARRIVED → START → COMPLETE`) принудительно проверяет сервер.

## Флаги

`HOME_SERVICES_ENABLED` (только `local`/`dev`/`test`, иначе приложение не стартует) требует `BOOKING_ENABLED`. Runtime-переключатель — `identity.feature_toggles` (`HOME_SERVICES`). Профиль окружения: `python3 scripts/dev/product_profile.py dev-home-services` — остальные продукты явно выключены.

## Тесты и команды

```bash
cd backend
./gradlew :services:homeservices:test                              # модульные тесты
./gradlew :app:test --tests 'kz.kunde.homeservices.*'              # HTTP + PostgreSQL (нужны DB_URL/DB_USERNAME/DB_PASSWORD)
./gradlew :app:test --tests 'kz.kunde.homeservices.HomeServicesJourneyIntegrationTest'   # сквозной сценарий пяти ролей
```

`HomeServicesJourneyIntegrationTest` — это **API-интеграционный** сценарий (оффер → модерация → заказ → приём → визит → завершение; отмена, доступ, повторы, недопустимые переходы). Он **не заменяет** нативный multi-role E2E на устройствах (в бэклоге Home Services MVP).

Что CI запустит для правки только этого модуля: `git diff --name-only origin/main... | python3 scripts/ci/detect_affected.py --files-from -`.
