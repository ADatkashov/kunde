# KUNDE Design System & UX/UI Specification 1.0

**Status:** design recommendation for research and Figma handoff. No Figma file or application UI was created or changed. **Product:** KUNDE — *Everyday, made easier.* **Initial market:** Almaty, Kazakhstan. **Languages:** Kazakh, Russian; English-ready architecture.

## Design direction

Recommended **Calm Teal + Warm Mineral**: deep evergreen interaction color, warm-neutral surfaces, direct typography, restrained motion and category-specific accents. This is a hypothesis, not an approved brand identity. A small set of colors and components ties Consumer, Partner, Provider and Admin together; density and workflow differ by role. No unverified category should appear orderable.

## Specification map

| File | Scope |
|---|---|
| 01–06 | Brand, color, typography, tokens, layout and component system |
| 07–11 | Consumer, category-specific UX, Partner, Provider and Admin experiences |
| 12–14 | Flows, screen inventory and UI states |
| 15–18 | Motion, accessibility, localization and UX writing |
| 19–22 | Figma handoff, design QA, decisions and traceability |
| `wireframes/` | 13 key textual wireframes |
| `assets/design-tokens.json` | Machine-readable cross-platform token proposal |

## Baseline and constraints

Use [PRD 1.0](/E:/ADK/kunde/docs/product/PRD-1.0.md), [PRD 1.1](/E:/ADK/kunde/docs/product/PRD-1.1/01-product-scope.md) and [Technical Architecture 1.0](/E:/ADK/kunde/docs/architecture/README.md) as source. Shared rules: five consumer destinations; eight categories with phased rollout; separate order, booking and payment; explicit AI confirmation for consequential actions; role-scoped privacy; Kazakh/Russian initial localization; network validation for mutations. Architecture recommends Flutter consumer client and web-oriented partner/admin surfaces but does not approve a visual system.

## Document conventions

“Recommended” means proposed for user research and design review. “Required” traces to PRD/architecture. P0/P1/P2 follows PRD 1.1 priority, with category readiness still gated. Screen IDs are stable. Copy examples are source strings and require native-language review before launch. Contrast values were computed using WCAG relative luminance and rounded to two decimals; final rendered states still require independent visual and assistive-technology QA.

## Open items before final design approval

Validate brand direction, logo, font licensing and device coverage; choose imagery/illustration style; test category-card comprehension and consumer navigation with Almaty users; confirm dark-mode demand; confirm operationally supported categories; obtain translations and legal copy; approve final color contrast and responsive breakpoints with real components.
