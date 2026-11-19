# Следующая проверка KUNDE Rides 1.3

На интегрированном `main` проверить [Android E2E](docs/product/rides-transport.md#нативный-e2e) и два [подписанных DEV APK](docs/infrastructure/android-release-apk.md). В `status.json` должен быть `PASSED`; для каждого APK сверить пакет, версию, SHA исходников, SHA-256 файла и сертификата. Маршрут только тестовый. E2E использует изолированную БД и отключённые платежи.

После проверки DEV остаются согласованный дорожный провайдер, платёжный цикл и проверка файлов водительских документов. Публичная активация выполняется отдельно по решению владельца.

[Статус проекта](PROJECT_STATE.md) · [Linear ADA-44](https://linear.app/adatkashov/issue/ADA-44/feat-013-provider-dispatch)
