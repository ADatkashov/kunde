"""Cost/safety gate over `terraform show -json <plan>`: free tier only, no deletes, no surprise resources."""
import json, sys

ALLOWED_TYPES = {"terraform_data", "neon_project", "render_web_service"}
NEON_PITR_FREE_MAX = 21600


RENDER_SERVICE = "render_web_service"


def check(plan, allow_render_replace=False):
    """allow_render_replace: permit exactly one delete+create of the Render service (provider
    1.9.1 cannot update free-plan services in place, issue #80). Nothing else may be deleted."""
    problems = []
    for rc in plan.get("resource_changes", []):
        addr, rtype = rc["address"], rc["type"]
        actions = rc["change"]["actions"]
        if rtype not in ALLOWED_TYPES:
            problems.append(f"{addr}: resource type {rtype} is not allowed in DEV")
            continue
        if "delete" in actions:
            is_render_replace = rtype == RENDER_SERVICE and actions == ["delete", "create"]
            if not (allow_render_replace and is_render_replace):
                problems.append(f"{addr}: plan deletes or replaces a resource ({'+'.join(actions)})")
        after = rc["change"].get("after") or {}
        if rtype == "render_web_service":
            if after.get("plan") != "free":
                problems.append(f"{addr}: plan must be free, got {after.get('plan')!r}")
            if (after.get("num_instances") or 1) > 1:
                problems.append(f"{addr}: more than one instance")
            if after.get("disk"):
                problems.append(f"{addr}: persistent disk is a paid feature")
            if after.get("autoscaling"):
                problems.append(f"{addr}: autoscaling is a paid feature")
        if rtype == "neon_project":
            if (after.get("history_retention_seconds") or 0) > NEON_PITR_FREE_MAX:
                problems.append(f"{addr}: history_retention_seconds exceeds the Free plan cap")
            if after.get("allowed_ips") or after.get("hipaa"):
                problems.append(f"{addr}: IP allow-list/HIPAA are not Free features")
    for name, out in plan.get("planned_values", {}).get("outputs", {}).items():
        if out.get("sensitive"):
            problems.append(f"output {name}: sensitive values must not be exposed as outputs")
    return problems


if __name__ == "__main__":
    import os
    found = check(json.load(open(sys.argv[1])), os.environ.get("ALLOW_RENDER_REPLACE") == "true")
    for line in found:
        print(line)
    summary = json.load(open(sys.argv[1]))
    print("resources in plan:", len(summary.get("resource_changes", [])))
    sys.exit(1 if found else 0)
