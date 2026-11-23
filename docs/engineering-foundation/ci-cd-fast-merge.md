# CI/CD: быстрый merge, APK сразу после merge, асинхронные E2E

Цель: тяжёлые проверки (эмулятор, visual, интеграционные) **не блокируют** merge и получение подписанного DEV Release APK.
Успешная сборка APK **не** означает, что E2E пройден: статус E2E всегда указывается отдельно.

## Что запускается автоматически

| Этап | Workflow | Когда |
|---|---|---|
| A. FAST CI | `Backend CI`, `Flutter CI`, `Partner Flutter CI`, `Security CI`, `CI configuration`, `Infrastructure` | PR и push в `main` (Backend/Flutter — по paths) |
| C. APK | `Release APK on merge (DEV)` (`release-apk-on-merge.yml`) | push в `main`, сразу после merge; не ждёт E2E |

`release-apk-on-merge.yml` определяет, что собирать, по изменённым файлам (`scripts/ci/release_targets.py`, покрыт тестами):

- `mobile/**` — общий код Consumer/Executor/Admin → собираются все три; изменение только `executor_main.dart` / `admin_rides_main.dart` / `main.dart` → только этот клиент;
- `partner_app/**` → Partner; `packages/kunde_design/**` и сами release-workflow → все четыре;
- backend/docs → APK не собирается.

Каждый APK собирает существующий `android-release.yml` (Partner — `partner-release.yml`): подписанный Release (не Debug), секреты
`ANDROID_KEYSTORE_*`/`ANDROID_KEY_*`, DEV backend `https://kunde-backend-ty81.onrender.com/api/v1/`, проверка `apksigner`/`aapt`,
отладочная подпись и локальные URL отклоняются. Артефакт `KUNDE-dev-release` / `KUNDE-executor-dev-release` /
`KUNDE-admin-dev-release` / `KUNDE-Partner-dev-release` хранится 14 дней вместе с `commit.txt`, `version.txt`, `.sha256`.
В Summary запуска: commit SHA, versionName, versionCode, ссылка на запуск и явная пометка **«E2E NOT RUN»**.

## Что запускается только вручную

`E2E suite (manual, async)` (`e2e-suite.yml`) — Actions → Run workflow. Поля: `ref` (SHA/ветка/тег; пусто = выбранная ветка) и флажки:

| Флажок | Что запускается |
|---|---|
| `consumer` | auto, education, groceries, health, leisure |
| `partner` | groceries-roles (Partner fulfilment) + `partner-android` |
| `executor` | delivery two-app |
| `admin` | education-roles (Partner/Admin/Executor) |
| `taxi` | rides two-app |
| `maps` | Taxi with KUNDE Maps |
| `multi_app` | delivery, rides, education-roles, groceries-roles |
| `emulator` | Android identity E2E |
| `visual` | before/after скриншоты (база — `merge-base` с `origin/main` или поле `base-sha`) |
| `backend` | полный `Backend CI` (mvn verify + smoke) |
| `all` | всё перечисленное |

Те же workflow можно запускать по одному (`workflow_dispatch`) или вызывать через `workflow_call`; у всех есть вход `ref`.
Итог: таблица в Summary — `PASSED` / `FAILED` / `NOT RUN`; пропущенная проверка никогда не считается пройденной,
`report` красный при любом падении.

Больше **не** запускаются автоматически на PR/push: Android visual, Auto/Delivery/Leisure/Education/Groceries/Health/Rides E2E, Partner Android APK build.

## Параллельность и concurrency

- E2E-группы: `<workflow>-<event>-<ref>`, `cancel-in-progress: false` — разные запуски/ветки/коммиты не отменяют друг друга;
- release-группа: `release-apk-<event>-<sha>` — два merge подряд дают два APK, ничто не отменяется;
- у Release APK и E2E нет `needs` друг на друга; раньше `rides-native-e2e.yml` собирал APK только после успешного E2E — эта связка удалена.
- `Backend CI` отменяет предыдущий запуск только для PR/push, ручной и вызванный из suite — нет.

## Процесс

1. PR → FAST CI зелёный, нет конфликтов, нет нерешённых критических замечаний CodeRabbit.
2. Squash merge в `main` (branch protection не обходится).
3. Автоматически собираются APK → скачать из Actions → Artifacts, проверить на телефоне.
4. Параллельно запустить `E2E suite` на SHA merge-коммита.
5. Падение E2E → логи/скриншоты из артефактов → причина → исправление дефекта (тесты не отключаются) → отдельный PR →
   FAST CI → merge → при затронутом Android-клиенте новый APK. Без бесконечных повторных запусков: нерешённая ошибка
   сообщается явно, E2E остаётся `FAILED`. Критический security-дефект, риск потери данных или ошибка оплаты — остановить продвижение версии и сообщить владельцу.

Ручной запуск GitHub Actions сам по себе не запускает Claude Code: для автономного исправления нужна активная сессия агента.

## Branch protection (проверить владельцу)

Интеграция агента получает 403 на чтение branch protection/rulesets — состояние **не проверено**. Required checks должны быть:
`Backend CI / backend`, `Flutter CI / flutter`, `CI configuration / configuration`, четыре job `Security CI`
(`dependencies`, `secrets`, `containers`, `sdk-tooling` — см. TASK-003). Из required нужно убрать (если были добавлены):
`Android visual comparison`, `Rides two-app Android E2E`, `Auto/Delivery/Leisure/Education/Groceries/Health … E2E`,
`Partner Android APK (DEV)` — эти workflow больше не создают проверок на PR, и обязательная проверка зависла бы в «Expected».
