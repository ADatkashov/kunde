# Executor · Home Services

Экран мастера «Дом и быт» (`home_services_work_screen.dart`): привязка к мастеру по коду-приглашению, затем визит по порядку — «в пути» (с ETA), «на месте», «начал», «завершил». Сервер проверяет порядок и принадлежность заказа мастеру; клиент показывает только следующее допустимое действие (`HomeServicesWorkScreen.nextAction`).

API (`executor/home-services/…`, модуль `backend/services/homeservices`): `link`, `jobs`, `jobs/{id}/stage`, `jobs/{id}/start`, `jobs/{id}/complete`. ETA при выезде считается по дороге от позиции мастера; без разрешения на геолокацию используется введённый вручную.

Тесты: `cd apps/executor && flutter test test/features/home_services`. Выборочный запуск не заменяет `flutter analyze --fatal-infos` — приложение компилирует все фичи. Что CI запустит для правки этой фичи: `echo apps/executor/lib/features/home_services/x.dart | python3 scripts/ci/detect_affected.py --files-from -` (Executor `home_services` + `executor`, которая импортирует фичу).
