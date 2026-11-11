# KUNDE design context

## Product and audience
Consumer mobile app for everyday life in Almaty, then Kazakhstan. Russian,
Kazakh and English. Authentication opens the system browser; the app never asks
for a password. Sources: ADR-015 and docs/identity/api-contracts.md.

## Visual direction
Retain the existing KundeTheme: green #0B6B5E, canvas #F6F7F4, ink #17221F,
white #FFFFFF. Material color schemes own semantic and dark-mode colors.
A morning sun on the welcome screen connects the everyday-life promise with
Almaty; use no invented marketplace services or availability claims.

## Typography and layout
Use platform fonts with Cyrillic/Kazakh coverage, existing 30/24/20 display scale
and 17/16 body scale. Brand K uses a restrained heavy display weight. Form fields
and controls use Material typography. Content scrolls within safe areas, bounded
at 520 px for welcome and 600 px for profile. Controls have at least 48 px targets.

## Runtime ownership
mobile/lib/shared/theme/kunde_theme.dart owns tokens; screens consume ThemeData.
KundeLocalizations owns foundation messages, AuthStrings owns authentication
messages. Material components own focus, keyboard, dialogs and state semantics.
See UX-CONTRACT.md for behavior and mobile/test/features/identity for coverage.

## Avoid
No credential forms, token/claim diagnostics, fabricated services, remote fonts,
forced animations or colors that bypass semantic theme roles.
