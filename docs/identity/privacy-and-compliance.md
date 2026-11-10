# Privacy and Kazakhstan compliance questions

This is a technical issue checklist, not legal advice. KUNDE counsel must review the current consolidated law, amendments, effective dates, regulator guidance, vendor contracts and actual data flows before provider selection or launch.

## Personal-data storage and transfer

The official Adilet text for Kazakhstan's Personal Data and Protection Law, Article 12, states that personal data storage is performed in a database/digital object located in Kazakhstan. The page includes a June 24, 2026 amendment note with a 60-day commencement rule. Because today's snapshot is 2026-11-10, counsel should verify the currently effective consolidated wording and applicability, not rely on this summary alone. [Adilet, Law No. 94-V](https://adilet.zan.kz/rus/docs/Z1300000094); [compare text](https://old.adilet.zan.kz/rus/docs/Z1300000094/compare).

Evaluate each copy and processor: IdP user database, authentication logs, audit events, OTP vendor request/status logs, backups, disaster recovery, support access, analytics, crash telemetry, email/phone claims and token logs. A database hosted in Kazakhstan does not by itself settle cross-border processing/transfer, remote support access or subprocessors. Obtain counsel's written view on lawful bases, consent/notice language, processor terms, cross-border conditions, retention and deletion.

## Product controls

- Collect only identifiers needed for the authentication purpose; explain why phone is used and how it is shared with IdP/SMS processors.
- Maintain notice/consent version and withdrawal records separately from proof that a user controls a phone.
- Set retention by purpose and legal obligation; expire challenge/telemetry quickly and constrain security log access.
- Document controller/operator/third-party responsibilities and incident notification route.
- Offer data-subject access/correction/deletion workflow with financial, fraud and legal-hold exceptions reviewed by counsel.

## Kazakhstan telephone and messaging

Kazakhstan and Russia share `+7`; ITU assigns Kazakhstan `+7 0`, `+7 6`, `+7 7` ranges in 2026 bulletin. Use maintained numbering metadata and E.164, not `+7` alone. [ITU Operational Bulletin 1341](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1341-2026-OAS-PDF-E.pdf).

Ask counsel and each mobile operator/provider whether transactional OTP templates, sender IDs, consumer notices, marketing rules, consent and opt-out obligations differ. Do not apply marketing-SMS rules to OTP without legal analysis, and do not infer that authentication traffic is exempt. For WhatsApp, confirm official Business onboarding, approved authentication template and local recipient consent rules. For Telegram, bot initiation requires the user to start the bot, so it is not universal fallback.

## Launch gate evidence

Obtain current signed DPA/subprocessor list, region map for primary/replica/backup/log/support, deletion/export terms, breach notice, retention settings, telecom sender registration steps, country-specific OTP pricing and template approvals. Record counsel approval and data-flow inventory in the release evidence; no such approval is claimed by this proposal.
