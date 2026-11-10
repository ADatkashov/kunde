# DevOps & Environments

`compose.yaml` defines a local PostgreSQL 16 service and backend container. The DB port binds to loopback. Credentials are required from ignored `.env`; no default password exists. Backend image builds with Java 21/Maven and runs non-root. Cloud, production deployment and secret manager remain unselected.

`.github/workflows/ci.yml` configures separate backend and Flutter jobs. Backend CI provisions PostgreSQL and runs Maven `verify`; mobile CI resolves dependencies, analyzes and runs unit/widget tests. CI DB credentials are disposable and scoped to the ephemeral job. No deployment job exists.

Before production add reviewed/pinned action revisions, dependency/container vulnerability scanning, SBOM/provenance, protected deployment environments, managed secret injection, data-region review, restore evidence and on-call ownership.
