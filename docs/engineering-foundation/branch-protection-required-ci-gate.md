# Подключение «Required CI Gate» к branch protection (инструкция владельцу)

Агент не имеет прав на branch protection/rulesets (GitHub отвечает 403), поэтому настройку выполняет владелец репозитория. Ничего из существующих правил отключать не нужно.

## Что такое Gate

Check `Required CI Gate` (workflow `CI PR gate`, `ci-pr.yml`) создаётся на **каждом** PR без path-фильтра. Он ждёт и проверяет остальные проверки коммита: нужные по `paths:` workflow должны завершиться `success`, `skipped` допустим только у jobs с `if:`, а шаги Backend/Flutter, которые детектор требует (`Verify and package`, `Test …`), не должны быть пропущены. Подробные правила — [ADR-027](../architecture/adr/ADR-027-product-based-selective-ci.md) и docstring `scripts/ci/required_gate.py`.

## Шаги (Settings → Branches / Rules)

1. **Убедитесь, что Gate уже отработал хотя бы на одном PR** (после merge PR с `ci-pr.yml` откройте любой новый PR): GitHub предлагает в поиске required checks только те, что уже запускались.
2. Откройте **Settings → Branches** (или **Settings → Rules → Rulesets**), правило для ветки `main`. Если правила нет — создайте, ничего другого не включая.
3. Включите **Require status checks to pass before merging**.
4. В поиске выберите **`Required CI Gate`** (источник — GitHub Actions) и сохраните. **Существующие required checks оставьте** на первое время: Gate их дополняет, а не заменяет.
5. Рекомендуется **Require branches to be up to date before merging**: Gate проверяет именно head-коммит PR.
6. Не добавляйте в required: `sdk-tooling` (пропускается по `if`), E2E-workflow (`*-native-e2e`, `product-e2e`, `e2e-suite`) — они ручные и не создают check на PR.

## После нескольких успешных PR (по решению владельца)

Когда Gate подтвердит себя на 5–10 PR, отдельные path-фильтруемые checks (`backend`, `flutter`, `executor-flutter`, `admin-flutter`, `partner-flutter`, `validate`) можно убрать из required: при их отсутствии на PR они остаются «Expected» и блокируют merge, а Gate уже требует их, когда они нужны. Оставьте `Required CI Gate` и всегда выполняющиеся `configuration`, `secrets`, `dependencies`, `containers`.

## Проверка и откат

- Проверка: откройте PR, дождитесь `Required CI Gate` — зелёный; специально сломайте тест в тестовом PR — Gate должен стать красным и заблокировать merge.
- Состояние защиты: `gh api repos/ADatkashov/kunde/branches/main/protection --jq '.required_status_checks'` (нужны права администратора).
- Откат: удалите `Required CI Gate` из списка required checks; сам workflow на merge не влияет, пока check не обязателен.
- Если Gate «завис» (до 40 минут ожидания по таймауту), смотрите его лог: строки `wait …` называют workflow/job, которых не хватает; `FAIL …` — что именно блокирует.
