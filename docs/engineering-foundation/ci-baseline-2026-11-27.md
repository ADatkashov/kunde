# CI baseline (до ADR-027), 2026-11-27

Источник: GitHub Actions API, последние запуски `main` и PR (один выборочный замер, **не** статистика). Время = `updated_at − created_at` запуска.

| Workflow | Событие | Длительность | Запускается |
|---|---|---|---|
| Backend CI (`backend`, `docker-image` параллельно) | PR | ≈ 4 мин 39 с | `backend/**` (весь `./gradlew clean build` + smoke) |
| Backend CI | push main | ≈ 3 мин 20 с | то же |
| Flutter CI (только Consumer + все `packages/*`) | PR | ≈ 3 мин 11 с | `apps/consumer/**`, `packages/**` |
| Executor Flutter CI | PR | ≈ 1 мин | `apps/executor/**`, пакеты |
| Security CI | PR | ≈ 50 с – 1 мин 20 с | всегда |
| CI configuration | PR | ≈ 16–20 с | всегда (включая `unittest` по `scripts/ci`) |
| Infrastructure / Terraform DEV | PR | ≈ 12–20 с | по paths |
| Release APK on merge (DEV) | push main | ≈ 10 с (определение) → 9–10 мин (сборка) | merge, не ждёт E2E |

## Что уже хорошо

- Heavy E2E (Auto/Delivery/Groceries/Education/Health/Leisure/Rides/Maps, visual) — **только вручную** (`e2e-suite.yml`), не блокируют merge и APK.
- `concurrency` с `cancel-in-progress` на PR для Backend/Flutter/Security/CI configuration; E2E и release — без отмены.
- `scripts/ci/release_targets.py` уже выбирает APK по изменённым путям.

## Найденные пробелы

1. Backend: любое изменение `backend/**` = полная сборка всех 19 модулей (~82 тест-класса только в `:app`); нет выбора по модулю/продукту.
2. Flutter CI: фильтр по папке, а не по фиче; `flutter test` всего Consumer даже при правке одной фичи.
3. Нет единого детектора и нет Required CI Gate; required checks перечислены в [ci-cd-fast-merge.md](ci-cd-fast-merge.md), но **текущая branch protection недоступна агенту (HTTP 403)** — состояние не проверено.
4. Контрактные/продуктовые E2E не параметризованы продуктом (`product`/`suite`) — только набор флажков.
5. Нет сравнимых замеров по job-ам и кэшам Gradle build/configuration cache (используется только `setup-java cache: gradle`).

## Не измерено

Длительности отдельных job/step, hit-rate кэшей, сравнение «после» — будут сняты в PR 3–5; до этого заявлять ускорение нельзя.

## Граф зависимостей (вычисляется, не хранится)

`python3 scripts/ci/detect_affected.py --print-graph` — Gradle-модули и Flutter-проекты с прямыми рёбрами (из `build.gradle.kts`/`pubspec.yaml`).
Ключевые факты: все сервисы зависят от `platform`; `identity`/`partners` — общие; `booking` ← `auto`, `beauty`, `health`, `homeservices`; `groceries` → `food`; `events` → `leisure`; `admin` → `auto`, `delivery`, `food`, `leisure`; `:app` зависит от всех.
Flutter: `kunde_session → kunde_auth → kunde_api → kunde_ui → kunde_operator`; Partner использует только `kunde_api`, `kunde_design`, `kunde_session`.
