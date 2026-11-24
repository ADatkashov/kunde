# Domain Registry

Единый реестр доменов KUNDE (см. [CONSTITUTION](CONSTITUTION.md) §1). Состояние на 2026-11-24: пакеты — **текущие** (`kz.kunde.<pkg>`), Gradle-модуль — **целевой** (`backend/services/<module>`). Колонки обновляются в каждом PR, который переносит домен. Подробный аудит: [project-structure-audit](project-structure-audit.md).

| Канон | Продукт для пользователя | Пакет сейчас → модуль | Маршруты `/api/v1/…` | Flutter features (сейчас) | Таблицы (префикс) | Зависит от |
|---|---|---|---|---|---|---|
| identity | Профиль, адреса, согласия | `identity` | `me`, `me/addresses`, `me/consents` | `identity` | `identity.users`, `profile.*`, `serviceability.*` | platform |
| auth | Вход по телефону | `auth` → `identity` | `auth` | `identity` | `identity.auth_/otp_/refresh_` | platform |
| partners | Партнёры, персонал, каталог | `partner`, `catalog` → `partners` | `partner`, `categories`/offerings | `partner`, `partner_app` | `marketplace.partner*`, `offering*`, `categories` | auth |
| food | Еда | `food` | `food`, `executor/food`, `partner/…/food` | `food`, `food_admin`, `executor/food_work` | `food_*` | partners |
| groceries | Продукты | `groceries` | `groceries` | `groceries` | `grocery_*` | food |
| delivery | Доставка | `delivery` | `deliveries`, `executor/deliveries`, `admin/deliveries`, `partner/…/deliveries` | `delivery`, `delivery_admin`, `executor/delivery_work` | `deliver*` | partners, platform |
| rides | Такси | `rides` | `rides`, `executor/rides`, `admin/rides`, `partner/…/rides/fleet` | `rides`, `rides_admin`, `executor/driver_*` | `ride*` | partners, platform |
| maps | (карты, внешний сервис `kunde-maps`) | `maps` | — | `maps` | — | platform.geo |
| booking | Движок записи | `booking` | `booking`, `booking/bookings`, `partner/…/booking` | `booking` | `booking_*`, `bookings` | partners |
| beauty | Красота | `booking` → **`beauty`** | `beauty`, `beauty/favorites`, `executor/beauty`, `partner/…/beauty`, `admin/beauty` | `beauty` | `marketplace.beauty_*` → beauty | booking |
| homeservices | Услуги на дом | `booking` → **`homeservices`** | `home-services`, `admin/home-services/categories` | `home`, `home_services_admin` | `home_service*` → homeservices | booking |
| health | Здоровье | `health` | `booking/health/favorites`, `admin/health` | `health` | `health_*` | booking, partners |
| auto | Авто | `auto` | `auto`, `admin/auto` | `auto`, `auto_admin`, `executor/auto_work` | `auto_*`, `customer_vehicles` | booking |
| leisure | Досуг | `leisure` | `leisure`, `executor/leisure`, `partner/…/leisure`, `admin/leisure` | `leisure`, `leisure_admin`, `executor/gate_scan` | `leisure_*` | partners, auth |
| events | Мероприятия | `events` | `events`, `search` | — (UI в `leisure`) | (`leisure_*`) | leisure |
| education | Образование | `education` | `education`, `education/enrollments` | `education` | `education_*` | partners |
| support | Поддержка | `support` | `me/support/cases` | (в `delivery`/`rides`) | `support.*` | platform.support |
| admin | Админ-панель | `admin` | `admin/*` (auto, beauty, features, food, groceries, home-services, leisure, partners) | `admin_*`, `*_admin` | `identity.admin_*` | домены (однонаправленно) |
| platform | (техническое ядро) | `platform`, `config` → `platform`, `app` | `health`, `poc` | — | `platform.*`, `identity.feature_toggle*` | — |

Заготовки `order`, `fulfillment` (→ `food`), `notification`, `analytics` (→ `platform`) — решение в ADR-023 «Судьба заготовок».

**Feature flags:** `FOOD_*`, `GROCERIES_*`, `DELIVERY_*`, `RIDES_*`, `MAPS_ENABLED`, `BEAUTY_ENABLED`, `BOOKING_*`, … + runtime-переключатели `identity.feature_toggles`; точный перечень выводится из `FeatureGate`-бинов (`platform.FeatureToggles`).
**Расположение тестов:** сейчас `backend/src/test/java/kz/kunde/<pkg>`, `mobile/test/features/<feature>`; целевое — в модуле/приложении домена.
