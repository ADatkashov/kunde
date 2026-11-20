# Следующая задача KUNDE Auto 1.0

Backend-срез смержен в PR (см. [auto](docs/product/auto.md)). Далее по порядку: Consumer Flutter (автомобили, каталог, котировка, запись, перенос/отмена, история), Partner Flutter (inbox, жизненный цикл, недоступные периоды), затем Android E2E и подписанные DEV Release APK.

Приёмка: `cd backend && mvn verify` на PostgreSQL 16, `flutter analyze` и `flutter test`, Android E2E «Consumer → запись → Partner подтверждает → обслуживание → история». Публичный запуск Auto выключен.
