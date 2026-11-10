# KUNDE repository guidance

## Required context before work

Before every new or resumed task, read [`PROJECT_STATE.md`](PROJECT_STATE.md) and [`NEXT_TASK.md`](NEXT_TASK.md), then check the relevant source docs and ADRs they link to. Treat them as a compact index, not authority over current code.

## Stack and layout

- `backend/`: Java 21, Spring Boot 3.5.7, Maven, modular-monolith API, PostgreSQL/Flyway.
- `mobile/`: Flutter/Dart consumer app, feature-oriented `lib/`, RU/KK/EN localization scaffolding.
- `docs/`: product, architecture/ADR, design, business, identity, engineering foundation and roadmap/backlog.
- Root `compose.yaml`: local API and PostgreSQL; identity provider POCs are separately isolated under `docs/identity/poc/`.

Read the module README and relevant `docs/` contract before editing. Keep domain boundaries and existing API contracts stable.

## Architecture and decision discipline

- Preserve modular monolith boundaries, PostgreSQL/Flyway ownership, Flutter client, API contracts, and the OIDC resource-server boundary.
- ADR-013 accepts the reversible fail-closed security boundary; it does not approve an identity vendor. ADR-015 is PROPOSED. ADR-001–012 statuses vary; read each ADR before relying on its recommendation.
- Do not promote a recommendation, POC, roadmap item, or `implementation_status` into an accepted decision without its required owner approval/evidence.
- Do not replace or bypass an existing architectural decision without a documented reason, impact analysis, and the repository's decision process. Prefer the smallest change consistent with accepted decisions.
- Keep marketplace domains, login/OTP, payments, AI, and production integrations disabled unless their documented gates are met.

## Security and quality

- Never commit credentials, private keys, tokens, local `.env`, truststores or test-user secrets. Use ignored local configuration and synthetic identities.
- Keep Spring JWT signature, exact issuer, audience, time and authorization checks fail-closed. HTTP issuers and cleartext are POC-only, loopback-only, and must not leak into production profiles.
- Mobile OAuth uses Authorization Code + PKCE via system browser; no embedded client secret, implicit flow, password grant, or ID token as API access token.
- Do not disable TLS certificate/hostname validation. Do not weaken security to make a test pass.
- Match neighboring formatting, naming, API/error contracts and test patterns. Add focused tests for changed behavior; report only checks actually run and their actual results. Do not call a build, scaffold or fixture test a live provider verification.
- Never edit generated outputs under `backend/target/`, Flutter `build/`, `.dart_tool/`, or local POC state as source of truth.

## Git and change handling

- At task start, check `git status --short --branch` and inspect recent history/diff when Git metadata exists. Preserve user changes; do not reset, clean, overwrite or stage unrelated work.
- This supplied workspace snapshot previously had no `.git` directory; Git status/history was unavailable. Recheck before assuming that limitation persists. Do not initialize a repository or invent a clean state.
- Use the existing branch/workflow. Do not commit, push, rewrite history, or change branches unless explicitly requested.
- Keep diffs minimal and review the final diff/status before reporting. If Git remains unavailable, state that verification limitation.

## Documentation and handoff

- Keep `PROJECT_STATE.md` factual and short; keep one actionable priority in `NEXT_TASK.md` with acceptance checks and commands.
- Detailed specifications and evidence belong in their existing documents. Link to them instead of copying them into handoff files.
- Update state/handoff when material implementation or verification changes, while preserving unapproved decision statuses and unfinished backlog statuses.
