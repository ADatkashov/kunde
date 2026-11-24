#!/usr/bin/env python3
"""Markdown tables for docs/architecture from the real coupling data (no network, no database).

Run the fast architecture tests first (they write backend/app/build/architecture/coupling.tsv):
  cd backend && ./gradlew :app:test --tests 'kz.kunde.architecture.*'
  python3 scripts/dev/architecture_matrix.py {matrix|ownership|readiness}
"""
import collections
import glob
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARCH = ROOT / "backend/app/src/test/resources/architecture"
CORE = {"identity", "auth", "partner", "catalog", "platform"}  # shared kernel and B2B directory: expected to be depended on
DOMAINS = ["auth", "identity", "partner", "catalog", "admin", "support", "food", "groceries", "delivery", "rides", "maps",
           "booking", "beauty", "homeservices", "health", "auto", "leisure", "events", "education"]
MODULE = {"auth": "identity", "identity": "identity", "partner": "partners", "catalog": "partners", "admin": "admin",
          "support": "support", "food": "food", "groceries": "groceries", "delivery": "delivery", "rides": "rides",
          "maps": "maps", "booking": "booking", "beauty": "beauty", "homeservices": "homeservices", "health": "health",
          "auto": "auto", "leisure": "leisure", "events": "events", "education": "education"}


def coupling():
    rows = (ROOT / "backend/app/build/architecture/coupling.tsv").read_text().splitlines()[1:]
    out = {}
    for r in rows:
        a, b, i, s = r.split("\t")
        out[(a, b)] = (int(i), int(s))
    return out


def lines(path):
    return [l.strip() for l in path.read_text().splitlines() if l.strip() and not l.startswith("#")]


def owners():
    return [tuple(l.split("=")) for l in lines(ARCH / "table-owners.txt")]


def owner_of(t, table):
    for p, o in table:
        if t.startswith(p):
            return o


def tables():
    t = owners()
    found = set()
    for f in glob.glob(str(ROOT / "backend/app/src/main/resources/db/migration/*.sql")):
        for m in re.finditer(r"create\s+table\s+(?:if\s+not\s+exists\s+)?(\w+\.\w+)", Path(f).read_text(), re.I):
            found.add(m[1].lower())
    by = collections.defaultdict(list)
    for x in sorted(found):
        by[owner_of(x, t)].append(x)
    return by


def fks():
    out = []
    for l in lines(ARCH / "cross-owner-foreign-keys.txt"):
        m = re.match(r"(\S+) -> (\S+) \((\w+) -> (\w+)\)", l)
        out.append(m.groups())
    return out


def cycles():
    nodes = set()
    for l in lines(ARCH / "known-coupling-cycles.txt"):
        a, b = l.split(" -> ")
        nodes |= {a, b}
    return nodes


def matrix():
    c = coupling()
    print("| из \\ в | " + " | ".join(DOMAINS) + " |")
    print("|---|" + "---|" * len(DOMAINS))
    for a in DOMAINS:
        cells = []
        for b in DOMAINS:
            i, s = c.get((a, b), (0, 0))
            cells.append("" if not (i or s) else (f"{i}i" if i else "") + ("+" if i and s else "") + (f"{s}s" if s else ""))
        print(f"| **{a}** | " + " | ".join(cells) + " |")


def ownership():
    by = tables()
    f = fks()
    out_fk = collections.Counter(x[2] for x in f)
    in_fk = collections.Counter(x[3] for x in f)
    c = coupling()
    sql_in = collections.Counter()
    for (a, b), (i, s) in c.items():
        sql_in[b] += s
    print("| Владелец | Таблиц | Входящих чужих SQL-ссылок | FK наружу | FK внутрь |")
    print("|---|---|---|---|---|")
    for d in DOMAINS + ["platform"]:
        n = len(by.get(d, []))
        print(f"| {d} | {n} | {sql_in[d]} | {out_fk[d]} | {in_fk[d]} |")
    print()
    print(f"Всего таблиц: {sum(len(v) for v in by.values())}; FK между владельцами: {len(f)}.")


def readiness():
    c = coupling()
    f = fks()
    knot = cycles()
    inbound_sql = collections.Counter()
    out_sql = collections.Counter()
    out_imp = collections.Counter()
    for (a, b), (i, s) in c.items():
        allowed = (a, b) in {("auto", "booking"), ("beauty", "booking"), ("health", "booking"), ("homeservices", "booking")}
        if b not in CORE and not allowed:
            out_sql[a] += s
            out_imp[a] += i
        if b not in CORE:
            inbound_sql[b] += s
    for (a, b), (i, s) in c.items():
        if a in CORE and b not in CORE:  # core reaching into a domain is a real inversion
            out_sql[a] += s
            out_imp[a] += i
    fk_nc = collections.Counter()
    for _, _, o, t in f:
        if o not in CORE and t not in CORE:
            fk_nc[o] += 1
            fk_nc[t] += 1
    print("| Домен | Оценка | Исходящие чужие SQL/импорты | Чужие читают его таблицы | FK с другим доменом | В узле циклов |")
    print("|---|---|---|---|---|---|")
    for d in DOMAINS:
        if d == "maps":
            print("| maps | 95 | 0 / 0 | 0 | 0 | нет |")
            continue
        pen = min(30, 3 * out_sql[d]) + min(15, 2 * out_imp[d]) + min(20, 2 * inbound_sql[d]) + min(15, 2 * fk_nc[d])
        pen += 15 if d in knot else 0
        pen += 10  # события/outbox: ни один домен их ещё не публикует
        score = max(0, 100 - pen)
        print(f"| {d} | {score} | {out_sql[d]} / {out_imp[d]} | {inbound_sql[d]} | {fk_nc[d]} | {'да' if d in knot else 'нет'} |")


if __name__ == "__main__":
    {"matrix": matrix, "ownership": ownership, "readiness": readiness}[sys.argv[1]]()
