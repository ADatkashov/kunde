#!/usr/bin/env python3
"""End-to-end smoke test of the KUNDE barbershop booking DEV pilot over real HTTP (stdlib only).

Usage: booking_smoke.py BASE_URL [PHONE] [--keep]
Needs a backend started with HOME_SERVICES_ENABLED, BOOKING_ENABLED (and BOOKING_SEED_DEMO), AUTH_PHONE_ENABLED and AUTH_DEV_OTP_ENABLED in a
dev/local/test environment and a synthetic allowlisted number (default +77000000001). Books one slot and cancels it
(unless --keep); exit code 1 on the first failed check.
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
if not caps.get("bookingEnabled"):
    sys.exit("FAIL: booking is not enabled on this backend (bookingEnabled=false)")
venues = call("GET", "/api/v1/booking/venues")
if len(venues) < 3:
    sys.exit(f"FAIL: expected seeded barbershops, got {len(venues)}")
call("GET", "/api/v1/booking/bookings", expect=401)

call("POST", "/api/v1/auth/otp/request", {"phone": phone}, expect=202)
session = call("POST", "/api/v1/auth/otp/verify", {"phone": phone, "code": "123456"})
token = session["accessToken"]

venue = next(v for v in venues if v["slug"] == "barber-alatau")
detail = call("GET", "/api/v1/booking/venues/" + venue["id"])
service = next(s for s in detail["services"] if s["name"] == "Мужская стрижка")
arman = next(m for m in detail["masters"] if m["name"] == "Арман")
tomorrow = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5, days=1)).date().isoformat()
slots = call("GET", f"/api/v1/booking/slots?venueId={venue['id']}&serviceId={service['id']}&masterId={arman['id']}&date={tomorrow}")
assert slots, "no free slots for tomorrow"
slot = slots[len(slots) // 2]
req = {"venueId": venue["id"], "serviceId": service["id"], "masterId": arman["id"], "startsAt": slot["startsAt"], "comment": "smoke"}
key = "smoke-" + uuid.uuid4().hex
booking = call("POST", "/api/v1/booking/bookings", req, token=token, headers={"Idempotency-Key": key}, expect=201)
assert booking["status"] == "CONFIRMED" and booking["confirmation"] == "DEV_MOCK" and booking["cancellable"], booking
again = call("POST", "/api/v1/booking/bookings", req, token=token, headers={"Idempotency-Key": key}, expect=200)
assert again["id"] == booking["id"], "idempotent replay must return the same booking"

after = call("GET", f"/api/v1/booking/slots?venueId={venue['id']}&serviceId={service['id']}&masterId={arman['id']}&date={tomorrow}")
assert slot["startsAt"] not in [s["startsAt"] for s in after], "booked slot must disappear"
call("POST", "/api/v1/booking/bookings", dict(req, comment=None), token=token,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=409)  # same time, same master: refused

# Re-open: the app restores its session from the refresh token and still sees the persisted booking.
session2 = call("POST", "/api/v1/auth/token/refresh", {"refreshToken": session["refreshToken"]})  # refresh tokens rotate
token2 = session2["accessToken"]
history = call("GET", "/api/v1/booking/bookings", token=token2)
assert any(b["id"] == booking["id"] for b in history), "booking not restored after session refresh"

if "--keep" not in sys.argv:
    cancelled = call("POST", f"/api/v1/booking/bookings/{booking['id']}/cancel", token=token2)
    assert cancelled["status"] == "CANCELLED", cancelled
    call("POST", f"/api/v1/booking/bookings/{booking['id']}/cancel", token=token2, expect=409)
    freed = call("GET", f"/api/v1/booking/slots?venueId={venue['id']}&serviceId={service['id']}&masterId={arman['id']}&date={tomorrow}")
    assert slot["startsAt"] in [s["startsAt"] for s in freed], "cancelled slot must be free again"

# Home services: cleaning reuses the same booking mechanism (category CLEANING, address + area, server-side price).
cleaning = call("GET", "/api/v1/booking/venues?category=CLEANING")
if not cleaning:
    sys.exit("FAIL: no cleaning venue seeded (BOOKING_SEED_DEMO on a build with V19?)")
assert all(v["category"] == "CLEANING" for v in cleaning) and all(v["slug"] != "barber-alatau" for v in cleaning)
cdetail = call("GET", "/api/v1/booking/venues/" + cleaning[0]["id"])
ctype = next(sv for sv in cdetail["services"] if sv["name"] == "Генеральная уборка")
cslots = call("GET", f"/api/v1/booking/slots?venueId={cleaning[0]['id']}&serviceId={ctype['id']}&date={tomorrow}")
assert cslots, "no cleaning slots for tomorrow"
cslot = cslots[len(cslots) // 2]
creq = {"venueId": cleaning[0]["id"], "serviceId": ctype["id"], "masterId": cslot["masterId"], "startsAt": cslot["startsAt"],
        "addressText": "Алматы, тестовый адрес 1 (smoke)", "areaSqm": 50}
call("POST", "/api/v1/booking/bookings", dict(creq, addressText=None), token=token2,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=400)  # address is required
call("POST", "/api/v1/booking/bookings", dict(creq, areaSqm=5), token=token2,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=400)  # area out of range
ckey = "smoke-" + uuid.uuid4().hex
cleaned = call("POST", "/api/v1/booking/bookings", creq, token=token2, headers={"Idempotency-Key": ckey}, expect=201)
assert cleaned["category"] == "CLEANING" and cleaned["areaSqm"] == 50, cleaned
assert cleaned["priceMinor"] == ctype["priceMinor"] + ctype["pricePerSqmMinor"] * 50, "price must be computed by the server"
call("POST", "/api/v1/booking/bookings", creq, token=token2, headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=409)
token3 = call("POST", "/api/v1/auth/token/refresh", {"refreshToken": session2["refreshToken"]})["accessToken"]
assert any(b["id"] == cleaned["id"] and b["category"] == "CLEANING" for b in call("GET", "/api/v1/booking/bookings", token=token3)), \
    "cleaning request not restored after session refresh"
if "--keep" not in sys.argv:
    assert call("POST", f"/api/v1/booking/bookings/{cleaned['id']}/cancel", token=token3)["status"] == "CANCELLED"
print("SMOKE OK")
