# 04 — Design Tokens

Machine-readable proposal: [`assets/design-tokens.json`](assets/design-tokens.json). JSON values are canonical for this specification draft; all values remain subject to visual review. Token names are stable semantic references; do not hard-code values in component specs.

## Token groups

- **Color:** primitives and semantic aliases per Light/Dark theme; semantic status color includes icon/text treatment.
- **Typography:** family, weight, size, line-height, letter spacing and numeric features.
- **Space:** 4 px base, steps 0–16 (0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96).
- **Size:** control height, icon size, touch target, sheet width, content max widths.
- **Radius:** 4, 8, 12, 16, 20, 24, pill (9999).
- **Elevation:** surface levels via border/tone plus restrained shadows; shadow may be reduced in dark mode.
- **Border:** 1 px standard, 2 px focus/selected as needed; semantic color.
- **Opacity:** disabled 0.48 only for nontext decoration; scrim values are in theme tokens; never lower text opacity as hierarchy.
- **Breakpoints:** compact <360, mobile 360–599, tablet 600–899, desktop 900–1199, wide ≥1200 logical/CSS px; validate layouts per platform.
- **Motion:** 100/160/220/280 ms; named easing; reduced-motion override.
- **Z-index:** base 0, sticky 10, nav 20, menu 30, scrim 40, modal/sheet 50, toast 60, critical dialog 70.
- **Icon sizes:** 16, 20, 24, 32, 40; default interactive icon 24 px in ≥44/48 px target.

## Naming and implementation mapping

Format: `color.light.text.primary`, `space.4`, `type.body.medium`, `radius.card`, `motion.duration.standard`. Flutter maps semantic groups to `ThemeExtension`/ColorScheme plus typed spacing/type extensions; Web exports CSS custom properties under `--kunde-*`. Keep a single source file or generated outputs to prevent platform drift. Token generation/build scripts are not created in this specification stage.
