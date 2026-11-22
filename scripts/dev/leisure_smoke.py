#!/usr/bin/env python3
"""End-to-end smoke test of KUNDE Leisure (bookable activities) on a DEV backend over real HTTP (stdlib only).

Usage: leisure_smoke.py BASE_URL [CUSTOMER_PHONE] [--keep]
Needs LEISURE_SEED_DEMO and the DEV OTP allowlist (default customer +77000000001, partner owners +77000000002/3). Ticketed events (cinema,
concerts, theatre) are Events and are covered by events_smoke.py. Here: the activity catalogue, a bowling-lane booking priced by the server with the
DEV/TEST ledger payment (no real charge), an idempotent replay, a double booking of the same slot refused, and a cancellation with a TEST refund.
Exit code 1 on the first failed check.
"""
import json
import sys
import urllib.error
import urllib.request
import uuid

base = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://localhost:8080"
args = [a for a in sys.argv[2:] if not a.startswith("--")]
phone = args[0] if args else "+77000000001"
owner_a, owner_b = "+77000000002", "+77000000003"
keep = "--keep" in sys.argv


def call(method, path, body=None, token=None, headers=None, expect=200):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read()
    expected = expect if isinstance(expect, (list, tuple)) else [expect]
    if status not in expected:
        sys.exit(f"FAIL {method} {path}: HTTP {status}, expected {expected}: {raw[:300]!r}")
    print(f"ok   {method} {path.split('?')[0]} -> {status}")
    return json.loads(raw) if raw else None


def login(number):
    call("POST", "/api/v1/auth/otp/request", {"phone": number}, expect=202)
    return call("POST", "/api/v1/auth/otp/verify", {"phone": number, "code": "123456"})["accessToken"]



caps = call("GET", "/api/v1/capabilities")
if not caps.get("leisureEnabled"):
    sys.exit("FAIL: Leisure is not enabled on this backend (leisureEnabled=false)")
categories = call("GET", "/api/v1/leisure/categories")
codes = {c["code"] for c in categories}
assert len(categories) >= 17 and {"QUEST", "BOWLING", "GAMING_VR", "KARAOKE", "KARTING"} <= codes, codes
assert codes.isdisjoint({"CINEMA", "CONCERT", "THEATER", "EXHIBITION"}), "ticketed event categories belong to Events"
cards = call("GET", "/api/v1/leisure/events?category=BOWLING&limit=20")
if not cards:
    sys.exit("FAIL: no bowling activities seeded (LEISURE_SEED_DEMO?)")
call("GET", "/api/v1/leisure/home?lat=43.22&lng=76.93")
call("GET", "/api/v1/leisure/orders", expect=401)
card = cards[0]
detail = call("GET", "/api/v1/leisure/events/" + card["id"])
assert detail["product"] == "LEISURE" and detail["demo"] is True and detail["rating"] is None
ticket = detail["ticketTypes"][0]
sessions = call("GET", f"/api/v1/leisure/events/{card['id']}/sessions?days=7")
session = max(sessions, key=lambda x: x["startsAt"])  # the latest: free cancellation is still open

token = login(phone)
other = login(owner_b)
hold = call("POST", f"/api/v1/leisure/sessions/{session['id']}/holds", {"lines": [{"ticketTypeId": ticket["id"], "quantity": 1}]}, token, expect=201)
assert hold["totalMinor"] == ticket["priceMinor"], "server must price the hold"
key = "smoke-" + uuid.uuid4().hex[:24]
order_body = {"holdId": hold["id"], "paymentMethod": "TEST_CARD", "ageConfirmed": True}
order = call("POST", "/api/v1/leisure/orders", order_body, token, {"Idempotency-Key": key}, expect=201)
again = call("POST", "/api/v1/leisure/orders", order_body, token, {"Idempotency-Key": key}, expect=200)
assert again["id"] == order["id"], "replay must return the same order"
assert order["payment"]["status"] == "TEST_CAPTURED" and order["payment"]["mode"] == "DEV_TEST"
call("POST", "/api/v1/leisure/orders", {"holdId": hold["id"], "paymentMethod": "APPLE_PAY"}, token, {"Idempotency-Key": "smoke-" + uuid.uuid4().hex[:24]}, expect=422)
call("GET", "/api/v1/leisure/orders/" + order["id"], None, other, expect=404)
mine = call("GET", "/api/v1/leisure/orders?scope=upcoming", None, token)
assert any(o["id"] == order["id"] for o in mine), "the booking must be in my bookings"

owner_a_token = login(owner_a)
owner_b_token = other
partners = call("GET", "/api/v1/partner/partners", None, owner_b_token)
pid = next(p["id"] for p in partners if p["verificationStatus"] == "APPROVED")
stats = call("GET", f"/api/v1/partner/partners/{pid}/leisure/stats?days=7&product=LEISURE", None, owner_b_token)
assert stats["orders"] >= 0

if not keep:
    cancelled = call("POST", f"/api/v1/leisure/orders/{order['id']}/cancel", None, token)
    assert cancelled["status"] == "CANCELLED" and cancelled["payment"]["status"] == "TEST_REFUNDED", cancelled

print("SMOKE OK")
