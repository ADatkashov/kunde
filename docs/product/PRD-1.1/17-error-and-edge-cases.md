# 17 — Error and Edge-Case Catalog

Messages are illustrative English source copy for localization; client should use stable error codes and server-provided safe parameters, not expose internals. Retry means retry the same logical operation with original idempotency key unless noted.

| ID | Trigger / system behavior | User-visible response / recovery | Retry / logs |
|---|---|---|---|
| ERR-NET-001 | Network unavailable; read-only cache may display with stale label; mutation remains unresolved | “You’re offline. Reconnect to continue.” Keep safe draft; re-query transaction on reconnect | Retry reads; mutation lookup first; correlation and connection class |
| ERR-AUTH-001 | Session expired during mutation; reject before side effect | “Please sign in again. We’ll check whether your last action completed.” | Re-auth then lookup idempotency; auth audit |
| ERR-OTP-001 | OTP delayed/provider failure | “Code hasn’t arrived yet. Check the number or try again shortly.” Show resend cooldown/support | Bounded resend; provider request ID, no plaintext code |
| ERR-REQ-001 | Same idempotency key different payload | “This request changed. Review it and try again.” | No retry with same key/payload mutation; security/validation log |
| ERR-CAT-001 | Provider unavailable or listing suspended | “This service is unavailable right now.” Offer eligible alternatives | Refresh availability; listing/version ID |
| ERR-PRICE-001 | Price/fees changed after detail view | “The total changed. Review the updated price before continuing.” | New quote and fresh explicit confirm; old/new quote IDs |
| ERR-STOCK-001 | Product unavailable | “One or more items are no longer available.” Keep cart and allow removal/substitution review | Revalidate; item/version, no payment credentials |
| ERR-SLOT-001 | Booking slot concurrently taken | “That time was just booked. Choose another available time.” Release stale hold | Refresh slots; resource/hold correlation |
| ERR-PAY-001 | Payment request timeout/unknown | “We’re checking your payment. Please don’t pay again yet.” Show status and support link | Query/reconcile; provider reference and idempotency key |
| ERR-PAY-002 | Verified payment success, order creation failed | “Payment was received, but the order isn’t confirmed. We’re resolving it and will update you.” | Automatic persistence retry/void/refund; high-priority incident, correlated records |
| ERR-PROV-001 | Partner accepts then disconnects | Show last verified state and “We’re checking with the provider”; dispatch/support recovery | Reconcile events; assignment version, connectivity metadata |
| ERR-DEL-001 | Delivery delayed | Show verified last update/estimate if available, support/cancel options per policy | No fabricated ETA; event timeline and SLA timer |
| ERR-CANCEL-001 | Cancellation no longer eligible or fee changed | Explain current state and disclosed policy; allow support case | No duplicate cancellation; actor/policy version |
| ERR-PARTNER-001 | Partner cancels | Notify consumer; cancel order, release resources, compensation pending if needed | Dispatch alternative only with consent; reason and payment refs |
| ERR-REFUND-001 | Refund provider failure | “Your refund is delayed. We’re following up.” Keep pending/exception | Idempotent retry/escalation; provider event, amount, aging |
| ERR-LOC-001 | Location permission denied | Offer saved/manual address; explain location setting option | No automatic permission loop; permission choice only |
| ERR-ADDR-001 | Invalid/out-of-area address | “This address is outside the service area. Choose another address.” | Edit address/recheck service area; normalized address reference |
| ERR-AI-001 | AI tool fails | “I couldn’t complete that step. Nothing was placed unless shown below.” Show verified partial state | Retry idempotent read/action only; tool result/correlation, no sensitive prompt by default |
| ERR-AI-002 | Partial multi-step execution | List each completed/pending/failed action and next choice | Resume from failed step with fresh authorization; task-step audit |
| ERR-AUTHZ-001 | Unauthorized action or revoked family/partner grant | “You don’t have access to do that.” Do not disclose resource existence; contact owner/support | No retry until grant changes; denial audit |
| ERR-NOTIF-001 | Notification provider rejects/delivery fails | Keep in-app state, mark delivery failure and offer channel repair | Bounded retry/dedupe; channel/event ID |

## General handling

Every error has stable code, safe message, retryability, correlation ID and recoverability. Do not display stack traces or secrets. Keep input when safe; clear payment/security secrets. Escalate repeated financial integrity mismatches immediately to operations; do not mask them as generic success.
