# Developer Guide: где искать код

Правила — [CONSTITUTION](CONSTITUTION.md); карта доменов — [domain-registry](domain-registry.md). Этот файл — быстрые ответы.

**Нашёл баг в Delivery.** Backend: `backend/services/delivery/src/main/java/kz/kunde/delivery` (ядро — `backend/platform`, composition root и Flyway — `backend/app`). API: `/api/v1/deliveries`, `/executor/deliveries`, `/admin/deliveries`, `/partner/partners/{id}/deliveries`. Flutter: `mobile/lib/features/delivery`, `delivery_admin`, `executor/delivery_work_screen.dart`; `partner_app/lib/features/delivery`. Тесты: юнит — `backend/services/delivery/src/test`, со Spring/БД — `backend/app/src/test/java/kz/kunde/delivery`, `mobile/test/features/delivery`.

**Новый домен.** Запись в реестре → модуль/пакет → префикс таблиц в `table-owners.txt` → feature flag через `FeatureGate` → тесты. Пустые модули не создаём.

**Нужны данные чужого домена.** Не SQL и не импорт внутренностей: контракт владельца (пример — `platform.partner.PartnerDirectory`, ADR-021). Новая связь без записи в baseline роняет `ArchitectureBoundariesTest`.

**Проверки перед PR.** `cd backend && ./gradlew test --tests 'kz.kunde.architecture.*'`; для Flutter — `flutter analyze` и тесты затронутой фичи.
