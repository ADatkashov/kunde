# Indicative identity and OTP cost scenarios

Snapshot: 2026-11-10. These are planning scenarios, not quotes. MAU is not DAU; country mix, login method, message encoding, multipart SMS, retries, carrier route, taxes, data region, support and security add-ons change actual cost. No vendor SMS cost can be computed without verified KZ route price and successful verification rate.

## Public identity-plan reference points

| Candidate | 1k MAU | 10k MAU | 100k MAU | 1m MAU | What is included / excluded |
|---|---:|---:|---:|---:|---|
| Keycloak self-host | License $0 (Apache 2.0) | $0 | $0 | $0 | **Not total cost**: compute, managed DB, backup, HA, monitoring, SMS, on-call, upgrades and security engineering are excluded. Cost model must be built from KZ infrastructure quote and staffing. |
| ZITADEL Cloud (DAU plan, not MAU) | $0 if ≤100 DAU | From $100/mo Pro if DAU exceeds free capacity | From $100/mo plus current overages/limits | Quote/usage model required | Public pricing page lists Free 100 DAU and Pro $100 base with 25k DAU included; MAU scenarios cannot be directly equated. Confirm pricing, support, residency, SMS, log retention and overage before budget. |
| Auth0 | Current Free may cover eligible 1k / 10k MAU | Current page says up to 25k MAU on Free, but Essentials $35 includes 500 MAU | Quote / custom tiers | Quote / custom tiers | Free plan features/production suitability and limits require review; paid Professional shows $240 with 500 MAU on current page. Does not imply $35 buys 10k. SMS and enterprise features extra/plan-dependent. |
| Cognito Essentials, direct local users | $0* | $0* | about $1,350/mo* | about $14,850/mo* | Current AWS public price scenario: first 10k MAU free, then $0.015/MAU. Calculation: `(MAU − 10,000) × $0.015`. Excludes SMS/SNS, tax, AWS services, Plus threat features, federation charges. Region/feature tier can change price. |
| Firebase Auth with Identity Platform, direct/social | $0** | $0** | about $125–$275/mo** | about $2,375–$5,225/mo** | Blaze includes first 50k MAU; $0.0025–$0.0055 per MAU above, so `max(0, MAU − 50,000) × rate`. Excludes phone SMS/phone verification, Google Cloud, support and other services. |

\* Cognito formula assumes all modeled MAU are direct local user-pool sign-ins charged under the Essentials direct-user tier. Federated OIDC/SAML users have a separate allowance/price. Confirm regional rate.

\** Google table labels the rate range by qualifying tier/provider and billing structure; use a billing calculator and destination-specific SMS prices before treating the range as budget. No Kazakhstan phone unit price is asserted here.

## SMS/WhatsApp model

Let `v` be completed verifications/month, `p` the fraction needing a first SMS, `r` average SMS attempts per successful verification (including retries/fallback), and `c_sms` the contracted KZT per billable SMS segment. Then estimated SMS spend is `v × p × r × c_sms`, plus sender registration, minimums, taxes and failed/undelivered billable attempts. For channels priced per successful delivery, compute separate `v_channel × success_fraction × price`. Add provider retries and support overhead; do not multiply only by successful sign-ins.

Illustration only (not a vendor quote): at 100,000 verifications and one SMS per verification, each 1 ₸ change in `c_sms` changes monthly spend by 100,000 ₸; at 1m verifications it changes it by 1m ₸. Actual usage must come from funnel telemetry after launch with personal data minimized.

## Infrastructure and operations

For self-host, model two or more IdP instances, KZ-located PostgreSQL HA, backups, WAF/rate controls, secret manager/HSM as required, observability, DR, patching and incident on-call. Price with approved KZ providers after residency review; no infrastructure price is invented here. Managed options still require KUNDE integration, privacy, abuse monitoring, vendor support, migration and application on-call.

## Procurement checklist

Request itemized 1k/10k/100k/1m MAU prices; DAU-to-MAU assumptions; authentication-method premiums; OTP send/verify fees; failed delivery billing; sender-ID and template fees; taxes; overage; minimum; currency; regional data copies; log/audit retention; support/SLA; export; migration assistance; and price-change/termination rights. Recalculate monthly from expected OTP attempts per verification and channel share.

Sources: [AWS Cognito pricing](https://aws.amazon.com/cognito/pricing/), [Firebase Identity Platform pricing model](https://firebase.google.com/docs/auth#pricing), [Auth0 pricing](https://auth0.com/pricing), [ZITADEL pricing](https://zitadel.com/pricing/detail), [Keycloak license](https://www.apache.org/licenses/LICENSE-2.0). Prices should be refreshed before vendor selection.
