#!/usr/bin/env python3
"""End-to-end smoke test of KUNDE Partner Operations (DEV pilot) over real HTTP (stdlib only).

Usage: partner_ops_smoke.py BASE_URL [CUSTOMER_PHONE]
Needs a backend with FOOD_ENABLED, BOOKING_ENABLED, PARTNER_OPS_SEED_DEMO (synthetic partners +77000000002 / +77000000003,
restaurant partner-kitchen-demo, venue partner-salon-demo), AUTH_PHONE_ENABLED and AUTH_DEV_OTP_ENABLED with the three
synthetic numbers allowlisted. Scenario: the customer orders and books, the partner sees, accepts/rejects and completes,
the customer sees every status, history survives a session refresh; another partner and a plain customer are refused.
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
    return call("POST", "/api/v1/auth/otp/verify", {"phone": phone, "code": "123456"})


def key():
    return "smoke-" + uuid.uuid4().hex


caps = call("GET", "/api/v1/capabilities")
if not caps.get("marketplaceEnabled") or not caps.get("bookingEnabled"):
    sys.exit("FAIL: Food and Booking must both be enabled")
customer_session = login(customer_phone)
customer = customer_session["accessToken"]
partner_session = login(partner_phone)
partner = partner_session["accessToken"]
other = login(other_phone)["accessToken"]

# --- access control -------------------------------------------------------------------------------------------------
call("GET", "/api/v1/partner/partners", token=customer, expect=403)  # a plain customer has no partner scope
mine = call("GET", "/api/v1/partner/partners", token=partner)
demo = next((p for p in mine if p["verificationStatus"] == "APPROVED"), None)
if demo is None:
    sys.exit("FAIL: the synthetic partner is missing (PARTNER_OPS_SEED_DEMO on a build with V20?)")
pid = demo["id"]
other_partners = call("GET", "/api/v1/partner/partners", token=other)
assert all(p["id"] != pid for p in other_partners), "another partner must not see this partner"
call("GET", f"/api/v1/partner/partners/{pid}/food/orders", token=customer, expect=403)
call("GET", f"/api/v1/partner/partners/{pid}/food/orders", token=other, expect=404)
call("GET", f"/api/v1/partner/partners/{pid}/booking/bookings", token=other, expect=404)
call("GET", f"/api/v1/partner/partners/{pid}/food/orders", expect=401)
food = f"/api/v1/partner/partners/{pid}/food"
booking = f"/api/v1/partner/partners/{pid}/booking"

# --- food order: customer -> partner -> customer ---------------------------------------------------------------------
restaurants = call("GET", "/api/v1/food/restaurants")
kitchen = next((r for r in restaurants if r["slug"] == "partner-kitchen-demo"), None)
if kitchen is None:
    sys.exit("FAIL: the partner restaurant is not seeded")
detail = call("GET", "/api/v1/food/restaurants/" + kitchen["id"])
dish = next(d for s in detail["sections"] for d in s["dishes"] if d["name"] == "Плов с говядиной")
address = call("POST", "/api/v1/me/addresses", {
    "label": "Smoke", "formattedAddress": "Алматы, ул. Тестовая 1 (синтетический адрес)",
    "latitude": 43.238949, "longitude": 76.889709}, token=customer, expect=201)
cart = {"restaurantId": kitchen["id"], "items": [{"dishId": dish["id"], "quantity": 1, "optionIds": []}],
        "addressId": address["id"], "paymentMethod": "CASH_ON_DELIVERY", "comment": "smoke"}
k1 = key()
order = call("POST", "/api/v1/food/orders", cart, token=customer, headers={"Idempotency-Key": k1}, expect=201)
assert order["status"] == "PLACED" and order["simulated"] is False and order["fulfillment"] == "PARTNER", order
assert call("POST", "/api/v1/food/orders", cart, token=customer, headers={"Idempotency-Key": k1})["id"] == order["id"]

inbox = call("GET", food + "/orders", token=partner)
entry = next((e for e in inbox if e["order"]["id"] == order["id"]), None)
assert entry and entry["allowedNext"] == ["ACCEPTED", "CANCELLED"], inbox
call("GET", f"{food}/orders/{order['id']}", token=other, expect=404)  # other partner (wrong path) is refused
call("POST", f"{food}/orders/{order['id']}/status", {"status": "ACCEPTED"}, token=customer, expect=403)
for step in ["ACCEPTED", "PREPARING", "ON_THE_WAY", "DELIVERED"]:
    moved = call("POST", f"{food}/orders/{order['id']}/status", {"status": step}, token=partner)
    assert moved["order"]["status"] == step, moved
    assert call("GET", "/api/v1/food/orders/" + order["id"], token=customer)["status"] == step, "customer must see " + step
    call("POST", f"{food}/orders/{order['id']}/status", {"status": step}, token=partner)  # replay: no duplicate action
    if step == "ACCEPTED":
        call("POST", f"{food}/orders/{order['id']}/status", {"status": "DELIVERED"}, token=partner, expect=409)  # no skipping
final = call("GET", "/api/v1/food/orders/" + order["id"], token=customer)
assert [t["status"] for t in final["timeline"]] == ["PLACED", "ACCEPTED", "PREPARING", "ON_THE_WAY", "DELIVERED"], final["timeline"]
call("POST", f"{food}/orders/{order['id']}/status", {"status": "CANCELLED", "reason": "поздно"}, token=partner, expect=409)

rejected = call("POST", "/api/v1/food/orders", cart, token=customer, headers={"Idempotency-Key": key()}, expect=201)
call("POST", f"{food}/orders/{rejected['id']}/status", {"status": "CANCELLED"}, token=partner, expect=400)  # reason required
call("POST", f"{food}/orders/{rejected['id']}/status", {"status": "CANCELLED", "reason": "нет продуктов (smoke)"}, token=partner)
seen = call("GET", "/api/v1/food/orders/" + rejected["id"], token=customer)
assert seen["status"] == "CANCELLED" and seen["cancelledBy"] == "PARTNER" and seen["cancelReason"], seen

# availability: hide a dish, customers cannot order it, restore it
dishes = call("GET", f"{food}/restaurants/{kitchen['id']}/dishes", token=partner)
target = next(d for d in dishes if d["name"] == "Компот")
call("PATCH", f"{food}/restaurants/{kitchen['id']}/dishes/{target['id']}", {"available": False}, token=partner)
call("POST", "/api/v1/food/cart/quote", {"restaurantId": kitchen["id"], "items": [{"dishId": target["id"], "quantity": 3, "optionIds": []}]},
     token=customer, expect=422)
call("PATCH", f"{food}/restaurants/{kitchen['id']}/dishes/{target['id']}", {"available": True}, token=partner)

# --- booking: customer -> partner -> customer ------------------------------------------------------------------------
venues = call("GET", "/api/v1/booking/venues")
salon = next((v for v in venues if v["slug"] == "partner-salon-demo"), None)
if salon is None:
    sys.exit("FAIL: the partner venue is not seeded")
sdetail = call("GET", "/api/v1/booking/venues/" + salon["id"])
service = next(s for s in sdetail["services"] if s["name"] == "Мужская стрижка")
master = sdetail["masters"][0]
tomorrow = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5, days=1)).date().isoformat()
slots_path = f"/api/v1/booking/slots?venueId={salon['id']}&serviceId={service['id']}&masterId={master['id']}&date={tomorrow}"
slots = call("GET", slots_path)
assert len(slots) >= 3, "not enough free slots"
req = {"venueId": salon["id"], "serviceId": service["id"], "masterId": master["id"], "startsAt": slots[0]["startsAt"], "comment": "smoke"}
bk = key()
pending = call("POST", "/api/v1/booking/bookings", req, token=customer, headers={"Idempotency-Key": bk}, expect=201)
assert pending["status"] == "PENDING" and pending["confirmation"] == "PARTNER", pending
assert call("POST", "/api/v1/booking/bookings", req, token=customer, headers={"Idempotency-Key": bk})["id"] == pending["id"]
call("POST", "/api/v1/booking/bookings", req, token=customer, headers={"Idempotency-Key": key()}, expect=409)  # slot is held
assert slots[0]["startsAt"] not in [s["startsAt"] for s in call("GET", slots_path)]
requests = call("GET", booking + "/bookings?scope=requests", token=partner)
assert any(b["id"] == pending["id"] and b["allowedActions"] == ["CONFIRM", "REJECT"] for b in requests), requests
call("POST", f"{booking}/bookings/{pending['id']}/action", {"action": "CONFIRM"}, token=other, expect=404)
call("POST", f"{booking}/bookings/{pending['id']}/action", {"action": "CONFIRM"}, token=partner)
call("POST", f"{booking}/bookings/{pending['id']}/action", {"action": "CONFIRM"}, token=partner)  # replay
call("POST", f"{booking}/bookings/{pending['id']}/action", {"action": "REJECT", "reason": "поздно"}, token=partner, expect=409)
assert call("GET", "/api/v1/booking/bookings/" + pending["id"], token=customer)["status"] == "CONFIRMED"
call("POST", f"{booking}/bookings/{pending['id']}/action", {"action": "CANCEL"}, token=partner, expect=400)  # reason required
call("POST", f"{booking}/bookings/{pending['id']}/action", {"action": "CANCEL", "reason": "мастер заболел (smoke)"}, token=partner)
cancelled = call("GET", "/api/v1/booking/bookings/" + pending["id"], token=customer)
assert cancelled["status"] == "CANCELLED" and cancelled["cancelledBy"] == "PARTNER" and cancelled["cancelReason"], cancelled
assert slots[0]["startsAt"] in [s["startsAt"] for s in call("GET", slots_path)], "partner cancellation must free the slot"

second = call("POST", "/api/v1/booking/bookings", dict(req, startsAt=slots[1]["startsAt"]), token=customer,
              headers={"Idempotency-Key": key()}, expect=201)
call("POST", f"{booking}/bookings/{second['id']}/action", {"action": "REJECT", "reason": "нет времени (smoke)"}, token=partner)
assert call("GET", "/api/v1/booking/bookings/" + second["id"], token=customer)["status"] == "CANCELLED"
third = call("POST", "/api/v1/booking/bookings", dict(req, startsAt=slots[2]["startsAt"]), token=customer,
             headers={"Idempotency-Key": key()}, expect=201)
call("POST", f"{booking}/bookings/{third['id']}/action", {"action": "CONFIRM"}, token=partner)

# --- history persists: a refreshed session still sees everything -----------------------------------------------------
token2 = call("POST", "/api/v1/auth/token/refresh", {"refreshToken": customer_session["refreshToken"]})["accessToken"]
orders = {o["id"]: o for o in call("GET", "/api/v1/food/orders", token=token2)}
assert orders[order["id"]]["status"] == "DELIVERED" and orders[rejected["id"]]["status"] == "CANCELLED", "food history lost"
bookings = {b["id"]: b for b in call("GET", "/api/v1/booking/bookings", token=token2)}
assert bookings[pending["id"]]["status"] == "CANCELLED" and bookings[third["id"]]["status"] == "CONFIRMED", "booking history lost"
ptoken2 = call("POST", "/api/v1/auth/token/refresh", {"refreshToken": partner_session["refreshToken"]})["accessToken"]
history = call("GET", food + "/orders?scope=history", token=ptoken2)
assert {order["id"], rejected["id"]} <= {e["order"]["id"] for e in history}, "partner order history lost"
call("POST", f"{booking}/bookings/{third['id']}/action", {"action": "CANCEL", "reason": "уборка данных smoke"}, token=ptoken2)

print("SMOKE OK")
