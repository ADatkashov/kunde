# Domain readiness scores

Оценка готовности домена к будущему выделению, 0–100, состояние 2026-11-24. Считается автоматически и воспроизводимо: `python3 scripts/dev/architecture_matrix.py readiness`.
Это эвристика для приоритизации, а не обещание: она не заменяет решения владельца и измеримого основания ([ADR-025](adr/ADR-025-gradual-service-extraction.md)).

Формула: 100 минус штрафы — исходящие чужие SQL (3 за связь, максимум 30) и импорты (2, максимум 15) к **не ядерным** доменам; чужие SQL в таблицы домена (2, максимум 20); FK с другим некорневым владельцем (2, максимум 15); участие в узле циклов (15); отсутствие публикуемых событий/outbox (10, у всех: ни один домен не пишет в `OutboxWriter`). `maps` выделен уже (отдельный репозиторий, ADR-020). Для ядра (`auth`, `identity`, `partner`, `catalog`) оценка показывает лишь аккуратность, выделять его не планируется.

| Домен | Оценка | Исходящие чужие SQL/импорты | Чужие читают его таблицы | FK с другим доменом | В узле циклов |
|---|---|---|---|---|---|
| auth | 75 | 0 / 0 | 0 | 0 | да |
| identity | 90 | 0 / 0 | 0 | 0 | нет |
| partner | 63 | 4 / 0 | 0 | 0 | да |
| catalog | 75 | 0 / 0 | 0 | 0 | да |
| admin | 45 | 38 / 9 | 0 | 0 | нет |
| support | 86 | 0 / 0 | 0 | 2 | нет |
| food | 37 | 2 / 0 | 26 | 6 | да |
| groceries | 27 | 11 / 1 | 2 | 6 | да |
| delivery | 66 | 1 / 0 | 2 | 1 | да |
| rides | 68 | 1 / 0 | 1 | 1 | да |
| maps | 95 | 0 / 0 | 0 | 0 | нет |
| booking | 28 | 4 / 0 | 30 | 22 | да |
| beauty | 71 | 0 / 0 | 2 | 8 | нет |
| homeservices | 86 | 0 / 0 | 2 | 0 | нет |
| health | 61 | 0 / 0 | 2 | 5 | да |
| auto | 48 | 0 / 0 | 6 | 9 | да |
| leisure | 70 | 0 / 0 | 11 | 0 | нет |
| events | 86 | 0 / 2 | 0 | 0 | нет |
| education | 90 | 0 / 0 | 0 | 0 | нет |

## Доказательства и блокеры по доменам

| Домен | Доказательства | Блокеры |
|---|---|---|
| maps | Отдельный репозиторий `kunde-maps`; в backend только порт `RideRouting` и HTTP-адаптер | — |
| education | Нет входящих чужих SQL; единственные внешние ссылки — ядро (`partner`, `identity`) | `education → identity/partner` по SQL (контракт ядра), админ-права |
| identity | Ничего не читает наружу; 79 FK внутрь — осознанное ядро | Станет отдельным сервисом только последним |
| support | Нет исходящих SQL/импортов (`SupportCaseDirectory`, `CaseSubjectOwnership`) | Два FK на `deliveries/rides` |
| homeservices | Тонкая вертикаль Booking, 1 импорт | Выделяется только вместе с booking |
| events | 2 импорта `leisure` | Выделяется только вместе с leisure |
| leisure | Свои 19 таблиц; нет циклов | Admin пишет напрямую в 11 мест; `leisure → auth/partner` |
| beauty | Нет циклов | 17 ссылок на `booking_*` (семья), FK |
| delivery / rides | Контракты `ActiveWork`, `RideRouting`, `CaseSubjectOwnership` | Узел циклов; `rides ↔ delivery` по SQL; общая диспетчеризация |
| partner | `PartnerDirectory` как публичный контракт | Демо-сид тянет `food/booking/auth` |
| health, auto | Вертикали Booking | Обратные рёбра `booking → health/auto`; 22 FK у booking |
| admin | Только маршрутизация + гранты `AdminGrants` в `platform.authz` | 38 SQL и 9 импортов в 8 доменов (см. [microservice-readiness](microservice-readiness.md)) |
| food, groceries, booking | Внутри семьи — зрелые модули | Семьи welded: `groceries → food_*` (11), `booking` — 29 входящих чужих SQL и 22 FK |
