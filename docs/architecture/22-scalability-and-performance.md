# 22 — Scalability and Performance

## Scale independently where useful

API is stateless and horizontally replicated; DB remains primary capacity constraint and must be protected with bounded pools, indexes, query budgets and backpressure. Worker concurrency is partitioned by class (payment reconciliation, notifications, search projection, AI tasks) so noisy noncritical work cannot starve finance. Search index/read replicas may be added independently. Partner/provider event ingestion is rate-limited and deduplicated.

## Workload assumptions to obtain

Before sizing: city launch user cohort; concurrent sessions/peak minute; catalog/listing count; searches per session; order/booking conversion; payment and webhook peak; dispatch GPS/event rate; media size; retention; AI requests, prompt/tool tokens, budget; promotional burst. No numerical capacity is asserted without these inputs.

## Performance controls

- Paginate all lists; avoid N+1; cap search radius/facets/result size; query plan and slow-query monitoring.
- Cache only versioned public catalog/search results with short TTL; revalidate at transaction boundary.
- Use asynchronous projections for search/analytics/notifications and backpressure/retry controls.
- Rate limit OTP, login, search and mutation endpoints by abuse risk and tenant.
- Load test checkout/payment callbacks and last-slot contention; test degraded provider latency.
- Mobile image variants/CDN and lazy loading where regional policy permits.

## Multi-city/country progression

City is a scoped service-area/configuration, not a separate application. Country data residency and legal policy may require separate regional database/deployment cells. Start with one KZ home region and explicit country/market ID. Avoid global active-active writes for money, identity or bookings until consistency, residency and operations are proven.
