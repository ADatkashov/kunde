# Architecture Fitness Functions

Автоматические проверки, удерживающие модульный монолит выделяемым. Все — быстрые тесты без Spring и БД (`backend/app/src/test/java/kz/kunde/architecture/`), запускаются первым шагом `backend.yml` и в каждом PR. **Ни одна проверка не расширяется ради зелёной сборки**: файлы-ратчеты ниже могут только уменьшаться; добавление строки — осознанное решение в том же PR с обоснованием.

| # | Что защищает | Тест | Ратчет / эталон | Статус |
|---|---|---|---|---|
| 1 | Новая межмодульная связь (импорт чужого типа или SQL в чужую таблицу) | `ArchitectureBoundariesTest.newCrossModuleCouplingIsRejected…` | `cross-module-baseline.txt` (144) | действует |
| 2 | У каждой таблицы есть владелец | `…everyTableHasADeclaredOwner` | `table-owners.txt` | действует |
| 3 | `platform` не зависит от бизнес-доменов | `…platformKernelDoesNotDependOnBusinessDomains` | — | действует |
| 4 | Слои Gradle: `platform` без зависимостей, `app` не зависимость библиотек, нет циклов модулей | `ArchitectureFitnessTest.gradleModuleGraphIsLayeredAndAcyclic` | — | действует |
| 5 | Новые циклы между доменами (рёбра графа, лежащие на цикле) | `…domainCouplingHasNoNewCycles` | `known-coupling-cycles.txt` (20 рёбер, один узел из 10 пакетов) | действует |
| 6 | Чужой контроллер/фильтр/конфигурация — не публичный контракт | `…foreignModulesDoNotImportControllersOrBootstrapClasses` | — | действует (демо-сиды допущены, V13) |
| 7 | HTTP-типы (`jakarta.servlet`) не просачиваются в бизнес-логику | `…servletTypesStayInTheWebLayer` | — | действует |
| 8 | Сервисы не используют web-аннотации и `ResponseEntity` | `…servicesDoNotUseWebAnnotationsOrResponseEntity` | — | действует |
| 9 | Новые внешние ключи между таблицами разных владельцев | `…noNewCrossOwnerForeignKeys` | `cross-owner-foreign-keys.txt` (123) | действует |
| 10 | Размещение агрегатов по городам (sharding readiness) | `PlacementRegistryTest` | `placement-registry.txt` | действует |
| 11 | Контракт потребитель↔поставщик для портов (`PartnerDirectory`, `SupportCaseDirectory`, `RideRouting`) и снимок OpenAPI | — | — | TARGET (нужны PostgreSQL/Spring-тесты) |
| 12 | Продюсер события использует `OutboxWriter` в транзакции и поддерживает версию схемы | — | — | TARGET (появится вместе с первым продюсером, [event-catalog](event-catalog.md)) |

## Что сознательно не проверяется

- «Инфраструктурные детали в бизнес-логике» ограничены тем, что можно проверить честно: HTTP-типы (#7, #8). `JdbcTemplate` в сервисах — осознанный выбор проекта (ADR-023: нет ORM и репозиториев); запрет на него дал бы 77 нарушений без пользы.
- Публичность типа внутри пакета нельзя проверить без разбиения пакетов на `api`/`internal` (Конституция §3.6: плоский пакет до ~15 файлов). Вместо этого действует ратчет #1: каждое использование чужого типа — учтённое ребро.

## Как работать с ратчетами

```bash
cd backend
./gradlew :app:test --tests 'kz.kunde.architecture.*'
# осознанная перезапись эталонов; diff проверить глазами, в PR объяснить каждую добавленную строку
./gradlew :app:test --tests 'kz.kunde.architecture.*' -Dkunde.architecture.updateBaseline=true -Dkunde.architecture.updateKnown=true
```
