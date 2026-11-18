# Следующий этап Rides — интеграция двух приложений в DEV/TEST

После обязательного Security CI последовательно объединить стек PR #131–133 и Executor. Провести поездку Consumer → Executor → Consumer на двух устройствах или эмуляторах с тестовым маршрутом, проверить историю, отмену, повторы и сетевые ошибки.

Проверки backend выполняются на тестовом PostgreSQL через `cd backend && mvn -Dtest='kz.kunde.rides.*Test' test`. Проверки Flutter выполняются через `cd mobile && flutter analyze --fatal-infos && flutter test`. Обе команды должны пройти. Для двух сборок использовать Android Release APK (DEV) с разными значениями параметра `executor`, проверить идентификаторы, сертификаты и SHA-256.

[Контекст и ограничения Rides](docs/product/rides-transport.md) · [Статус проекта](PROJECT_STATE.md)
