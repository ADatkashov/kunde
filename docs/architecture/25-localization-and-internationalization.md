# 25 — Localization and Internationalization

## Data conventions

Store UTC instants; store service-location IANA time zone for local appointment semantics. Use integer minor units + ISO currency code; do not store formatted monetary strings. Locale tags use BCP 47 (`kk-KZ`, `ru-KZ`, `en` as applicable). Address is structured flexibly with country-specific formatter/parser adapters; do not make one country shape mandatory. Catalog strings are localized per listing or approved fallback with locale provenance.

## Rules and isolation

Country/market config owns currency, tax/commission policy, phone parsing, address conventions, supported categories, service areas, notification/legal text and data-retention policy. Core order/payment domains accept currency and policy version; they do not embed `KZT` branches. New-country rollout uses policy/config deployment and separate legal review, not merely enabling locale.

## Client/API behavior

Locale is explicit on profile/request. APIs return machine values and stable codes; clients format currency/date. Store accepted consent version and language. Search indexes language variants and applies locale-specific tokenization; user copy is not generated as legal truth by AI. Critical consent, payment and cancellation text is human-reviewed in Kazakh/Russian; English architecture/resources are supported.

## Expansion gate

Before country launch define data residency cell, cross-border transfer basis, local payment adapters, tax/commission, consumer rights, language QA, support hours, incident obligations and partner terms. User home data region is explicit; access from other countries is subject to policy and law.
