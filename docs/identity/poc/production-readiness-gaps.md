# Production readiness gaps — identity POC recovery 3.0

See the [4.0 decision report](final-provider-decision-report.md#fit-risks-and-release-gates) for the current launch gates. Items below record 3.0.

This local POC does not authorize production use.

- Provider choice remains unapproved; ADR-015 remains PROPOSED.
- ZITADEL native app/project/user and equivalent Android-to-API flow are outstanding.
- Keycloak live negative-token matrix and full refresh/revocation/session/access-token-after-logout lifecycle are outstanding.
- Android invalid callback/state, cancellation, interruption, invalid refresh and second successful re-login are not fully verified.
- Production TLS/DNS, redirect allowlists, signing-key custody, MFA/step-up/admin access, rate/abuse controls, audit and incident response are not validated.
- Kazakhstan privacy/data location, cross-border processing, commercial terms/support and subprocessor review remain open.
- SLOs, named on-call, monitoring/alerting, HA, backups/restore, DR, patch/upgrade/rollback and load/capacity testing remain open. Local idle resource snapshots are not sizing data.
- Secure-storage/device compromise review, independent threat model and penetration test remain outstanding.
- Migration/export and provider-exit strategy require owner approval.

TASK-006 is not complete and must not start production readiness acceptance based on this POC.
