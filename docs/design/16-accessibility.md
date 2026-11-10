# 16 — Accessibility (WCAG 2.2 AA target)

Design and QA target WCAG 2.2 AA for web and equivalent platform accessibility patterns on iOS/Android. Conformance requires implementation testing; this specification alone does not establish compliance.

## Visual and motor

- Normal text contrast ≥4.5:1; large text ≥3:1; essential control boundaries/icons ≥3:1. Use color-system pairings and recheck overlays/states.
- Do not rely on color, position, sound, shape or animation alone; combine with text/icon/structure.
- Touch targets are at least 44×44 logical px; prefer 48×48 on primary controls. Spacing prevents accidental adjacent activation.
- Focus indicator is visible, high-contrast and not clipped/hidden by sticky bars or sheets. Keyboard focus order follows reading order; no keyboard trap except modal with escape/close and focus restoration.
- At 200% text scaling/reflow, keep content/actions available without clipped text or two-dimensional scroll except data requiring it with accessible alternative.
- Do not use very small text for essential price, cancellation, identity, warning or payment information.

## Screen reader and forms

- Semantic heading hierarchy, labels, buttons, list/timeline relationships and selected/expanded/disabled states.
- Every icon-only control has concise action name; decorative illustration is hidden from accessibility tree. Dynamic status is announced once.
- Forms have persistent labels, linked helper/error text, input format hints, autocomplete and field-level plus summary errors. Do not identify invalid input by color only. OTP fields support paste/autofill and one logical accessible control.
- Statuses are spoken with type + text (“Payment pending”), not ambiguous “green check”. Currency, time zone, rating count and address context are verbalized accurately.
- Voice input is an optional path; text entry remains available. Speech permission is requested in context and recording state is clear.

## Maps, motion and cognitive access

Maps must have a text/list alternative with address, distance, serviceability and route status. Location can be entered manually. Respect reduced motion; haptics never provide sole feedback. Keep language simple, one primary action at a time, predictable controls and clear recovery. Avoid timed forms; where a hold must expire, display countdown and a way to request a new slot.

## QA evidence

Test with VoiceOver, TalkBack, keyboard-only web, browser zoom, 200% font, high-contrast settings and reduced-motion mode. Use automated contrast tooling plus manual review of focus, status, map fallback, error announcements and dynamic content. Include participants with disabilities before public launch; resolve critical blockers.
