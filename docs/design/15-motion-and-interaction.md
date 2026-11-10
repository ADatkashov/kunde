# 15 — Motion and Interaction

Motion communicates hierarchy, continuity and state; it must not delay task completion or imply a status that has not occurred. Durations in `04-design-tokens.md` are starting values and must be checked on low-end devices.

| Interaction | Duration/easing | Behavior |
|---|---|---|
| Button press | 100 ms standard ease | Immediate scale/tonal feedback; never delay network command |
| Small state/content change | 160 ms standard | Crossfade/height change only when it clarifies update |
| Bottom sheet | 220 ms enter/exit | Spring-like but restrained; drag is optional, close button always present |
| Page transition | 220–280 ms platform-consistent | Preserve spatial relationship; avoid long horizontal transition between primary tabs |
| Success feedback | 160–220 ms | Check/icon + text; no confetti for payments/refunds or serious service actions |
| Skeleton shimmer | 1.2–1.6 s loop, low contrast | Disable under reduced motion; static skeleton is acceptable |
| Progress | Continuous only when real progress is measurable | Use indeterminate if provider time is unknown; never invent percentage |

## Interaction rules

- Touch feedback begins within one frame; pressed state uses tone/shape; double tap cannot issue duplicate command because server idempotency remains mandatory.
- Gestures supplement visible controls. Swipe cannot be the only way to cancel/delete; map gestures have a list alternative.
- Haptics are brief and reserved for meaningful selection/confirmed transitions; never substitute for visual/audio state. Respect OS haptic/reduced-motion settings.
- Drag-and-drop in calendars/tables previews change and awaits server acceptance; conflicts revert with explanation.
- Destructive actions use a deliberate review step; no shake/flash/error animation.
- Avoid auto-advancing carousels, parallax, looping decorative motion and animation that hides status or interrupts reading.

## Reduced motion

When OS reduced-motion is enabled, remove parallax, scaling, long transitions and shimmer; use instant/short opacity or state change. All information remains available without animation. Respect “remove animations” platform settings and web `prefers-reduced-motion`.
