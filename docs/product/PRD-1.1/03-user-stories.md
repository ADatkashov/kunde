# 03 — User Stories

Priority/phase abbreviations are defined in document 21. AC references point to `07-acceptance-criteria.md`; flow references point to document 04. Each story includes a role, expected outcome and principal exception path.

| ID | As a… | I want… | So that… | Exception / linked AC | Priority |
|---|---|---|---|---|---|
| HOME-001 | consumer | set or change my service location | results are locally relevant | denied/invalid location → manual address; AC-01 | P0 |
| HOME-002 | consumer | see supported categories and current transactions | I can resume useful work | empty catalog or offline state; AC-02 | P0 |
| HOME-003 | consumer | see relevant nearby or popular services | I can discover without searching | no eligible results; AC-03 | P1 |
| HOME-004 | consumer | see promotions with terms | I understand eligibility and price | expired/ineligible promotion; AC-04 | P2 |
| EXP-001 | consumer | browse category, business, product or service | I can choose a suitable option | category has no live supply; AC-05 | P0 |
| EXP-002 | consumer | filter and sort results | I can compare useful options | filter yields no results; AC-06 | P1 |
| EXP-003 | consumer | inspect price, availability, rules and provider details | I can make an informed choice | listing changes before checkout; AC-07 | P0 |
| AUTH-001 | guest | register and verify a phone | I can create an account | OTP delayed, expired, replayed or rate-limited; AC-08 | P0 |
| AUTH-002 | consumer | sign in, recover access and end sessions | I control account access | expired/revoked session; AC-09 | P0 |
| USER-001 | consumer | manage profile and language | the app reflects my choices | invalid/unsupported input; AC-10 | P0 |
| USER-002 | consumer | save and select addresses | checkout is accurate | location permission denied or address invalid; AC-11 | P0 |
| USER-003 | consumer | manage favorites and notification preferences | I control discovery and contact | transactional notice cannot be disabled; AC-12 | P1 |
| USER-004 | consumer | export/delete my account and manage consent | I control my data | legal/financial retention obligations; AC-13 | P1 |
| FAM-001 | family owner | invite and revoke a member with scoped permissions | we coordinate safely | invite expires/revocation during task; AC-14 | P2 |
| FAM-002 | family owner | book for a dependent | I can manage authorized care | guardian authority not established; block and explain; AC-15 | P2 |
| ORDER-001 | consumer | add available items to cart and review total | I know what I am ordering | price, stock, fee or delivery quote changes; AC-16 | P0* |
| ORDER-002 | consumer | pay and place an order once | I receive a traceable order | timeout, duplicate tap, payment success/order failure; AC-17 | P0* |
| ORDER-003 | consumer | track status and contact support | I know fulfillment progress | partner rejects, courier unavailable/delayed; AC-18 | P0* |
| BOOK-001 | consumer | select service, resource and open slot | I can reserve a real appointment | slot concurrently taken; AC-19 | P1 |
| BOOK-002 | consumer | reschedule or cancel under disclosed terms | I can change plans | provider rejects or cancellation is late; AC-20 | P1 |
| PAY-001 | consumer | see verified payment/refund status and receipt | financial history is clear | delayed confirmation or refund failure; AC-21 | P0* |
| ACT-001 | consumer | review active, past, cancelled and refunded activity | transactions are manageable | records paginate or fail to load; AC-22 | P0 |
| SUP-001 | consumer | open a support case linked to a transaction | I can resolve an issue | duplicate case or unavailable agent; AC-23 | P0* |
| AI-STORY-001 | consumer | ask for search, comparison or explanation | discovery is easier | ambiguous/unavailable result; AC-24 | P1 |
| AI-STORY-002 | consumer | prepare an order/booking plan | I can review before committing | stale quote/slot; require refresh; AC-25 | P1 |
| AI-STORY-003 | consumer | approve or reject a consequential action | nothing commits without my consent | changed amount/scope invalidates approval; AC-26 | P1 |
| AI-STORY-004 | consumer | inspect/delete conversation context | I control stored AI context | deletion cannot erase legally retained transaction record; AC-27 | P2 |
| PARTNER-001 | business owner | submit business for verification and maintain catalog | customers see trustworthy supply | verification pending/rejected; AC-28 | P0* |
| PARTNER-002 | business manager/employee | accept or reject assigned requests | fulfillment status is current | timeout, duplicate update, out-of-scope role; AC-29 | P0* |
| PROVIDER-001 | driver/courier/provider | accept and update assigned task | customer sees progress | assignment withdrawn or connectivity lost; AC-30 | P0* |
| OPS-001 | support agent | inspect a case and record a resolution | incidents are auditable | access purpose missing; deny and log; AC-31 | P0* |
| OPS-002 | moderator | review reported content and apply policy action | marketplace quality is maintained | appeal or conflict of interest; AC-32 | P1 |
| FIN-001 | finance operator | reconcile transaction and settlement records | funds can be accounted for | provider event mismatch; quarantine for review; AC-33 | P0* |
| ADMIN-001 | platform administrator | configure access and operational controls | platform stays governable | privilege escalation attempt; deny and alert; AC-34 | P0* |

`P0*` means P0 only for a category and operating model selected for launch. It does not imply all category operations launch. Every story's detailed preconditions, alternate branches and full acceptance steps are specified in the linked flow, requirement and AC documents.
