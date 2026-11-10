# Weighted provider decision matrix

This is a transparent **preliminary architecture score**, not a vendor test or final selection. Score 1 (poor fit) to 5 (strong fit). A criterion depending on unverified Kazakhstan facts is capped at 3. Weighted total is `sum(weight × score) / 5`, on a 100-point scale. Change scores after POC and written vendor answers.

| Criterion | Weight | Keycloak | ZITADEL | Auth0 | Cognito | Firebase |
|---|---:|---:|---:|---:|---:|---:|
| Security controls and standards | 14 | 4 | 4 | 5 | 4 | 4 |
| Flutter/native mobile fit | 10 | 3 | 4 | 4 | 3 | 5 |
| Spring/OIDC API fit | 10 | 5 | 5 | 5 | 4 | 3 |
| Phone OTP flexibility for KZ | 12 | 3 | 4 | 4 | 3 | 3 |
| Data control/residency | 12 | 5 | 3 | 2 | 2 | 2 |
| Operations / support burden | 10 | 2 | 4 | 5 | 4 | 5 |
| Cost predictability at scale | 8 | 4 | 3 | 2 | 4 | 4 |
| Customization / UX | 6 | 5 | 4 | 4 | 3 | 3 |
| Portability / lock-in | 6 | 5 | 4 | 3 | 3 | 2 |
| Audit / lifecycle / extensibility | 6 | 4 | 4 | 4 | 3 | 3 |
| International scalability | 6 | 4 | 4 | 5 | 5 | 5 |
| **Weighted total / 100** | **100** | **78.4** | **78.0** | **78.8** | **68.4** | **71.2** |

The narrow numeric lead for Auth0 is not dispositive: current public plan detail and region suitability remain uncertain, while KUNDE has a material data-location question and a strong preference for portable identity. Keycloak and ZITADEL scores reflect capability and control, but lower certainty/ops overhead for custom phone flows. The matrix therefore recommends a **hybrid-compatible architecture** with Keycloak as first self-host POC and ZITADEL as a managed/self-host alternative; it does **not** approve either product.

## Hard gates (not averaged away)

1. Counsel confirms processing, storage, cross-border transfers, consent and retention approach for IdP, messaging vendor, telemetry and backups.
2. Vendor confirms exact region for primary store, logs, backups, support access and disaster recovery; KUNDE verifies contract and subprocessors.
3. Phone-first flow, resend/anti-abuse, account recovery, verified phone claims and native redirect flow pass an isolated POC.
4. Operations owner accepts patching, uptime, incident, key rotation, restore and SMS spend-control responsibilities.
5. Current quotes cover 1k–1m MAU, OTP route, overages, audit retention, support/SLA and data export.

## Why the weights

Security (14), Kazakhstan OTP practicality (12) and data control (12) receive the highest weights because account takeover and launch-market compliance can block launch. Mobile and Spring standards fit (10 each) reflect existing product stack. Operations, cost (8) matter as usage grows. Customization, portability, audit and internationalization (6 each) are meaningful but cannot compensate for a failed hard gate.

## Sensitivity

If KUNDE cannot staff 24/7 IdP operations, lower Keycloak operations from 2 to 1; if a verified Kazakhstan managed region and contract become available, raise managed candidates' data scores only after proof. If the product requires native phone UX without IdP-hosted login, re-score custom-flow implementation burden. Re-run this matrix after the same evidence is collected for all finalists.
