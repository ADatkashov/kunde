# Explore/Search — C-07

```text
┌ ‹ Explore · [Location ▾] ┐
│ [Search services or items  ×] │
│ [All] [Food] [Home] [Care] →  │
│ [Filters 2] [Sort: Relevant]  │
│ 18 results       [List | Map] │
│ ┌ Business / listing card ┐   │
│ │ Name · category · rating│   │
│ │ Price basis · distance  │   │
│ │ Open / availability age │   │
│ └────────────────────────┘   │
│ ...                           │
└ Home · Explore · AI · Activity · Me ┘
```

List is default. Category chips preserve global query; filters open a mobile bottom sheet and desktop side panel. Cards group mixed result types and expose exact price model (“estimate”, “quote”, “fixed”). Map selection highlights matching card; map failure returns to list. Empty result preserves query and provides clear filters/area action. Stale result cannot bypass live detail/checkout revalidation.
