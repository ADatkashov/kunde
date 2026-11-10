# 18 — Localization

Initial launch locale set is Kazakh and Russian in Almaty. English must be supported by architecture and may be enabled after translation coverage review. Locale affects presentation; country-specific policy must not be embedded in shared domain logic.

| Topic | Requirement |
|---|---|
| UI copy | Use translation keys/resources; no user-facing hardcoded strings in production surfaces. Include context, placeholders, plural rules and accessibility labels. |
| Fallback | User-selected locale → device preference if supported → approved market default → English only as controlled fallback. Never mix languages silently within a critical price/consent action; flag missing translation for remediation. |
| Currency | Store integer minor units plus ISO currency code; format per locale and currency metadata. Do not infer currency from language. KZT is expected for Almaty launch but market configuration validates it. |
| Time | Store instants in UTC; display using service location zone and localized date/time format. Confirm ambiguous local time around DST/time-zone rules where relevant. |
| Address | Support local script/Latin variations, apartment/building details, map pin plus textual instructions and normalized service-area reference. Do not require one global address shape. |
| Phone | Normalize with country calling code while preserving user-entered display; verify before use and respect portability. |
| Catalog | Partner supplies localized name/description or approved fallback; identify unavailable translation internally. Search should index approved language variants. |
| Numbers and accessibility | Locale-aware decimal/grouping, units and screen-reader pronunciation. Keep identifiers/codes stable and copyable. |
| Legal/consent | Show current legally approved language version and record version/locale accepted; translations require review. |

## QA acceptance

Critical flows (auth, quote, checkout, payment, cancellation, booking, privacy consent) must be checked in Kazakh and Russian for truncation, numeric/date correctness, pluralization, text scaling and VoiceOver/TalkBack semantics. Missing translation cannot turn a required warning or consent into blank text.
