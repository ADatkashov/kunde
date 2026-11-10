# 10 — Admin Portal Architecture

Admin is a privileged control plane, separated from consumer UX and protected by stronger identity/session policy. Prefer isolated admin route/application and API audience; deploy separately only if blast-radius or network policy requires. No unrestricted “god mode” data browser.

## Role-specific workspaces

- Support: case-linked user/order/booking timeline, masked fields, case actions.
- Moderation: reported listing/review, policy evidence and appeal outcome; no payment mutation.
- Finance: payment/refund/settlement event reconciliation and controlled operations.
- Operations: partner/provider status and dispatch/order exceptions.
- Platform admin: category/policy/configuration and access grants, with preview and audit.
- Break-glass super admin: short-lived elevation, reason, MFA/step-up and independent review.

## Controls

Every access to PII requires case/purpose; fields are masked by default. Search is constrained by case, transaction ID or authorized tenant. Bulk export is disabled by default and separately approved. Refund/financial action is a workflow with policy, bounds, optional dual control and immutable audit. High-risk configuration uses maker/checker, change preview, staged rollout and rollback. Admin sessions are short-lived, device-bound where supported, and never share consumer tokens.

## Audit and separation

Record actor, role, scope, purpose, resource, action, prior/new state, timestamp, correlation and approval, excluding secrets. Audit store is append-only with restricted read. Monitor unusual access volume, repeated denials and out-of-hours privileged action. See 18 and PRD 1.1 §13.
