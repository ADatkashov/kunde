# Failure and recovery scenarios

| Scenario | Expected behavior | Recovery / operational evidence |
|---|---|---|
| IdP unavailable before login | Show localized retry/support state; no local bypass | Provider health alert, status communication, retry with backoff. |
| Discovery/JWKS unavailable | Continue only within bounded valid cached-key policy; reject unknown key/issuer | Alert, refresh rate limit, key-rotation runbook. Never turn off signature checks. |
| SMS request times out with unknown acceptance | Keep same IdP challenge; show pending/retry after cooldown; reconcile by provider message ID where possible | Do not blindly resubmit identical payload; query status or new explicit attempt; track billable ambiguity. |
| OTP delayed / expired | Allow bounded resend after cooldown; old code remains one-time and expires | Do not extend expiry indefinitely; generic response; cap spend. |
| SMS vendor outage | Circuit-break affected route; optionally show user-selected approved alternate | Fallback must have separate consent, data and abuse review; no silent identity bypass. |
| Refresh token rejected/reuse detected | Clear local session, revoke token family, require full sign-in, notify user when appropriate | Security event, session investigation, revocation propagation. |
| Phone lost / SIM swapped | Do not recover solely from a new claim to number | Alternate factor or staffed recovery; notify former contacts, delay/high-risk review, revoke sessions. |
| User deletes account while provider offline | Accept idempotent request and mark deletion pending; restrict new use | Durable work item retries provider revocation/deletion; alert and track completion; honor retention policy. |
| App callback duplicated or malformed | Reject bad state/nonce/issuer; process valid code once | Clear transaction state; restart auth; no code in logs. |
| Provider migration or issuer change | Keep old mapping until new provider proof and mapping transaction succeed | Reconcile user counts, sample ownership, rollback window, revoke old sessions after cutover; no phone-based bulk merge. |
| KUNDE DB unavailable | Protected APIs fail safely; no profile/permission bypass | Restore DB and verify external mapping/membership integrity; recovery test. |
| Account suspended but JWT remains valid | Authorization lookup denies suspension promptly or short token TTL bounds access | Define revocation propagation SLO and cache invalidation; monitor stale authorization window. |

Every runbook should identify decision owner, alert threshold, on-call route, user-facing RU/KK/EN text, audit event, retry owner, recovery-time objective and post-incident review. Values are not yet set; set them in implementation/operations planning.
