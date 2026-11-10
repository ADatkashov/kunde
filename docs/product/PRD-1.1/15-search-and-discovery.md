# 15 — Search and Discovery

## Query contract

Inputs: query text, selected locale, explicit category scope (optional), service location, fulfillment date/time (optional), filters, sort, page cursor. Do not send family, health or payment details to search. Search may offer suggestions from consented/recent user data; users can clear history.

Search targets are category, business, service and product. Results retain type/category labels; mixed results are grouped by relevant category/type, never ranked as if unlike services are directly comparable. A chosen category narrows results. Search indexes only active/eligible listings and marks data freshness.

## Filters and sorting

- Location/service area and distance where location is available and lawful.
- Availability for selected day/time, with time zone.
- Price range applied to comparable price model; quote-based services are labeled, not falsely ranked by estimate as fixed price.
- Rating and review count shown separately; missing ratings are not treated as zero-star businesses.
- Fulfillment type, service attributes, provider/staff, dietary/other category options only where catalog supplies verified values.
- Sort options: relevance (default), distance, rating, price, availability. Tie-break deterministically; disclose when sort cannot be applied across mixed price models.

## States and behavior

| Condition | Behavior |
|---|---|
| Empty query | Show categories, curated supported modules or recent searches; do not send broad query unnecessarily |
| No results | Preserve query, show selected location/category and offer clear filter reset or nearby area |
| Partial category outage | Render available category sections with affected section marked unavailable; do not imply completeness |
| Network/index error | Preserve query/filters and allow retry; stale cached result is visibly labeled and cannot bypass checkout revalidation |
| Location unavailable/denied | Use explicit saved/manual location; do not silently infer precise location |
| Listing became unavailable | Keep result only if clearly marked unavailable or remove on refresh; prevent transaction until revalidated |
| Search history cleared | Remove user-linked recent terms from user-facing history under approved retention policy |

## API and analytics

`GET /api/v1/search?q=&category=&lat=&lng=&dateTime=&filters=&sort=&cursor=` is a proposed contract, not current implementation. Coordinate precision is minimized; location may be represented as a user-selected address/service area. Events: `search_submitted`, `search_results_viewed`, `search_result_selected`, `search_filter_changed`, `search_no_results` with query category and coarse region, never raw sensitive text by default. See 19 and 20.
