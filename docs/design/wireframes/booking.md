# Booking — C-19/C-20

```text
┌ ‹ Choose a time                   ┐
│ Service · provider · location     │
│ Date [ ‹ Tue 11 Nov › ]           │
│ Staff [Any available ▾]           │
│ Morning    [09:30] [10:30]        │
│ Afternoon [14:00] [16:30]         │
│ Slot held for 01:45               │
├ Review appointment                ┤
│ Beneficiary · service · duration  │
│ Almaty time · price · policy      │
│ [Confirm booking]                 │
└───────────────────────────────────┘
```

Slot picker and review are separate steps. Hold timer is meaningful and accessible; expired/taken slot returns to refreshed alternatives. Review discloses provider-confirmation and payment requirements, beneficiary and time zone. Rescheduling does not hide the current confirmed booking; replacement slot is confirmed before old one is released when possible.
