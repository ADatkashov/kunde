# Next task — verify Consumer authentication on native devices

After PR #5, validate the implemented Flutter authentication flow against the
isolated Keycloak Consumer realm on Android and iOS. Preserve ADR-015 production
gates. See docs/identity/consumer-validation/README.md for configuration and
existing protocol/test evidence.

Acceptance: actual system-browser login and registration, PKCE callback, secure
vault persistence after app restart, profile load/edit, rotated refresh, offline
retry, session expiry, provider logout and subsequent credential prompt. Exercise
RU/KK/EN, screen readers, keyboard and large text. Record screenshots and sanitized
results; never publish tokens or synthetic-user passwords. iOS release signing
and real deployment endpoints need owner-managed configuration.

Use the current backend/Flutter test suites and hosted workflows as regression
checks. The manual Android identity E2E workflow currently reports missing native
scenario prerequisites; implement those before claiming native E2E success.
