#!/usr/bin/env python3
"""Resolve (product, suite) of the Product E2E workflow into existing reusable E2E workflows (ADR-027).

Prints {"workflows": [...], "unavailable": [...]}; exit 2 on an unknown product/suite.
Nothing is invented: a combination without an existing E2E workflow is listed under `unavailable` and makes
product-e2e.yml fail, so "no E2E exists" can never be mistaken for "E2E passed".
Usage: product_e2e_plan.py <product|all> <api|consumer|partner|executor|admin|multi-role|full>
"""
import json
import pathlib
import sys

REGISTRY = pathlib.Path(__file__).with_name("product-registry.json")
SUITES = ("api", "consumer", "partner", "executor", "admin", "multi-role", "full")


def plan(product, suite, registry=None):
    reg = registry or json.loads(REGISTRY.read_text(encoding="utf-8"))
    products = reg["products"]
    if suite not in SUITES:
        raise ValueError("unknown suite %r" % suite)
    if product != "all" and product not in products:
        raise ValueError("unknown product %r" % product)
    names = sorted(products) if product == "all" else [product]
    workflows, unavailable = set(), []
    for name in names:
        e2e = products[name].get("e2e", {})
        if suite == "api":
            found = {reg["e2e_api_workflow"]}
        elif suite == "full":
            found = {w for ws in e2e.values() for w in ws} | {reg["e2e_api_workflow"]}
        else:
            found = set(e2e.get(suite, []))
        if found:
            workflows |= found
        else:
            unavailable.append("%s/%s" % (name, suite))
    return {"workflows": sorted(workflows), "unavailable": unavailable}


if __name__ == "__main__":
    try:
        print(json.dumps(plan(sys.argv[1], sys.argv[2])))
    except (ValueError, IndexError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        sys.exit(2)
