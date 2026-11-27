#!/usr/bin/env python3
"""DEV/TEST product profile -> environment variables (ADR-027). Uses the EXISTING backend flag names (application.yml).

  product_profile.py dev-home-services            # KEY=value lines (dotenv / Render environment / compose)
  product_profile.py dev-home-services --yaml     # `KEY: "value"` for a GitHub Actions env: block
  product_profile.py --list

A profile enables one product, its platform prerequisites and its demo seeders; EVERY other product flag and seeder is set to
false explicitly, so other products start no schedulers (DeliveryMaintenance is @ConditionalOnProperty app.delivery.enabled),
create no demo data and call no integrations. Identity/auth stay on (shared platform); Flyway migrations are never touched.
`dev-all` = every product. Never apply a profile to PROD: PROD flags are owned by the owner (AGENTS.md).
"""
import json
import pathlib
import sys

REGISTRY = pathlib.Path(__file__).resolve().parents[1] / "ci" / "product-registry.json"


def load():
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def all_flags(reg):
    return sorted({f for p in reg["products"].values() for f in p["profile_flags"]})


def profile(name, reg=None):
    reg = reg or load()
    if not name.startswith("dev-"):
        raise ValueError("profile names start with 'dev-': %r" % name)
    key = name[4:]
    if key != "all" and key not in reg["products"]:
        raise ValueError("unknown profile %r" % name)
    wanted = set(all_flags(reg)) if key == "all" else set(reg["products"][key]["profile_flags"])
    env = {f: "true" if f in wanted else "false" for f in all_flags(reg)}
    env.update(dict.fromkeys(reg["profile_always_on"], "true"))
    return dict(sorted(env.items()))


def main(argv):
    reg = load()
    if "--list" in argv:
        print("\n".join(["dev-" + k for k in sorted(reg["products"])] + ["dev-all"]))
        return 0
    names = [a for a in argv[1:] if not a.startswith("--")]
    try:
        env = profile(names[0], reg)
    except (ValueError, IndexError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    for k, v in env.items():
        print('%s: "%s"' % (k, v) if "--yaml" in argv else "%s=%s" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
