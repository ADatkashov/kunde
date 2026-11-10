# 14 — Notifications

Delivery channels (push, in-app, SMS, email, messaging) are pluggable and subject to consent, regional law, verified capability and cost. No external channel/provider is assumed. In-app transaction center is the durable source of status.

| Event | Class | Recipient and content | User control / deduplication |
|---|---|---|---|
| OTP / account recovery | Security mandatory | Account holder; code/expiry, never order data | Rate-limited; latest challenge supersedes prior |
| New device, password/session/security change | Security mandatory | Account holder; time and recovery action | Cannot be disabled where security requires |
| Order placed/accepted/rejected/status changed | Transaction mandatory | Consumer and relevant scoped partner/provider | One event per state/version; retries use same event ID |
| Driver/provider assigned or changed | Transaction mandatory | Consumer/provider; minimal assignment detail | Collapse superseded assignment update while retaining history |
| Booking confirmed/changed/reminder/cancelled | Transaction mandatory | Consumer, provider; only authorized beneficiary details | Reminder schedule configurable, deduplicated by booking/version |
| Payment/refund pending/confirmed/failed | Financial mandatory | Payer; amount, currency and verified state/reference | Never notify success on unverified result |
| Support case update | Service mandatory | Case participants with scoped content | Deduplicate by case/update ID |
| AI task requested/completed/failed | User-requested operational | Conversation owner; completed steps and next action | Preference may control push; result remains in app |
| Promotion/recommendation | Marketing optional | Consented audience, relevant offer and terms | Consent, quiet hours and unsubscribe respected |

## Delivery behavior

- Persist notification event in same logical transaction/outbox as domain state change. Retry transient failure with bounded exponential backoff; dead-letter and monitor exhausted delivery.
- Provider delivery receipt is not proof user read it. Keep status distinct: queued, sent, delivered (if provider verifies), failed.
- Deduplicate by stable event ID and recipient/channel. State-change retries cannot create repeated charges or repeated messages.
- User can set language, eligible channels, marketing consent and noncritical reminder preferences. Mandatory service/security messages are not silently suppressed.
- Do not include sensitive health, child, payment credential or full address information in lock-screen text; link to authenticated detail.
- Respect local time zone for reminders and user quiet-hour settings, except legally/operationally urgent notices under approved policy.
- Invalid contact or revoked push token is marked unusable; offer preference repair and retain in-app status.
