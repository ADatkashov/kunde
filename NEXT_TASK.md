# Следующие проверки

## KUNDE Leisure

1. После слияния Flutter-PR [#177](https://github.com/ADatkashov/kunde/pull/177) собрать подписанные DEV Release APK (Consumer, Executor, Admin — `android-release.yml`; Partner — `partner-release.yml`), сверить `applicationId`, подпись, SHA-256, DEV URL и коммит.
2. Нативный E2E на эмуляторе (по образцу `auto-native-e2e.yml`): вход → Досуг → каталог → мероприятие → места → тестовая оплата → QR-билет → история → отзыв; скриншоты и сверка с референсом. Не выполнялся.
3. Команды: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com`; `cd backend && mvn test -Dtest='Leisure*'`; `cd mobile && flutter test test/features/leisure`.

## Health & Wellness

На интегрированном коммите прогнать Backend/Flutter/Security CI и синтетический сценарий Health в существующем DEV. Подтвердить эффективный флаг, слот, повтор команды, тестовый ledger, перенос, отмену и отказ другому пользователю. Проверить интеграцию Partner и Admin, затем зафиксировать нативные проверки Android и подписанные DEV APK. [Контракт и границы пилота](docs/product/health-wellness.md).

## KUNDE Control Center

Выполнить авторизованный Web E2E совмещённых #152/#159 на DEV с утверждённым синтетическим сотрудником. Критерии: вход, обзор и сводка Delivery, разрешённый реестр сотрудников, отказ 401/403 и выход. После зелёных обязательных проверок объединить #159 в `feat/delivery-admin-web`, затем заново проверить и объединить #152 в `main`.

Из итогового main запустить [Android Release APK (DEV)](https://github.com/ADatkashov/kunde/actions/workflows/android-release.yml) с `admin=true`, `executor=false` и штатным DEV API. Сверить исходный коммит, `com.kunde.admin`, release-подпись, отсутствие debug-настроек, размер и SHA-256 файла. Подтвердить установку и пройти Admin Android E2E, когда доступно тестовое устройство и синтетическая учётная запись.
