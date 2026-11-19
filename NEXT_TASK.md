# Следующий этап Rides — интеграция и подписанные APK DEV

[#131](https://github.com/ADatkashov/kunde/pull/131) объединён с main. Для [#132](https://github.com/ADatkashov/kunde/pull/132) прошли Security CI и Backend CI. CodeRabbit временно недоступен по квоте. После ревью объединить #132, синхронизировать [#133](https://github.com/ADatkashov/kunde/pull/133) и проверить Flutter CI до слияния. Затем синхронизировать и проверить остальные PR стека.

[Два приложения прошли нативный Android E2E](https://github.com/ADatkashov/kunde/actions/runs/44455026918) на тестовом маршруте. Повторить тест на интегрированной ветке. Для Consumer и Executor запустить Android Release APK (DEV), проверить идентификаторы, сертификаты и SHA-256. Публичная активация требует отдельного решения владельца.

[Контекст и ограничения Rides](docs/product/rides-transport.md) · [Статус проекта](PROJECT_STATE.md)
