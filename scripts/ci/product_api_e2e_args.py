#!/usr/bin/env python3
"""Gradle arguments of the selective Product API E2E (ADR-027), one per line.

A product's API E2E = its module unit tests plus the HTTP/PostgreSQL integration tests of its packages in :app
(`kz.kunde.<package>.*`, see product-registry.json). `all` = every product. Shared platform tests are not included on purpose:
they belong to Backend CI. Usage: product_api_e2e_args.py <product|all>
"""
import json
import pathlib
import sys

REGISTRY = pathlib.Path(__file__).with_name("product-registry.json")


def args(product, registry=None):
    reg = registry or json.loads(REGISTRY.read_text(encoding="utf-8"))
    products = reg["products"]
    if product != "all" and product not in products:
        raise ValueError("unknown product %r" % product)
    names = sorted(products) if product == "all" else [product]
    out = [":services:%s:test" % products[n]["backend"] for n in names]
    packages = sorted({pkg for n in names for pkg in products[n]["app_test_packages"]})
    if packages:
        out.append(":app:test")
        for pkg in packages:
            out += ["--tests", "kz.kunde.%s.*" % pkg]
    return out


if __name__ == "__main__":
    try:
        print("\n".join(args(sys.argv[1])))
    except (ValueError, IndexError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        sys.exit(2)
