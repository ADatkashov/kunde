# Signing-key rotation

The drill records public JWKS key IDs, then calls Spring with the original signed JWT to warm the decoder. It creates a higher-priority RSA signing component in the isolated realm, makes the original component passive and issues a new JWT. JWKS must contain both signing keys during overlap. The same Spring instance must accept both access tokens while valid. A valid new-key JWT with the same warmed decoder demonstrates the live unknown-key resolution path.

Removal is scoped to the original component of the newly generated test realm. The runner waits past the maximum configured online session lifetime and Spring tolerance after cutover, confirms the original access JWT has expired, then checks JWKS publication and a fresh JWT. Removal from JWKS and eviction from each verifier's cache are separate observations. Immediate fleet invalidation of a compromised signing key requires its own drill. [Keycloak realm keys](https://www.keycloak.org/docs/26.8.2/server_admin/), [Spring JWT resource server](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)

## Observed overlap

| Public `kid` | Original JWKS | Overlap JWKS |
|---|---|---|
| `MKKQ66DVflicKrp7OO2oYlzlsvo5bDwGbdufF4TkKVg` | Original signing key | Passive signing key |
| `9cELEMDONsx7nFevQ1md0Y8aVZh0j1jYRxd2T9WesL8` | Absent | New signing key |
| `GjceCmMQHtGOiQU2H2149ENtxQfaQhMAuJ2Ic4cmnls` | Present | Present |

The original JWT returned HTTP 200 before rotation. The new JWT and the still-valid old JWT each returned HTTP 200 during overlap with the same Spring process. The generated-JWKS regression additionally counts the fetch on an unknown key ID. The local live drill did not count network calls.

## Observed retirement

After at least 145 seconds from cutover, the original access JWT returned HTTP 401 before deletion. The old signing component was removed in the test realm and its `kid` was absent from JWKS. The new signing key and the unchanged third key remained published. A fresh JWT then returned HTTP 200. Emergency invalidation of still-unexpired tokens and fleet cache eviction remain separate exercises.
