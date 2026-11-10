# 03 — Typography

## Font recommendation

Use **Noto Sans** as the recommended cross-platform primary family for the first design handoff. Google Fonts metadata lists `cyrillic-ext`; the upstream glyph set explicitly includes the Kazakh and Russian Cyrillic characters needed by KUNDE ([Noto Sans metadata](https://github.com/google/fonts/blob/main/ofl/notosans/METADATA.pb), [Cyrillic glyph set](https://github.com/googlefonts/glyphsets/blob/main/GLYPHSETS.md)). Verify the exact shipped font file/subset and render it on supported devices before production. Keep system sans-serif as a fallback. **Inter** may be evaluated as an alternative only after testing the shipped build for `Ә Ғ Қ Ң Ө Ұ Ү Һ І ә ғ қ ң ө ұ ү һ і`, licensing, metrics and fallback behavior. Do not mix unrelated scripts at arbitrary weights.

## Type scale

Use a 4 px baseline grid, responsive sizes and relative scaling. Font weights: 400 regular, 500 medium, 600 semibold, 700 bold. Avoid weights below 400 for user-facing copy.

| Style | Mobile size / line | Web size / line | Weight | Typical use |
|---|---:|---:|---:|---|
| Display L | 36 / 42 | 48 / 56 | 700 | Rare consumer home hero |
| Display M | 30 / 36 | 40 / 48 | 700 | Major page title |
| H1 | 28 / 34 | 32 / 40 | 700 | Screen title |
| H2 | 24 / 30 | 28 / 36 | 700 | Section title |
| H3 | 20 / 26 | 22 / 30 | 600 | Card/detail group title |
| H4 | 18 / 24 | 18 / 26 | 600 | Subsection |
| Body L | 17 / 25 | 18 / 28 | 400 | Intro, key explanatory copy |
| Body M | 16 / 24 | 16 / 24 | 400 | Default body and inputs |
| Body S | 14 / 20 | 14 / 20 | 400 | Supporting text; avoid for long reading |
| Label L | 14 / 20 | 14 / 20 | 600 | Buttons and prominent field labels |
| Label M | 13 / 18 | 13 / 18 | 600 | Navigation/chips |
| Caption | 12 / 16 | 12 / 16 | 500 | Metadata only; not essential long instructions |
| Numeric display | 28–36 / 1.1 | 32–40 / 1.1 | 700 | Total/metric, tabular numerals |

Use neutral letter spacing: headings −0.2 to −0.4 px only after visual check; body 0; uppercase micro-labels +0.4 px sparingly. Use tabular numerals for prices, dates and dashboard metrics; align currency separately where localization requires. Never make amount meaning depend on alignment alone.

## Localization and layout behavior

Kazakh and Russian text often expands or changes word shape; controls grow vertically, wrap naturally and preserve logical reading order. Avoid fixed-height text containers and hand-inserted line breaks except brand/editorial display. Support system text scaling to 200% without clipping or lost actions. Test mixed Latin product names with Cyrillic sentences, phone numbers, addresses and KZT formatting. Fonts must be tested on actual iOS/Android and browser devices for hinting, baseline and fallback consistency.
