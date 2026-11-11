# Access token revocation

The drill sends an online Keycloak access JWT to the protected Spring endpoint before and after two independent events. Browser logout uses RP-initiated end-session in the same browser profile and verifies the callback and a later `prompt=none` authorization. Targeted admin revocation deletes the synthetic user's specific online session. Neither operation rewrites the JWT. The runner polls the original token every two seconds and records the last HTTP 200 and first HTTP 401 relative to both the event and the token's `exp`.

Flutter clears its local tokens when logout finishes or fails. Local clearing affects the app's copy. Provider logout terminates the browser SSO session and online refresh path. Explicit token revocation tests the provider's refresh endpoint separately. API acceptance of an already issued JWT is governed by signature, issuer, audience, expiry and the Spring clock tolerance. See the [Flutter contract](../flutter-integration.md) and [Keycloak admin guide](https://www.keycloak.org/docs/26.8.2/server_admin/).

## Observed results

On the 30-second test JWT, browser logout returned through the registered callback and a subsequent silent authorization returned `login_required`. Spring returned HTTP 200 immediately before and after logout. The online refresh attempt returned HTTP 400. The previous access JWT still received HTTP 200 at **79 seconds after logout** and first received HTTP 401 at **81 seconds**. Relative to the signed `exp`, those samples were **+58 s** and **+60 s**.

Targeted admin session deletion returned HTTP 204. The prior access JWT returned HTTP 200 immediately afterwards, while refresh returned HTTP 400. It still received HTTP 200 at **82 seconds after revocation** and first received HTTP 401 at **84 seconds**. These samples were **+59 s** and **+61 s** from `exp`. Explicit refresh endpoint revocation separately returned HTTP 200, followed by refresh HTTP 400 and HTTP 200 for the already-issued access JWT.

The results are consistent with the default Spring clock tolerance. KUNDE needs a separate account/session decision at the API for a faster emergency cutoff. The drill does not prove immediate revocation by invalidating a local Flutter token. [Spring timestamp validation](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
