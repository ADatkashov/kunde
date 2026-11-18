# Следующий этап Rides — интерфейсы Consumer и Executor

Подключить приложения к API котировок, офферов и поездок. Приёмка включает прохождение поездки в обоих приложениях и историю после завершения.

На тестовом PostgreSQL с настроенными `DB_URL`, `DB_USERNAME` и `DB_PASSWORD` выполнить `cd backend && mvn -Dtest='kz.kunde.rides.*Test' test`. Ожидается ноль ошибок. Команда покрывает поездку через HTTP с синтетической маршрутизацией и PostgreSQL, конкурентные назначения и отмену при выключенном флаге.

[Контекст Rides](docs/product/rides-transport.md) · [Открытые задачи и проверки других сервисов](PROJECT_STATE.md) · [Предыдущие записи](https://github.com/ADatkashov/kunde/blob/4cd6e091741ae6967efafd9235769cec79df5959/NEXT_TASK.md)
