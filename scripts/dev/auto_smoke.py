#!/usr/bin/env python3
"""End-to-end smoke test of the KUNDE Auto DEV pilot over real HTTP (stdlib only).

Usage: auto_smoke.py BASE_URL [PHONE] [--keep]
Needs a backend started with AUTO_ENABLED, AUTO_SEED_DEMO, BOOKING_ENABLED, AUTH_PHONE_ENABLED and AUTH_DEV_OTP_ENABLED in a
dev/local/test environment and a synthetic allowlisted number (default +77000000001). Books one service with the DEV/TEST
ledger payment (no real charge), replays it idempotently and cancels it (unless --keep); exit code 1 on the first failed check.
"""
import datetime
import json
import sys
import urllib.error
import urllib.request
import uuid

base = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://localhost:8080"
phone = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "+77000000001"


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


caps = call("GET", "/api/v1/capabilities")
if not caps.get("autoEnabled"):
    sys.exit("FAIL: Auto is not enabled on this backend (autoEnabled=false)")
categories = call("GET", "/api/v1/auto/categories")
assert len(categories) >= 8, f"expected the 8 seeded categories, got {len(categories)}"
venues = call("GET", "/api/v1/auto/venues")
if not venues:
    sys.exit("FAIL: no Auto venues seeded (AUTO_SEED_DEMO on a build with V34+?)")
assert all(v.get("synthetic") for v in venues), "DEV demo venues must be marked synthetic"
call("GET", "/api/v1/auto/bookings", expect=401)
call("GET", "/api/v1/auto/vehicles", expect=401)

call("POST", "/api/v1/auth/otp/request", {"phone": phone}, expect=202)
session = call("POST", "/api/v1/auth/otp/verify", {"phone": phone, "code": "123456"})
token = session["accessToken"]

venue = venues[0]
detail = call("GET", "/api/v1/auto/venues/" + venue["id"])
service = next(s for s in detail["services"] if s.get("available"))
tomorrow = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5, days=1)).date().isoformat()
slots = call("GET", f"/api/v1/auto/slots?venueId={venue['id']}&serviceId={service['id']}&date={tomorrow}")
assert slots, "no free slots for tomorrow"
slot = slots[len(slots) // 2]

vehicle = call("POST", "/api/v1/auto/vehicles",
               {"make": "Toyota", "model": "Camry", "year": 2018, "plate": "SMK" + uuid.uuid4().hex[:3].upper() + "02"},
               token=token, expect=201)
quote = call("POST", "/api/v1/auto/quotes",
             {"venueId": venue["id"], "serviceId": service["id"], "vehicleId": vehicle["id"], "startsAt": slot["startsAt"]},
             token=token, expect=[200, 201])
assert quote["priceMinor"] == service["priceMinor"], "price must be computed by the server"

# Real card data is never accepted; only the DEV/TEST ledger method exists.
call("POST", "/api/v1/auto/bookings", {"quoteId": quote["id"], "paymentMethod": "REAL_CARD"}, token=token,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=[400, 422])

key = "smoke-" + uuid.uuid4().hex
body = {"quoteId": quote["id"], "paymentMethod": "TEST_CARD"}
booking = call("POST", "/api/v1/auto/bookings", body, token=token, headers={"Idempotency-Key": key}, expect=[200, 201])
payment = booking.get("payment") or {}
assert payment.get("method") == "TEST_CARD" and payment.get("status") == "TEST_HELD", payment
assert payment.get("capturedMinor") == 0, "nothing may be captured before the service is done"
again = call("POST", "/api/v1/auto/bookings", body, token=token, headers={"Idempotency-Key": key}, expect=[200, 201])
assert again["id"] == booking["id"], "idempotent replay must return the same booking"

session2 = call("POST", "/api/v1/auth/token/refresh", {"refreshToken": session["refreshToken"]})
token2 = session2["accessToken"]
history = call("GET", "/api/v1/auto/bookings", token=token2)
assert any(b["id"] == booking["id"] for b in history), "booking not restored after session refresh"

if "--keep" not in sys.argv:
    cancelled = call("POST", f"/api/v1/auto/bookings/{booking['id']}/cancel", token=token2)
    assert cancelled["status"] == "CANCELLED", cancelled
    assert (cancelled.get("payment") or {}).get("status") == "TEST_VOIDED", "the test hold must be released on cancel"
    replay = call("POST", f"/api/v1/auto/bookings/{booking['id']}/cancel", token=token2)  # cancelling twice is idempotent
    assert replay["status"] == "CANCELLED", replay
    call("DELETE", f"/api/v1/auto/vehicles/{vehicle['id']}", token=token2, expect=204)
print("SMOKE OK")
