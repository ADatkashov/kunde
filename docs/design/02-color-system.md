# 02 — Color System

Proposed Calm Teal + Warm Mineral palette. Tokens describe semantic roles; components must consume semantic tokens, not invent one-off hex values. HEX is sRGB. Contrast uses WCAG 2.x relative luminance. Normal text target ≥4.5:1; large text ≥3:1; essential non-text UI boundaries/icons ≥3:1 against adjacent color. Color never carries status alone.

## Light theme

| Token | HEX | Intended use | Constraints |
|---|---|---|---|
| `light.brand.primary` | `#0B6B5E` | Primary CTA, selected navigation, links | On white: 6.40:1; on warm canvas: 5.96:1. White label text passes. |
| `light.brand.primaryHover` | `#07574D` | Hover/pressed web state | Use with white label; do not encode disabled state with it. |
| `light.brand.secondary` | `#2E8174` | Secondary brand graphics | Check exact surface pairing before text use. |
| `light.brand.accent` | `#C66A22` | Decorative highlights, category accents | On white: 3.83:1; decorative/non-text only. Never use for normal-size text on light surface. |
| `light.canvas` | `#F6F7F4` | App background | Avoid large pure-white empty canvas where warm base improves grouping. |
| `light.surface` | `#FFFFFF` | Cards, sheets, form fields | Primary content surface. |
| `light.surfaceSubtle` | `#EEF2EF` | Grouped sections, chip backgrounds | Text still uses approved contrast foreground. |
| `light.surfaceRaised` | `#FFFFFF` | Dialogs/popovers | Elevation/shadow and border distinguish from canvas. |
| `light.textPrimary` | `#17221F` | Headings/body | On canvas: 15.20:1. |
| `light.textSecondary` | `#465650` | Supporting text | On canvas: 7.21:1. |
| `light.textTertiary` | `#5C6B65` | Captions, metadata | On canvas: 5.21:1; do not reduce opacity. |
| `light.textOnBrand` | `#FFFFFF` | Text/icons on primary fill | Primary fill contrast 6.40:1. |
| `light.borderSubtle` | `#CBD5D0` | Decorative card separators | 1.50:1 on white; not used as the sole boundary for an essential control. |
| `light.borderControl` | `#7A8782` | Inputs/selected control outline when boundary is necessary | 3.74:1 on white; use with visible label/focus state. |
| `light.focus` | `#0B6B5E` | 2 px keyboard focus ring | Maintain visible offset; do not clip. |
| `light.success` | `#176B52` | Success icon/text/status | On white: 6.44:1; pair with check icon and label. |
| `light.warning` | `#8A5700` | Warning icon/text | On white: 6.10:1; pair with warning icon and plain-language message. |
| `light.error` | `#B9382D` | Error/destructive text/icon | On white: 5.73:1; confirm destructive action. |
| `light.info` | `#1769AA` | Informational status | On white: 5.77:1; pair with info icon/label. |
| `light.disabledSurface` | `#E8ECE9` | Inactive control fill | Use native disabled semantics; not for low-contrast text. |
| `light.disabledText` | `#5C6B65` | Disabled label | Preserve legibility; disabled is additionally indicated by control state. |
| `light.overlay` | `#101A17` at 56% | Scrim behind modal/sheet | Must not obscure modal focus or convey content. |

## Dark theme

| Token | HEX | Intended use | Constraints |
|---|---|---|---|
| `dark.brand.primary` | `#77D8C2` | Primary action/selection | On `#121916`: 10.53:1; use dark foreground `#121916` on filled button. |
| `dark.brand.primaryHover` | `#91E0CF` | Hover/pressed | Keep interaction state distinct by shape/state too. |
| `dark.brand.secondary` | `#4BC99A` | Secondary emphasis/successful brand graphic | On dark canvas: 8.60:1. |
| `dark.brand.accent` | `#FFD166` | Decorative warm accent | Avoid large luminous fills; use dark text if used as a control fill. |
| `dark.canvas` | `#121916` | App background | Avoid pure black; reduce glare. |
| `dark.surface` | `#18211D` | Cards and inputs | Separate from canvas with border/elevation. |
| `dark.surfaceRaised` | `#202A25` | Dialogs/menus | Elevation is conveyed with tone and boundary. |
| `dark.surfaceSubtle` | `#26312C` | Chips/grouped rows | Text remains high contrast. |
| `dark.textPrimary` | `#F2F5F2` | Main content | On canvas: 16.25:1. |
| `dark.textSecondary` | `#C2CDC8` | Supporting content | On canvas: 10.93:1. |
| `dark.textTertiary` | `#AEBBB5` | Metadata | On canvas: 8.99:1. |
| `dark.textOnBrand` | `#121916` | Label on mint primary | Contrast on `#77D8C2` exceeds 10:1. |
| `dark.borderSubtle` | `#43514A` | Decorative card separators | 1.97:1 on surface; not the sole boundary for an essential control. |
| `dark.borderControl` | `#64736C` | Inputs/selected control outline when boundary is necessary | 3.30:1 on surface; use with visible label/focus state. |
| `dark.focus` | `#91E0CF` | Keyboard focus | 2 px ring and offset, not clipped. |
| `dark.success` | `#4BC99A` | Success | On canvas: 8.60:1; pair with icon/text. |
| `dark.warning` | `#FFD166` | Warning | On canvas: 12.38:1; pair with warning label/icon. |
| `dark.error` | `#FF7A70` | Error/destructive | On canvas: 7.03:1; never color-only. |
| `dark.info` | `#75B8FF` | Information | On canvas: 8.55:1; pair with icon/text. |
| `dark.disabledSurface` | `#26312C` | Inactive controls | Preserve native disabled semantics. |
| `dark.disabledText` | `#AEBBB5` | Inactive label | Legibility retained; state also shown structurally. |
| `dark.overlay` | `#000000` at 64% | Modal scrim | Keep underlying context discernible but inactive. |

## Contrast verification summary

Computed representative text pairs: light primary/white 6.40:1; primary/canvas 5.96:1; secondary text/canvas 7.21:1; tertiary text/canvas 5.21:1; error/white 5.73:1; warning/white 6.10:1; dark primary/canvas 10.53:1; dark primary on dark surface 9.72:1; dark primary foreground on-brand fill 10.53:1; dark secondary text/canvas 10.93:1. Essential control borders: light 3.74:1 on white; dark 3.30:1 on surface. Values round to two decimals. Accent orange is decorative-only on light backgrounds. Full UI contrast must be retested after opacity, overlays, images and disabled states are composed. Do not lower text opacity to simulate hierarchy.
