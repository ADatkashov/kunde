# Следующие проверки

## KUNDE Leisure

1. Установить подписанные DEV APK из [PROJECT_STATE](PROJECT_STATE.md) на устройство, пройти Consumer-сценарий (Досуг → места → TEST_CARD → QR) и Partner/Executor/Admin; сверить скриншоты с референсом (`reports/leisure-native` в артефакте E2E).
2. Выяснить, почему эмулятор CI теряется при запуске приложения против выключенного `LEISURE_ENABLED`, и вернуть шаг `ui_flag_off` в блокирующие.
3. Команды: `python3 scripts/dev/leisure_smoke.py https://kunde-backend-ty81.onrender.com`; `cd backend && mvn test -Dtest='Leisure*'`; `cd mobile && flutter test test/features/leisure`.

## Health & Wellness

Закрыть многоролевую приёмку синтетического Health в DEV. Перед выпуском проверить оставшиеся фильтры и выездные wellness-задания, отзывы, жалобы и возвраты. Выполнить нативные сценарии Partner и Admin, проверить утверждённый аккаунт с `HEALTH_OPERATIONS`, установку подписанных APK, TalkBack и полный RU/KK/EN. Consumer Android уже прошёл сценарий каталога, записи с тестовой картой и отмены. Результаты и оставшиеся продуктовые сценарии ведутся в [Health PRD](docs/product/health-wellness.md).

## KUNDE Control Center

Выполнить авторизованный Web E2E совмещённых #152/#159 на DEV с утверждённым синтетическим сотрудником. Критерии: вход, обзор и сводка Delivery, разрешённый реестр сотрудников, отказ 401/403 и выход. После зелёных обязательных проверок объединить #159 в `feat/delivery-admin-web`, затем заново проверить и объединить #152 в `main`.

Из итогового main запустить [Android Release APK (DEV)](https://github.com/ADatkashov/kunde/actions/workflows/android-release.yml) с `admin=true`, `executor=false` и штатным DEV API. Сверить исходный коммит, `com.kunde.admin`, release-подпись, отсутствие debug-настроек, размер и SHA-256 файла. Подтвердить установку и пройти Admin Android E2E, когда доступно тестовое устройство и синтетическая учётная запись.
