# 30 — Architecture Risks

| Risk | Likelihood / impact | Mitigation and decision owner |
|---|---|---|
| No suitable verified Kazakhstan region/service for chosen managed stack | Medium / critical | Procurement/legal data-flow audit before vendor selection; choose in-country deployment and minimize external PII |
| Payments/order handoff creates duplicate charge or orphan transaction | Medium / critical | Idempotency, verified state, outbox/saga, immutable journal, reconciliation and fault-injection tests; Finance/Engineering |
| Marketplace supply/fulfillment is not operationally ready | High / high | Gate each category; pilot cohort/operations runbook; Product/Operations |
| Modular boundaries degrade into shared database monolith | Medium / high | Schema ownership, module dependency rules, architecture tests, code owners; Engineering |
| Team lacks mobile/Flutter or Spring production expertise | Unknown / high | Skills/capacity assessment and prototype before commitment; CTO |
| Managed infrastructure chosen without acceptable KZ data location | Medium / critical | Verify primary, backup, logs, support and AI processing locations contractually; Legal/Security |
| Search index stale causes unavailable items/appointments | Medium / medium | Canonical revalidation at checkout/booking and freshness timestamp; Catalog/Search |
| Model output leaks data or triggers unintended tool action | Medium / critical | Permission-scoped tool gateway, no DB access, explicit confirmation, redaction, adversarial eval; AI/Security |
| Family/child/health data exposed across roles | Low-medium / critical | Separate scopes, guardian validation, sensitive data review and delayed category launch; Privacy/Legal |
| Vendor lock-in/payment/map/model integration limits market expansion | Medium / high | Capability adapters, export/exit tests, portable domain IDs and provider contract review; Architecture |
| Premature platform infrastructure increases cost/on-call | Medium / medium | Defer Kafka/K8s/search/cache until measured trigger; CTO/Operations |
| Unclear retention/deletion conflicts with financial audit | Medium / high | Data inventory and field-level retention/legal hold policy before launch; Legal/Finance |

Risk owners and acceptance dates are TBD; architecture approval should assign them. No vendor availability or team capacity is assumed.

## Реестр рисков микросервисной готовности (2026-11-24)

Источник — аудит кода ([microservice-readiness](microservice-readiness.md)); владелец по умолчанию — Engineering до назначения; статус «открыт» пока не отмечено иное.

| ID | Риск | Вероятность / влияние | Доказательство | Митигирование | Статус |
|---|---|---|---|---|---|
| R-01 | Модульный монолит вырождается в общую БД с чужим SQL | Средняя / высокое | 102 SQL-связи, 123 FK между владельцами | Ратчеты (`fitness-functions`), перенос SQL в контракты | Контролируется ратчетами |
| R-02 | Единый узел циклов из 10 пакетов не позволяет выделять домены по одному | Высокая / высокое | `known-coupling-cycles.txt` | Вынос демо-сидов, расширение `BookingCategory`, порт Mobility | Открыт |
| R-03 | Admin связывает домены по SQL | Высокая / высокое | 44 SQL + 9 импортов | `<Domain>AdminApi` | Открыт |
| R-04 | Первое событие окажется финансовым, DLQ без инструмента разбора блокирует агрегат | Низкая / критичное | ADR-022, V16 | Нефинансовые продюсеры первыми, инструмент DLQ и retention до включения relay | Открыт |
| R-05 | Нет сквозной трассировки: сбой между модулями/сервисами не диагностируется | Средняя / среднее | только MDC `correlationId` | `correlation_id` в событиях и исходящих вызовах; OpenTelemetry при первом выделении | Открыт |
| R-06 | Изменение DTO ломает установленные APK (контрактных тестов нет) | Средняя / высокое | Конституция §8 | Снимок OpenAPI + проверка совместимости | Открыт |
| R-07 | Преждевременное выделение увеличит стоимость и дежурство | Средняя / среднее | Render Free, один экземпляр | Триггер ADR-025 | Контролируется решением |
| R-08 | DEV отстаёт от `main` (деплой `e2e9c5b`, PR #245), совместимость новых APK с DEV не проверена | Высокая / среднее | Render: последний live-деплой 2026-11-23 | Деплой DEV после разрешения владельца, затем smoke | Открыт |
| R-09 | Нестабильные E2E скрывают регрессии | Средняя / среднее | `executor_delivery` в полном наборе | Повтор нажатия при отключённой кнопке (исправлено в тесте), наблюдение | Исправлено в тесте, проверить |

