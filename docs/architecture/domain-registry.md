# Domain Registry

Единый реестр доменов KUNDE (см. [CONSTITUTION](CONSTITUTION.md) §1). Состояние на 2026-11-24: пакет — `kz.kunde.<pkg>`, Gradle-модуль — `backend/services/<module>` (✔ = модуль создан; все домены вынесены, `backend/app` — composition root). Колонки обновляются в каждом PR, который переносит домен. Подробный аудит: [project-structure-audit](project-structure-audit.md).

| Канон | Продукт для пользователя | Пакет сейчас → модуль | Маршруты `/api/v1/…` | Flutter features (сейчас) | Таблицы (префикс) | Зависит от |
|---|---|---|---|---|---|---|
| identity | Профиль, адреса, согласия | `identity` → `services/identity` ✔ | `me`, `me/addresses`, `me/consents` | `identity` | `identity.users`, `profile.*`, `serviceability.*` | platform |
| auth | Вход по телефону | `auth` → `services/identity` ✔ | `auth` | `identity` | `identity.auth_/otp_/refresh_` | platform |
| partners | Партнёры, персонал, каталог | `partner`, `catalog` → `services/partners` ✔ | `partner`, `categories`/offerings | `partner`, `partner_app` | `marketplace.partner*`, `offering*`, `categories` | auth |
| food | Еда | `food` → `services/food` ✔ | `food`, `executor/food`, `partner/…/food` | `food`, `food_admin`, `executor/food_work` | `food_*` | partners |
| groceries | Продукты | `groceries` → `services/groceries` ✔ | `groceries` | `groceries` | `grocery_*` | food |
| delivery | Доставка | `delivery` → `services/delivery` ✔ | `deliveries`, `executor/deliveries`, `admin/deliveries`, `partner/…/deliveries` | `delivery`, `delivery_admin`, `executor/delivery_work` | `deliver*` | partners, platform |
| rides | Такси | `rides` → `services/rides` ✔ | `rides`, `executor/rides`, `admin/rides`, `partner/…/rides/fleet` | `rides`, `rides_admin`, `executor/driver_*` | `ride*` | partners, platform |
| maps | (карты, внешний сервис `kunde-maps`) | `maps` → `services/maps` ✔ | — | `maps` | — | platform.geo |
| booking | Движок записи | `booking` → `services/booking` ✔ (контракт для вертикалей — `BookingCategory`, `BookingSlots`, `BookingService`) | `booking`, `booking/bookings`, `partner/…/booking` | `booking` | `booking_*`, `bookings` | partners |
| beauty | Красота | `beauty` → `services/beauty` ✔ (вертикаль Booking; готов к модулю) | `beauty`, `beauty/favorites`, `executor/beauty`, `partner/…/beauty`, `admin/beauty` | `beauty` | `marketplace.beauty_*` | booking |
| homeservices | Услуги на дом | `homeservices` → `services/homeservices` ✔ (вертикаль Booking; готов к модулю) | `home-services`, `admin/home-services/{categories,offers}`, `partner/partners/{id}/home-services/offers` | `home`, `home_services_admin` | `home_service*` | booking |
| health | Здоровье | `health` → `services/health` ✔ | `booking/health/favorites`, `admin/health` | `health` | `health_*` | booking, partners |
| auto | Авто | `auto` → `services/auto` ✔ | `auto`, `admin/auto` | `auto`, `auto_admin`, `executor/auto_work` | `auto_*`, `customer_vehicles` | booking |
| leisure | Досуг | `leisure` → `services/leisure` ✔ | `leisure`, `executor/leisure`, `partner/…/leisure`, `admin/leisure` | `leisure`, `leisure_admin`, `executor/gate_scan` | `leisure_*` | partners, auth |
| events | Мероприятия | `events` → `services/events` ✔ | `events`, `search` | — (UI в `leisure`) | (`leisure_*`) | leisure |
| flowers | Цветы и подарки | `flowers` → `services/flowers` ✔ (шаг 1 [ADR-026](adr/ADR-026-flowers-gifts-domain.md): модуль и флаг `FLOWERS_ENABLED`, без поведения; пока цветы работают как вертикаль `FLOWERS_GIFTS` в `food`) | (будущие `flowers/**`) | (будущие `flowers/**` в Consumer, Partner, Executor, Admin) | (будущий префикс `flowers_`) | partners |
| education | Образование | `education` → `services/education` ✔ | `education`, `education/enrollments` | `education` | `education_*` | partners |
| support | Поддержка | `support` → `services/support` ✔ | `me/support/cases` | (в `delivery`/`rides`) | `support.*` | platform.support |
| admin | Админ-панель | `admin` → `services/admin` ✔ | `admin/*` (auto, beauty, features, food, groceries, home-services, leisure, partners) | `admin_*`, `*_admin` | `identity.admin_*` | домены (однонаправленно) |
| platform | (техническое ядро) | `platform` → `backend/platform` ✔; `config`, `KundeApplication` → `backend/app` ✔ | `health`, `poc` | — | `platform.*`, `identity.feature_toggle*` | — |

Бывшие заготовки (ADR-023 «Судьба заготовок»), перенесены: `food.order` (жизненный цикл заказа Food), `food.fulfillment` (самовывоз), `platform.notifications` (цепочка доставки, допустимость каналов), `platform.analytics` (каталог событий и шлюз минимизации). Ни одна из них пока не вызывается из кода; отдельные домены появятся при реальной бизнес-ответственности.

**Feature flags:** `FOOD_*`, `GROCERIES_*`, `DELIVERY_*`, `RIDES_*`, `MAPS_ENABLED`, `BEAUTY_ENABLED`, `FLOWERS_ENABLED`, `BOOKING_*`, … + runtime-переключатели `identity.feature_toggles`; точный перечень выводится из `FeatureGate`-бинов (`platform.FeatureToggles`).
**Расположение тестов:** сейчас `backend/src/test/java/kz/kunde/<pkg>`, `apps/consumer/test/features/<feature>`; целевое — в модуле/приложении домена.

**Готовность к выделению и связи:** [microservice-readiness](microservice-readiness.md) · [оценки](domain-readiness-scores.md) · [матрица зависимостей](domain-dependency-matrix.md) · [владение данными](database-ownership-matrix.md) · [события](event-catalog.md) · [ADR-025](adr/ADR-025-gradual-service-extraction.md).
