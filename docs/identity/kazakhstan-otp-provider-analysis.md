# Kazakhstan OTP delivery provider analysis

**As of 2026-11-10.** Evidence is from public vendor pages. None of these vendors is connected or operational for KUNDE. Obtain written commercial and technical confirmation, production test routes and privacy terms before selection.

| Provider | Publicly evidenced | Unknown / validate | Initial fit |
|---|---|---|---|
| **Mobizon Kazakhstan** | REST HTTP/HTTPS API with JSON/XML, API key and optional IP allowlist; API base `https://api.mobizon.kz/service/`. Public bulk page advertises SMS from 10.40 ₸/message under stated volume/top-up conditions; sender ID may require contract/operator registration. | Bulk marketing price is not a confirmed transactional OTP tariff. Need KZ operator coverage, per-route OTP rate, delivery receipts semantics/latency, segment billing, duplicate behavior, sender ID and template approval, retry/idempotency, legal entity/contract, SLA and data processing/storage. | Candidate SMS transport adapter; price must not be used in unit economics until quote. [API](https://mobizon.kz/integration/api), [pricing](https://mobizon.kz/bulk-sms). |
| **SMSC.kz** | HTTPS API supports sending, status and cost/tariff-related operations; message cost and delivery status can be queried. Documentation notes duplicate identical request handling within a short interval; design retries with unique KUNDE attempt IDs and read-back status rather than blind replay. | Current public tariff page was not consistently retrievable; no stable per-KZ OTP price or SLA asserted. Confirm route/operator rates, sender/template registration, delivery receipts, statuses, request dedup scope, throughput, IP allowlist, support/contract, data location/retention and OTP use terms. | Candidate SMS adapter with useful API status surface. Treat price/status semantics as vendor-confirmation items. [API](https://smsc.kz/api/), [tariffs](https://smsc.kz/tariffs/). |
| **Cascade** | OTP API documents HTTPS bearer authentication and send/verify operations; official pricing currently states WhatsApp/Telegram 3 ₸ per successful delivery and SMS 8 ₸ after launch/availability conditions. | Public docs conflict over whether SMS is launched/available; resolve before use. Confirm actual channel availability to KZ users, account onboarding, WhatsApp Business template approval and opt-in, Telegram bot user-start constraint, delivery receipts/latency, fallback charge rules, residency, SLA, export and written contract. | Potential multi-channel OTP orchestrator, but API may couple challenge verification to vendor; prefer delivery-only adapter unless it supports caller-supplied IdP-generated code and does not become identity authority. [OTP docs](https://docs.cascade.kz/en/about), [pricing](https://docs.cascade.kz/en/pricing). |

## Number and channel rules

- Normalize input to E.164; preserve the submitted value only when necessary for audit/support, with retention controls. Kazakhstan and Russia share calling code `+7`. ITU's 2026 bulletin lists Kazakhstan's assigned `+7 0`, `+7 6`, `+7 7` ranges; do not identify a country using `+7` alone. Validate number ranges against a maintained numbering-plan source and keep international-number support extensible. [ITU Operational Bulletin 1341](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1341-2026-OAS-PDF-E.pdf)
- Treat SMS sender name and message-template approval as per-operator/commercial setup items; do not assume a numeric/shared sender or one template works across networks.
- A Telegram bot cannot initiate a conversation before the user starts it. Therefore Telegram is not a universal first-contact OTP fallback. [Telegram bots](https://core.telegram.org/bots)
- WhatsApp OTP needs an approved Business setup, template/category eligibility, opt-in and country-specific price confirmation. A vendor's “successful delivery” metric is not proof of user identity.
- Make fallback explicit user choice or consented policy, do not silently send personal data to another channel. Do not auto-fallback to social messaging after an account-enumerating response.

## Adapter selection questions

1. Can the provider send an IdP-generated code as supplied, without taking over verification? If no, isolate its own OTP API behind an IdP extension and evaluate lock-in carefully.
2. What are submission acceptance, delivered, expired and unknown statuses? Which have billable cost? What is retry-safe?
3. Which KZ networks and number prefixes are covered; what are p50/p95/p99 delivery times by network and time of day?
4. Is the message billed per SMS segment? How are Cyrillic/RU/KK templates encoded and segmented?
5. Where are number, message, provider logs and delivery reports stored, and for how long?
6. Are sender IDs, registered templates, business entity documents or operator contracts required? Obtain written checklist.

## Recommendation

Run an isolated adapter evaluation after the IdP finalist and legal gates are accepted. Obtain offers from Mobizon and SMSC.kz for one-way transactional SMS; assess Cascade only after confirming launch status and IdP-owned verification compatibility. Require primary SMS plus independently contracted fallback only if measured reliability justifies the additional privacy/operations cost. No delivery-rate claim or vendor is selected by this document.
