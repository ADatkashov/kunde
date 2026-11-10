# 17 — Localization and Internationalization

Initial user locales: Kazakh (`kk-KZ`) and Russian (`ru-KZ`); English (`en`) is supported architecturally. Language may differ from region/currency. Never infer country solely from language.

## Translation system

- All interface strings use stable keys such as `checkout.total`, `payment.pending.no_retry`, `booking.slot.expired`; no text embedded in image or hardcoded in a component.
- Resource files carry context/description, interpolation variables, plural rules and translator notes. Keep URLs, IDs and product names as appropriate.
- Language selection is in onboarding/profile and applies immediately, including accessibility labels/notifications where possible. Consent acceptance stores language and legal version.
- Fallback: selected locale → approved market default → English only if translated and safe. Missing strings in payment/consent/cancellation block release; no silent mixed-language critical content.
- Dynamic text avoids concatenation; translator controls grammar and word order. Use ICU plural/select patterns. Avoid hard line breaks and fixed-height text.

## Formatting

Dates/times follow locale and service time zone; transaction instants remain UTC in data. Display zone (e.g., “Almaty time”) for cross-city appointment. Currency is KZT for initial-market examples, rendered with locale-aware grouping and code/symbol disambiguation; no localized amount is sent back as a numeric value. Numbers/decimal units use locale APIs. Phone entry uses country calling code independent of UI language.

## Address, text direction and future readiness

Address input supports local scripts, apartment/entrance details, transliteration variants and map pin + text; never assume Western street/postcode ordering. Layout uses logical start/end, directional icons mirrored only when semantic, and text-run direction isolation for phone/ID. No current requirement for RTL; use framework localization primitives to avoid blocking future RTL markets.

## QA

Review Kazakh and Russian by native linguists; check line expansion, plural forms, gender/case, button width, search placeholder, voice/screen-reader pronunciation and lock-screen privacy. Regression screenshots are captured on compact/large Android and iPhone devices plus desktop Partner/Admin widths. Region-specific tax/currency/address rules come from market configuration, not translation resource.
