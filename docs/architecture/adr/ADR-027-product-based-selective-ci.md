# ADR-027: Product-Based Development, Affected Modules Testing and Selective CI/CD

- Статус: **PROPOSED** (принятие — за владельцем репозитория)
- Дата: 2026-11-27
- Связано: [ADR-023](ADR-023-build-system-and-module-structure.md), [ADR-024](ADR-024-shared-token-session-core.md), [ADR-025](ADR-025-gradual-service-extraction.md), [CI/CD: быстрый merge](../../engineering-foundation/ci-cd-fast-merge.md), [Baseline](../../engineering-foundation/ci-baseline-2026-11-27.md)

## Контекст

Монорепозиторий уже разделён: 19 Gradle-модулей (`platform`, `services/*`, `app`), четыре независимых Flutter-приложения, девять общих пакетов. Тяжёлые E2E вынесены в ручной `e2e-suite.yml`, APK собирается на merge независимо от E2E, Backend/Flutter CI уже фильтруются по `paths`.
Остаются пробелы:

1. Path-фильтры грубые: любое изменение в `backend/**` запускает весь `./gradlew clean build`, любое в `packages/**` — весь Consumer; изменение одного продукта не отличается от изменения Booking или Identity.
2. Нет единого места, где зафиксировано, **кого затрагивает** изменение (транзитивные зависимости считаются вручную).
3. Path-фильтры на самом workflow оставляют required check в «Expected», если workflow не запустился.

## Решение

1. **Один монорепозиторий, модульный монолит, существующие приложения и application ID сохраняются.** Отдельных репозиториев и физических микросервисов нет.
2. **Детектор затронутых модулей** `scripts/ci/detect_affected.py` — единственный источник решения «что запускать». Рёбра зависимостей он **читает из `settings.gradle.kts`, `build.gradle.kts` модулей и `pubspec.yaml`**, а не из отдельного файла (нет дрейфа). `scripts/ci/product-registry.json` содержит только то, чего нет в сборочных файлах: продукт ↔ Gradle-модуль, пакеты тестов в `:app`, Flutter-фичи продукта по приложениям.
3. **Правила** (тестируются в `scripts/ci/test_detect_affected.py`):

| Изменение | Результат |
|---|---|
| модуль продукта | его `:services:<m>:test`, пакеты `:app`-тестов продукта, Flutter-фичи продукта; зависимые модули |
| `booking` | все модули-потребители (`auto`, `beauty`, `health`, `homeservices` и их зависимые) |
| `platform`, `identity`, `partners` | все модули, все `:app`-тесты, все продукты |
| Flyway-миграция | все `:app`-тесты (миграционные/интеграционные), все продукты (консервативно) |
| Flutter-фича продукта | тесты этой фичи в этом приложении |
| общая/нерегистрированная фича, файл уровня приложения | всё приложение |
| `packages/<p>` | пакет, его зависимые пакеты (транзитивно) и все приложения-потребители целиком |
| `.github/**`, `scripts/ci/**`, Gradle-файлы, `compose.yaml` | **FULL** |
| неизвестный файл, невалидный граф, неразрешимые SHA | **FULL** |
| только `docs/**`, корневые `*.md` | проверка документации (job `CI configuration`) |

4. **Fail-safe вместо silent skip:** любая неопределённость → `scope=full` с причиной в выводе. Ошибка детектора не может превратиться в «ничего не запускать».
5. **Выборочный запуск ≠ выборочная компиляция.** Приложения продолжают компилировать все фичи; `flutter analyze` запускается для затронутого приложения целиком.
6. **Required CI Gate** (будущий PR 5) запускается всегда и учитывает success/failure/cancelled/ожидаемый skipped; branch protection меняет только владелец.
7. **Долгие E2E** остаются вне критического пути PR (`e2e-suite.yml`, ручной запуск); Full Regression — ночью и перед PROD (будущие PR).

## Что сознательно не делается сейчас

- Не создаётся «зеркальная» структура `backend/services/home-services` — реальный модуль называется `homeservices`; имена не меняются ради нейминга.
- Миграции не сопоставляются с продуктами по таблицам (консервативно все продукты); уточнение — отдельная задача после изучения `database-ownership-matrix`.
- **Фичи Consumer связаны импортами** (`home` импортирует почти все фичи, `booking` — beauty/food/health/home/home_services, `identity` — десять): детектор строит граф по реальным `import`, поэтому правка одной фичи Consumer перезапускает почти все feature-тесты (замыкание Home Services — 15 из 18 директорий). Реальная изоляция Consumer требует инверсии зависимостей (отдельная задача); выгода сейчас — в Executor/Admin, пропуске недостижимых приложений и пакетов, не затронутых изменением. Тесты вне `test/features/` (`core`, `shared`, `support`) идут только при изменении общих файлов приложения.
- Партнёрское приложение имеет плоскую структуру тестов (`apps/partner/test/*_test.dart`), выборочный запуск по продуктам для него невозможен — всегда целиком.
- Часть `:app`-тестов (`architecture`, `config`, `platform`, интеграционные auth/identity) не принадлежит продукту и запускается при любом изменении shared-модулей.
- Конституция не изменена (требуется отдельное согласование владельца).

## Последствия

Положительные: CI-решение воспроизводимо, объяснимо (`reasons`) и покрыто тестами; граф не расходится с Gradle/pubspec.
Риски: реестр нужно обновлять при добавлении продукта (тест `test_every_gradle_module_is_registered` и fail-safe FULL предотвращают тихий пропуск); детектор пока **не подключён** к workflow — подключение (PR 3–5) требует `fetch-depth` для merge-base и согласования required checks.

## План

PR 1 — этот ADR, baseline, реестр. PR 2 — детектор и тесты (выполнен вместе с PR 1). PR 3 — backend selective build/test (`backend.yml`, `backend_gradle_args.py`; в этой же ветке). PR 4 — Flutter selective testing (`flutter.yml`, `executor-flutter.yml`, `admin-flutter.yml`, `flutter_selection.py`; Partner без изменений: плоские тесты). PR 5 — `ci-pr.yml`, Required CI Gate, `product-e2e.yml`, кэши. PR 6 — product profiles, пилот Home Services, DEV Release.
