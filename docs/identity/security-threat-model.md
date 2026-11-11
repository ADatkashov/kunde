# Identity security threat model

Scope: account creation/login, OIDC callbacks, tokens, identity linking, OTP delivery, KUNDE authorization and admin access. Residual risk remains until implementation tests and operational controls exist.

| Threat | Impact | Required mitigation | Residual / evidence needed |
|---|---|---|---|
| SIM swap / number recycling | Account takeover or reassignment | OTP is proof of current channel possession only; fresh auth + old/new proof for changes; notify old channel; risk step-up/passkey; recovery review | Carrier response and account history cannot fully prevent SIM fraud. |
| SMS interception / forwarding | Login code theft | Short TTL, single-use, attempt limits; risk monitoring; step-up for sensitive/admin; avoid SMS-only admin | SMS remains a weak factor. |
| OTP brute force / SMS pumping | Account takeover, spend, denial | Per phone/IP/device/global quotas, generic responses, resend cooldown, anomaly/spend alarms, CAPTCHA/risk controls where appropriate | Tune false-positive/legitimate travel behavior with measured data. |
| Account enumeration | Privacy breach, targeting | Generic start/verify/recovery response, timing normalization where practical, no differing status codes/messages, rate limits | Vendor-hosted flow behavior must be tested. |
| OAuth redirect/code interception/mix-up | Session theft | Code + PKCE S256, external browser, exact redirect registration, state/nonce, issuer validation, claimed HTTPS links, no implicit flow | Test every platform callback and multiple issuers. |
| Token theft/replay | Unauthorized API calls | Secure refresh storage, short access life, rotation/reuse detection or sender constraint; audience restriction; TLS; redaction | Bearer access token replay window until expiry unless stronger binding/revocation. |
| Refresh theft | Persistent session takeover | OS keystore/keychain, rotation, revoke family, device session controls, no backups/logs | Rooted/jailbroken devices remain elevated risk. |
| Identity-linking abuse | Merge victim accounts | Fresh auth to existing identity and independent proof of new identity; no match-based auto-link; collision goes to recovery; audit/notify | Support process needs training, dual-control for exceptional merge. |
| Privilege escalation / IDOR | Business/customer data exposure | Server-side ABAC/resource ownership per request; deny by default; no client-supplied role/tenant trust | Requires negative authorization tests in implementation. |
| Admin compromise | Platform-wide exposure | Separate admin client, phishing-resistant MFA, just-in-time elevation, least privilege, audit, break-glass runbook | Human approval and account recovery can be attacked. |
| Provider/JWKS outage or key compromise | Login/API outage or forged identity | Fail closed, bounded cached JWKS, overlapping key rotation, incident key procedure, issuer pin, backup/recovery | Availability depends on provider and KUNDE readiness. |
| Social IdP account takeover | KUNDE account takeover | Defer social login from MVP; verified linking, step-up, provider assurance evaluation | Future social connections add trust dependencies. |
| SMS vendor compromise/data exposure | OTP and phone metadata disclosure | Minimize payload/logs, contract/subprocessor review, secret rotation, adapter isolation, alerts and fallback plan | Vendor internal access and telecom route remain third-party risks. |

Security basis: [OAuth 2.0 Security BCP RFC 9700](https://datatracker.ietf.org/doc/html/rfc9700), [native apps RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252), [OWASP mobile authentication/session guidance](https://mas.owasp.org/MASTG/0x04e-Testing-Authentication-and-Session-Management/), [OWASP mobile storage](https://mas.owasp.org/MASTG/0x05d-Testing-Data-Storage/).


## TASK-046 published supply-chain remediation — 2026-11-11

See [current vulnerability ledger](../security/ci-vulnerability-ledger.md) and [runbook](../security/security-runbook.md). Threats include JWT algorithm confusion, untrusted CORS, accidental mixed production/POC profiles, signed project/organization grant confusion, exception-secret logging, compromised buildscript dependencies and shared Gradle caches. Negative regressions and ephemeral SDK audit caches address defined boundaries; no SDK risk is accepted. Actual project dependency scans and maintained rebuilt OS images are clean in observed scopes; SDK MODERATE remains open. API abuse controls, canonical account/BOLA boundaries and Consumer E2E remain implementation gates, not claims inherited from Cloud-only work.


### Main integration review — 2026-11-11

Main22c1ae8 now publishes Consumer canonical identity/profile, issuer/subject binding, FlywayV2, Consumer authorization and Flutter auth repository/tests. Earlier statements that these modules were absent describe the historical baseline only. Preserve these additions; do not replace them with the older branch. Owner explicitly authorized integration/merge through PR4. Combined-source checks are required; native Consumer E2E and API abuse controls remain open. TASK-006/TASK-046 stay in_progress; no production readiness.
