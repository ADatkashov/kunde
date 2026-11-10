# 06 — Development Backlog

The canonical backlog is normalized into [`epics.yaml`](backlog/epics.yaml), [`features.yaml`](backlog/features.yaml), [`tasks.yaml`](backlog/tasks.yaml), [`dependencies.yaml`](backlog/dependencies.yaml), [`releases.yaml`](backlog/releases.yaml) and [`risks.yaml`](backlog/risks.yaml). Current baseline: 27 epics, 35 features, 56 engineering tasks. IDs are stable; extend them, do not renumber. EP-002 design outputs and gates are documented in [25-identity-ep002-design.md](25-identity-ep002-design.md); TASK-005 remains blocked until selection is approved.

## Hierarchy and granularity

`Epic → Feature → User Story → Engineering Task → Subtask`. Features carry a concise story and acceptance summary; engineering tasks are the actionable unit and carry unique task ID, epic, feature, area, priority, prerequisites, acceptance criteria, verification, DoD and target release. Subtasks are intentionally omitted from the baseline unless a task is split during refinement; do not create artificial tiny work items.

## Refinement rules

- Split a task when it has independent ownership/release/testing or cannot be reviewed as one change.
- Keep API, mobile and database work contract-aligned; task dependencies name prerequisites, not merely related work.
- Use `conditional` for work only required by an unresolved operating model; never silently place it on critical path.
- A task's `tests` field defines evidence required later; it is not evidence that tests have run.
- Link product stories/requirements wherever available. Cross-cutting tasks link the decision or architecture contract they satisfy.

## Engineering areas represented

Backend, mobile, web/admin, database, infrastructure, DevOps, security, QA and product analytics. Partner workflow is allowed to start with the lightest operationally viable web/tool surface; no separate provider mobile app is assumed until D-02 resolves the fulfillment model.

## Start-ready queue

Begin with TASK-001 decision register ownership and sign-off plan, TASK-002 architecture/repository baseline review, TASK-003 API/domain contract map, TASK-004 build/review/branch pipeline specification and TASK-005 initial threat/privacy assessment. These prepare delivery but do not claim unresolved decisions are closed. Then foundation implementation can start against approved technical contracts. Real order/payment development is not Start-Ready until category, lifecycle, funds flow and legal/privacy decisions are resolved.

