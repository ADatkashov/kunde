#!/usr/bin/env python3
"""Smoke test of KUNDE Home Services (DEV pilot) over real HTTP (stdlib only).

Usage: home_services_smoke.py BASE_URL [CUSTOMER_PHONE]
Needs a backend with HOME_SERVICES_ENABLED, BOOKING_ENABLED, PARTNER_OPS_SEED_DEMO (synthetic partners +77000000002 / +77000000003),
AUTH_PHONE_ENABLED and AUTH_DEV_OTP_ENABLED with the synthetic numbers allowlisted.

Covers everything reachable with synthetic phones and no staff credentials: the flag, the public catalogue and quote, the partner
creating a draft offer for its own cleaning service and submitting it for moderation, the Admin queue and decision refused without
the HOME_SERVICES_CATALOG grant, a stranger partner refused, a customer booking a cleaning slot and reading the visit of its own
booking only, and the Executor API refusing an account that is not linked to a master. Approving the offer and walking the visit
(on the way, arrived, started, finished) need a staff grant and a linked master; they are covered by the backend integration tests
(HomeServicesOffersApiIntegrationTest, HomeServicesVisitApiIntegrationTest) and are left out here on purpose.
Exit code 1 on the first failed check.
"""
import datetime
import json
import sys
import urllib.error
import urllib.request
import uuid

base = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://localhost:8080"
customer_phone = sys.argv[2] if len(sys.argv) > 2 else "+77000000001"
partner_phone, other_phone = "+77000000002", "+77000000003"


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


def login(phone):
    call("POST", "/api/v1/auth/otp/request", {"phone": phone}, expect=202)
    return call("POST", "/api/v1/auth/otp/verify", {"phone": phone, "code": "123456"})["accessToken"]


caps = call("GET", "/api/v1/capabilities")
if not caps.get("homeServicesEnabled"):
    sys.exit("FAIL: Home Services is not enabled on this backend (homeServicesEnabled=false)")
if not caps.get("bookingEnabled"):
    sys.exit("FAIL: booking is not enabled on this backend (bookingEnabled=false)")

# Public catalogue and reference data.
categories = call("GET", "/api/v1/home-services/categories")
assert any(c["code"] == "CLEANING" for c in categories), "CLEANING category missing"
definitions = call("GET", "/api/v1/home-services/definitions?category=CLEANING")
assert definitions, "no cleaning definitions"
call("GET", "/api/v1/home-services/offers?limit=0", expect=400)
offers = call("GET", "/api/v1/home-services/offers")
assert isinstance(offers, list)
call("GET", "/api/v1/home-services/offers/" + str(uuid.uuid4()) + "/quote", expect=404)

customer, partner, stranger = login(customer_phone), login(partner_phone), login(other_phone)

# Partner: own organisation, own cleaning venue.
mine = call("GET", "/api/v1/partner/partners", token=partner)
partner_id = (mine[0]["id"] if isinstance(mine, list) else mine["partners"][0]["id"])
venues = call("GET", f"/api/v1/partner/partners/{partner_id}/booking/venues", token=partner)
cleaning = next((v for v in venues if v.get("category") == "CLEANING"), None)
if cleaning is None:
    sys.exit("FAIL: the synthetic partner has no CLEANING venue (is the demo seed on?)")
services = call("GET", f"/api/v1/partner/partners/{partner_id}/booking/venues/{cleaning['id']}/services", token=partner)
assert services, "cleaning venue has no services"
service = services[0]
offers_path = f"/api/v1/partner/partners/{partner_id}/home-services/offers"
existing = {o["serviceId"]: o for o in call("GET", offers_path, token=partner)}
if service["id"] in existing:
    offer = existing[service["id"]]
    print(f"ok   offer for this service already exists in status {offer['status']}")
else:
    offer = call("POST", offers_path, {"serviceId": service["id"], "definitionCode": definitions[0]["code"],
                                       "pricingModel": "FROM", "homeVisit": True, "warrantyDays": 14}, token=partner, expect=201)
    assert offer["status"] == "DRAFT", offer
if offer["status"] in ("DRAFT", "REJECTED"):
    sent = call("POST", f"{offers_path}/{offer['id']}/transition", {"action": "SUBMIT", "expectedVersion": offer["version"]}, token=partner)
    assert sent["status"] == "PENDING", sent

# Roles: a stranger partner and a plain customer see nothing of this organisation; Admin needs the grant.
call("GET", offers_path, token=stranger, expect=404)
call("GET", offers_path, token=customer, expect=404)
call("GET", "/api/v1/admin/home-services/offers?status=PENDING", token=customer, expect=403)
call("POST", f"/api/v1/admin/home-services/offers/{offer['id']}/decision",
     {"action": "APPROVE", "expectedVersion": 2, "reason": "smoke"}, token=partner, expect=403)
call("GET", "/api/v1/home-services/offers/" + offer["id"] + "/quote", expect=404 if offer["status"] != "PUBLISHED" else 200)

# Customer books a cleaning slot of the demo venue and reads the visit of its own booking only.
venue = call("GET", "/api/v1/booking/venues/" + cleaning["id"])
svc = venue["services"][0]
master = venue["masters"][0]
booking = None
for offset in range(1, 8):
    day = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5, days=offset)).date().isoformat()
    slots = call("GET", f"/api/v1/booking/slots?venueId={cleaning['id']}&serviceId={svc['id']}&date={day}")
    if slots:
        slot = slots[len(slots) // 2]
        body = {"venueId": cleaning["id"], "serviceId": svc["id"], "masterId": slot["masterId"], "startsAt": slot["startsAt"],
                "addressText": "Алматы, ул. Тестовая 1", "comment": "smoke"}
        if svc.get("pricePerSqmMinor") or svc.get("areaBased"):
            body["areaSqm"] = svc.get("minAreaSqm") or 40
        booking = call("POST", "/api/v1/booking/bookings", body, token=customer,
                       headers={"Idempotency-Key": "hs-smoke-" + uuid.uuid4().hex}, expect=201)
        break
if booking is None:
    sys.exit("FAIL: no free cleaning slot in the next week")
visit = call("GET", f"/api/v1/home-services/bookings/{booking['id']}/visit", token=customer)
assert visit["bookingId"] == booking["id"] and visit.get("stage") is None, visit
call("GET", f"/api/v1/home-services/bookings/{booking['id']}/visit", token=stranger, expect=404)
call("GET", f"/api/v1/home-services/bookings/{booking['id']}/visit", expect=401)

# Executor API: an account that is not linked to a master gets a clear refusal, never somebody else's jobs.
call("GET", "/api/v1/executor/home-services/jobs", token=customer, expect=404)
call("POST", "/api/v1/executor/home-services/link", {"code": "NOSUCH-0000"}, token=customer, expect=404)
call("POST", f"/api/v1/booking/bookings/{booking['id']}/cancel", token=customer)
print("home services smoke: all checks passed")
