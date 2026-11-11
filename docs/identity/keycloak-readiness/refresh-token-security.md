# Refresh token security

The new public clients use standard online Authorization Code + PKCE with rotation enabled and maximum reuse zero. Each lifecycle scenario uses its own browser authorization and token pair. The test checks single rotation, old-token replay and the successor's behavior, parallel refresh, browser logout, admin session deletion, explicit RFC 7009 refresh revocation, a shortened client-session expiry, and an invalid input. It also resubmits an already redeemed authorization code. That check concerns code reuse at the token endpoint.

The historical Android run requested `offline_access`. The new results apply to online refresh. Offline credentials have a distinct lifecycle and require separate acceptance evidence.

## Observed results

| Case | Keycloak 26.8.2 response |
|---|---|
| First refresh | HTTP 200 and a different refresh token |
| Replay of the original after rotation | HTTP 400 |
| Use of the successor after replay of the original | HTTP 400. A replay of a consumed token affected the usable successor in this drill. |
| Two concurrent requests with the same original | One HTTP 200 and one HTTP 400. Another use of the original returned 400. |
| After browser logout | HTTP 400 |
| After targeted admin session deletion | HTTP 400 |
| Explicit refresh revocation | Revoke HTTP 200. Refresh HTTP 400. Already-issued access JWT still received HTTP 200. |
| After short client session expiry | Refresh advertised 18 seconds. Submitting it after the signed expiry returned HTTP 400. |
| Invalid refresh value | HTTP 400 |
| Reuse of authorization code | First exchange HTTP 200. Repeated exchange HTTP 400. |

The concurrent check used one local node and two HTTP requests. It does not establish fleet behavior or a result for offline sessions. Treat a lost response as an uncertain exchange. Replaying an old token can disrupt a newer session path.
