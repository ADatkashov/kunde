# Checkout — C-17

```text
┌ ‹ Review order                    ┐
│ Merchant · fulfillment mode       │
│ Items / options / edit            │
│ Delivery address [Change]         │
│ Timing estimate + freshness       │
│ Substitution choice (if supported)│
│ Subtotal                          │
│ Fees / discount / taxes           │
│ TOTAL KZT                         │
│ Cancellation terms [Read]         │
│ Payment method [Provider flow]    │
│ [Confirm and pay · KZT total]     │
└───────────────────────────────────┘
```

Before submit, revalidate quote and stock; if changed, replace CTA with review-changes state and itemized delta. Sticky total/action is allowed only if it does not cover content/keyboard. After tap, disable duplicate submission and show pending. Unknown payment says do not pay again; order/payment state detail remains accessible.
