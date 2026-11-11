# KUNDE identity provider decision report 4.0

**2026-11-10 · Recommendation for owner review · Self-hosted Keycloak 26.8.2**

Keycloak scored **74.8/100** and ZITADEL **71.6/100**. Both passed Android AppAuth, real JWT validation and Spring API HTTP 200 before and after refresh. Keycloak fits the existing API audience and scope contract directly. Its local stack has two containers and the upstream Apache 2.0 license. ZITADEL has a lower observed idle memory footprint and remains a viable alternative. Its project audience and signed project-role claims require provider-specific mapping at this boundary. See the [weighted matrix](../provider-decision-matrix.md) and [operational comparison](operational-comparison.md).

## Technical evidence

| Check | Keycloak 26.8.2 | ZITADEL 4.19.5 |
|---|---|---|
| Configuration | Existing public client and realm preserved | Development organization and project, public Native client with Code and Refresh grants, JWT access tokens, exact native callbacks, synthetic user and project grant |
| Android PKCE | Historical PASS through Chrome Custom Tab, Flutter callback and code exchange | PASS through Chrome Custom Tab, Flutter callback and code exchange. Android discovery and JWKS both HTTP 200 with the original issuer. |
| Protected Spring API | Historical HTTP 200 with real JWT, then HTTP 200 after refresh | HTTP 200 with a real JWT and signed project-role mapping. Initial HTTP 403 identified the scope mismatch. |
| Refresh | Historical Flutter renewal and API HTTP 200 | Flutter refreshed and API returned HTTP 200. Protocol probe observed rotation, denied replay/invalid refresh and denied refresh after explicit revocation. |
| Logout and next login | Historical local clearing and new interactive prompt | End-session returned to Flutter and cleared local tokens. Selecting the remembered account required the password. The second PKCE exchange and API HTTP 200 passed. |
| Negative tokens and keys | Historical expiry/401, common signed fixtures and 4.0 live results in the linked matrix | Common signed fixtures plus live results in the linked matrix |

ZITADEL's signed access JWT in this configuration has `jti` and the expected project-scoped role when role assertion is enabled. The JWT has no `scope` claim. The POC authorizes against a signed grant for the configured project and organization. The ID token can share the project audience, so the POC also requires the access-token identifier in this provider/version profile. Opaque tokens require online authenticated introspection, adding backend credential custody and runtime availability/latency concerns. [ZITADEL applications](https://zitadel.com/docs/guides/manage/console/applications-overview), [claims](https://zitadel.com/docs/apis/openidoauth/claims), [introspection](https://zitadel.com/docs/guides/integrate/token-introspection)

## Fit, risks and release gates

- **Operations.** Keycloak has fewer local components. ZITADEL uses less memory in the recorded single idle snapshot. HA, Kubernetes, restore, controlled upgrades, monitoring, capacity and migration are documented capabilities without local drill evidence.
- **Business and licensing.** Both self-host candidates require infrastructure, operational staffing and SMS/support budgets. ZITADEL v4's server license and exceptions require review for the intended use. Commercial quotes, SLAs and phone-first Kazakhstan delivery remain unverified.
- **Privacy.** Counsel must approve Kazakhstan placement and all transfers and access paths across IdP, SMS, logs, telemetry, backup/DR and support. Self-hosting provides placement control. It does not establish compliance.
- **Security.** ZITADEL refused refresh after revocation while the issued access JWT still returned HTTP 200. The observed POC access lifetime was about 12 hours. Set an approved launch lifetime and revocation SLO. Verify live key rotation, invalid callback/state, network interruption, recovery, admin MFA, abuse controls, audit and device storage.

## Decision and next engineering gate

ADR-015 stays **PROPOSED**, TASK-005 **blocked** pending explicit owner approval, and TASK-006 **not started**. EP-002 implementation remains gated by provider/fallback acceptance and the approved lifecycle, privacy and operating design. The next engineering task and its exit criteria are in [NEXT_TASK.md](../../../NEXT_TASK.md). See the [security matrix](security-results.md), [remaining risks](remaining-risks.md), [production gaps](production-readiness-gaps.md) and [EP-002 roadmap](../../roadmap/25-identity-ep002-design.md).
