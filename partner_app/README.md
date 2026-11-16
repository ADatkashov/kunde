# KUNDE Partner — standalone Flutter application foundation

This is the first, **non-production** foundation for the second of four KUNDE applications, per ADR-019. It is deliberately **not yet a working partner operations client**. The existing embedded Partner hub in `mobile/` remains the functioning DEV implementation until feature parity is verified.

## Run

```bash
cd partner_app
flutter pub get
flutter analyze
flutter test
flutter run
```

## Migration requirements (next implementation PR)

1. Inspect the existing partner hub, auth repository, partner API, app shell and CI before extracting any code.
2. Reuse shared domain/API contracts and the existing backend; avoid duplicating domain business rules or introducing new backend services.
3. Add real authentication and deny-by-default role/membership checks. Unapproved users must never see partner data. Verify server-side authorization.
4. Port partner orders, bookings, availability, stock, menu and price editing, including timeout/alerts, while preserving behavior in the current Consumer DEV APK.
5. Configure distinct Android applicationId and iOS bundle ID, signing and separate release CI. Do not publish or deploy until verification.
6. Cover RU/KK/EN, widget/integration tests, role isolation, refresh/logout, backend smoke and a physical-device handoff.
7. Only after parity and owner verification, remove partner controls from the Consumer app via a separately reviewed migration.

No DEV/PROD backend or database changes in this foundation PR. No APK or CI success is claimed before actual verification.
