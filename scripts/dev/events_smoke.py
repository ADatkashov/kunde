#!/usr/bin/env python3
"""End-to-end smoke test of KUNDE Events & Tickets on a DEV backend over real HTTP (stdlib only).

Usage: events_smoke.py BASE_URL [CUSTOMER_PHONE] [--keep]
Events is a product view over the shared ticketing engine: this checks the separation from Leisure (own catalogue, one canonical card, global
search routing), buys two cinema seats with the DEV/TEST ledger (no real charge), repeats the purchase with the same key, checks the seat
cannot be sold twice, then runs the gate: an unassigned user is ACCESS_DENIED, the organiser assigns a GATE controller, who accepts and scans
(the server decides; ADMITTED once and DUPLICATE when a seeded session is inside the 2-hour entry window, otherwise TOO_EARLY). Finally the
order is cancelled for a TEST refund. Exit code 1 on the first failed check.
"""
import datetime
import urllib.parse
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
if not caps.get("eventsEnabled") or not caps.get("leisureEnabled"):
    sys.exit(f"FAIL: both products must be enabled (eventsEnabled={caps.get('eventsEnabled')}, leisureEnabled={caps.get('leisureEnabled')})")
ev_cats = call("GET", "/api/v1/events/categories")
le_cats = call("GET", "/api/v1/leisure/categories")
assert {c["code"] for c in ev_cats}.isdisjoint({c["code"] for c in le_cats}), "no category may be in both products"
assert {"CINEMA", "CONCERT", "THEATER"} <= {c["code"] for c in ev_cats}, "cinema, concerts and theatre are Events"
assert {"QUEST", "BOWLING", "GAMING_VR"} <= {c["code"] for c in le_cats}, "quests, bowling and VR are Leisure"
assert call("GET", "/api/v1/leisure/events?category=CINEMA") == [], "cinema is not a leisure activity"
assert call("GET", "/api/v1/events?category=BOWLING") == [], "bowling is not an event"
for q, route in (("концерт", "EVENTS"), ("театр", "EVENTS"), ("кино", "EVENTS"), ("квест", "LEISURE"), ("боулинг", "LEISURE")):
    got = call("GET", "/api/v1/search/route?q=" + urllib.parse.quote(q))["route"]
    assert got == route, f"search '{q}' must route to {route}, got {got}"
cards = call("GET", "/api/v1/events?category=CINEMA&limit=20")
if not cards:
    sys.exit("FAIL: no cinema events seeded (LEISURE_SEED_DEMO on a build with V40?)")
call("GET", "/api/v1/events/home?lat=43.22&lng=76.93")
call("GET", "/api/v1/leisure/orders", expect=401)
card = next(c for c in cards if c["bookingType"] == "SEAT_MAP" and c["minAge"] == 12)
detail = call("GET", "/api/v1/events/" + card["id"])
assert detail["product"] == "EVENTS" and detail["demo"] is True and detail["rating"] is None, "synthetic Events card, no invented rating"
assert call("GET", "/api/v1/leisure/events/" + card["id"])["id"] == card["id"], "one canonical card"
bowling = call("GET", "/api/v1/leisure/events?category=BOWLING&limit=5")[0]
call("GET", "/api/v1/events/" + bowling["id"], expect=404)
std = next(t for t in detail["ticketTypes"] if t["zone"] == "STANDARD")
sessions = call("GET", f"/api/v1/events/{card['id']}/sessions?days=7")
now = datetime.datetime.now(datetime.timezone.utc)
inside = [s for s in sessions if now < datetime.datetime.fromisoformat(s["startsAt"]) < now + datetime.timedelta(hours=1, minutes=45) and s["free"] >= 5]
far = [s for s in sessions if datetime.datetime.fromisoformat(s["startsAt"]) > now + datetime.timedelta(hours=8)]
session_id = (inside or far or sessions)[-1]["id"] if not inside else inside[0]["id"]
seats = call("GET", f"/api/v1/leisure/sessions/{session_id}/seats")
free = [s for s in seats if s["status"] == "FREE" and s["zone"] == "STANDARD"]
a, b = free[-1], free[-2]

token = login(phone)
hold = call("POST", f"/api/v1/leisure/sessions/{session_id}/holds", {"lines": [{"ticketTypeId": std["id"], "quantity": 2, "seatIds": [a["id"], b["id"]]}]}, token, expect=201)
assert hold["totalMinor"] == 2 * std["priceMinor"], "server must price the hold"
other = login(owner_b)
call("POST", f"/api/v1/leisure/sessions/{session_id}/holds", {"lines": [{"ticketTypeId": std["id"], "quantity": 1, "seatIds": [a["id"]]}]}, other, expect=409)

key = "smoke-" + uuid.uuid4().hex[:24]
order_body = {"holdId": hold["id"], "paymentMethod": "TEST_CARD", "ageConfirmed": True}
order = call("POST", "/api/v1/leisure/orders", order_body, token, {"Idempotency-Key": key}, expect=201)
again = call("POST", "/api/v1/leisure/orders", order_body, token, {"Idempotency-Key": key}, expect=200)
assert again["id"] == order["id"], "replay must return the same order"
assert order["payment"]["status"] == "TEST_CAPTURED" and order["payment"]["mode"] == "DEV_TEST"
qr = order["tickets"][0]["qr"]
assert qr.startswith("KT1.") and "77000" not in qr, "QR must not carry personal data"
call("POST", "/api/v1/leisure/orders", {"holdId": hold["id"], "paymentMethod": "APPLE_PAY"}, token, {"Idempotency-Key": "smoke-" + uuid.uuid4().hex[:24]}, expect=422)
call("GET", "/api/v1/leisure/orders/" + order["id"], None, other, expect=404)

# ---- gate: an assigned controller scans, anyone else is refused without detail
owner_a_token = login(owner_a)
pid = next(p["id"] for p in call("GET", "/api/v1/partner/partners", None, owner_a_token) if p["verificationStatus"] == "APPROVED")
# the customer is never assigned as a controller: refused without any detail of the ticket (the controller may already be assigned by an earlier run)
denied = call("POST", "/api/v1/executor/leisure/checkins", {"code": qr}, token)
assert denied["result"] == "ACCESS_DENIED" and denied.get("eventTitle") is None, denied
assignment = call("POST", f"/api/v1/partner/partners/{pid}/leisure/sessions/{session_id}/assignments", {"phone": owner_b, "role": "GATE"}, owner_a_token, expect=[200, 201, 409])
if assignment and assignment.get("id"):
    call("POST", f"/api/v1/executor/leisure/assignments/{assignment['id']}/step", {"step": "ACCEPT"}, other)
else:  # already assigned by an earlier run: accept what is offered
    for row in call("GET", "/api/v1/executor/leisure/assignments", None, other):
        if row["sessionId"] == session_id and row["role"] == "GATE" and row["status"] == "OFFERED":
            call("POST", f"/api/v1/executor/leisure/assignments/{row['id']}/step", {"step": "ACCEPT"}, other)
scan = call("POST", "/api/v1/executor/leisure/checkins", {"code": qr}, other)
assert scan["result"] in ("TOO_EARLY", "ADMITTED"), scan
if scan["result"] == "ADMITTED":
    assert call("POST", "/api/v1/executor/leisure/checkins", {"code": qr}, other)["result"] == "DUPLICATE", "second scan must be a duplicate"
    print("note: ADMITTED then DUPLICATE verified (a seeded session was inside the entry window)")
else:
    print("note: TOO_EARLY - the server decided; ADMITTED/DUPLICATE need a session inside the window (covered by integration tests and the native E2E)")
bad = call("POST", "/api/v1/executor/leisure/checkins", {"code": "KT1." + str(uuid.uuid4()) + "." + "0" * 32}, other)
assert bad["result"] in ("INVALID", "ACCESS_DENIED"), bad
stats = call("GET", f"/api/v1/partner/partners/{pid}/leisure/stats?days=7&product=EVENTS", None, owner_a_token)
assert stats["orders"] >= 1
report = call("GET", f"/api/v1/partner/partners/{pid}/leisure/reports/sales?days=7&product=EVENTS", None, owner_a_token)
line = next((r for r in report if r["eventId"] == card["id"]), None)
assert line and line["product"] == "EVENTS" and line["tickets"] >= 2 and line["revenueMinor"] >= 2 * std["priceMinor"], line
call("GET", f"/api/v1/partner/partners/{pid}/leisure/reports/sales?days=7", None, other, expect=[403, 404])  # another organiser must not read this report

if not keep and scan["result"] != "ADMITTED":
    cancelled = call("POST", f"/api/v1/leisure/orders/{order['id']}/cancel", None, token)
    assert cancelled["status"] == "CANCELLED" and cancelled["payment"]["status"] == "TEST_REFUNDED", cancelled
    seats_after = call("GET", f"/api/v1/leisure/sessions/{session_id}/seats")
    assert next(s for s in seats_after if s["id"] == a["id"])["status"] == "FREE", "seat must be free again"

print("SMOKE OK")
