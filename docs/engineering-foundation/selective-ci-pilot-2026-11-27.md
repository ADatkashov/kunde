# Пилот selective CI: Home Services (ADR-027), 2026-11-27

Сравнение двух реальных прогонов GitHub Actions: **FULL** — PR [#294](https://github.com/ADatkashov/kunde/pull/294) (меняет workflow, детектор обязан выбрать FULL), **SELECTIVE** — PR [#295](https://github.com/ADatkashov/kunde/pull/295) (только `backend/services/homeservices/README.md` и `apps/executor/lib/features/home_services/README.md`). Изменения не сопоставимы по содержимому, но дают честную пару «полная сборка ↔ изменение одного продукта». Один замер на каждый вариант, не статистика.

## Что выбрал детектор и что сделал CI

| | FULL (#294) | SELECTIVE (#295) |
|---|---|---|
| Режим Backend CI | `full` → `clean build` | `selective` → `assemble testClasses :services:homeservices:test :app:test --tests kz.kunde.homeservices.* --tests kz.kunde.architecture.*` |
| Тестов backend | 465, 0 падений | **41**, 0 падений |
| Executor Flutter | весь набор | `test/features/executor` + `test/features/home_services`: 32 теста, 0 падений |
| Flutter-workflow запущены | consumer, executor, admin, partner | только executor (path-фильтры; остальные не создавали check) |
| Required CI Gate | PASS, ожидал 7 workflow | PASS, `scope=selective`, ожидал `backend`, `ci`, `executor-flutter`, `security` и проверил обязательные шаги |
| Architecture / Security / Configuration | выполнены | выполнены (`configuration`, `secrets`, `dependencies`, `containers`; architecture-тесты входят в `:app:test`) |

Продукты Taxi, Food, Groceries, Education, Delivery, Health, Events, Leisure, Auto, Beauty, Flowers не запускались: их тесты (`kz.kunde.<pkg>.*`) не вошли в фильтр.

## Время (секунды, из Actions API)

| Job / шаг | FULL | SELECTIVE |
|---|---|---|
| `backend` целиком | 207 | **138** (−33 %) |
| шаг «Verify and package» | 93 | **24** (−74 %) |
| шаг «Architecture boundaries» (холодный Gradle) | 78 | 81 |
| `executor-flutter` | 70 | **58** (−17 %) |
| `docker-image` | 67 | 69 |
| `configuration` / `secrets` / `dependencies` / `containers` | 9 / 13 / 102 / 19 | 13 / 8 / 113 / 27 |

Ускорение даёт только выборочная часть; общие шаги (Docker, зависимости, security) не менялись. Цель «5–10 мин на PR» уже выполнялась до внедрения (≈ 3,5–5 мин): выигрыш измеряется десятками секунд и сокращением объёма тестов (−91 %), а не минутами.

## Кэш Gradle

В обоих прогонах PR шаг `setup-gradle` писал `Gradle User Home cache not found. Will initialize empty`: кэш создаётся прогоном на `main` (PR только читает), а первый такой прогон шёл параллельно. Поэтому шаг «Architecture boundaries» (компиляция с нуля) не ускорился — **hit rate на этих двух прогонах 0 %**. Повторный замер на тёплом кэше — в разделе «Повторный замер» ниже.

## Что пилот НЕ доказал

- Skip-ветка Flutter (`mode=skip`) в боевом CI ещё не встречалась.
- Selective по Consumer почти не экономит: фичи связаны импортами (см. ADR-027).
- Отрицательные пути Gate (обязательный шаг пропущен) проверены юнит-тестами, не реальным провалом.
- Product Profiles проверены тестом изоляции контекста, но не применены к DEV-сервису.

## Повторный замер на тёплом кэше (коммит `6ffd6dc` PR #295)

Тот же selective-состав (41 тест, 0 падений), `setup-gradle` восстановил кэш с `main` (`Restored cache entry with key gradle-home-v1…`):

| Шаг / job | FULL (#294, холодный) | SELECTIVE холодный | SELECTIVE тёплый |
|---|---|---|---|
| `backend` целиком | 207 с | 138 с | **97 с** |
| «Architecture boundaries» | 78 с | 81 с | **30 с** |
| «Verify and package» | 93 с | 24 с | 23 с |

Кэш ускорил компиляцию (шаг Architecture −63 % к холодному selective); тесты по-прежнему не кэшируются. Hit rate по этому замеру: кэш восстановлен (1 из 1 прогона после появления записи на `main`); статистики за несколько прогонов нет.

## Что боевой CI показал после пилота (PR #296–#298)

- **Ветка «изменён общий модуль» впервые исполнилась** (правка порта `PartnerDirectory` в `platform`): выполнено 418 тестов; нашёлся баг детектора — Gradle-путь `:services:platform:test` вместо `:platform:test` (исправлен, регрессионный тест на все модули из `settings.gradle.kts`).
- **Required CI Gate блокировал реальные ошибки** шесть раз подряд (архитектурный тест, неверный Gradle-путь, упавший тест, форматирование, golden) и пропускал только зелёные состояния; ложных блокировок не было.
- Архитектурный fitness-тест (ADR-025) отклонил новую прямую связь `homeservices → таблица партнёра`; аудит перенесён в порт `PartnerDirectory.recordCatalogChange`.
- Flutter: `dart format` и golden-картинки проверяются CI; для воспроизведения локально нужен Flutter 3.47.9 и `dart format --language-version=3.4`.
