# Следующая проверка KUNDE Leisure

1. Дождаться зелёных обязательных проверок PR [#177](https://github.com/ADatkashov/kunde/pull/177) и объединить его в `main`.
2. Из `main` собрать подписанные DEV Release APK (Consumer, Partner, Admin, Executor) через `android-release.yml` и `partner-release.yml`, сверить `applicationId`, подпись, SHA-256 и DEV URL.
3. Пройти нативный E2E на эмуляторе (по образцу `auto-native-e2e.yml`): вход → Досуг → каталог → мероприятие → места → тестовая оплата → QR-билет → история → отзыв; снять скриншоты и сравнить с референсом.
4. Параллельно (из прежнего плана): авторизованный Web E2E Control Center #152/#159 и Admin Android E2E.

Команды: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com`; `cd backend && mvn test -Dtest='Leisure*'`; `cd mobile && flutter test test/features/leisure`.
