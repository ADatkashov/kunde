#!/usr/bin/env python3
"""Synthetic DEV-only flowers checkout and partner operations over HTTP.

Usage: flowers_smoke.py BASE_URL [CUSTOMER_PHONE]. Creates synthetic DEV data;
never use against production. Requires the synthetic partner seeds and DEV OTP.
"""
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


stores = call("GET", "/api/v1/food/restaurants?vertical=FLOWERS_GIFTS")
store = next((s for s in stores if s["slug"] == "partner-flowers-demo" and s["synthetic"]), None)
if not store:
    sys.exit("FAIL: synthetic flowers store missing")
menu = call("GET", "/api/v1/food/restaurants/" + store["id"])
item = next(d for s in menu["sections"] for d in s["dishes"] if d["available"] and d["maxQuantity"] > 0)
customer_session = login(customer_phone)
customer = customer_session["accessToken"]
partner = login(partner_phone)["accessToken"]
other = login(other_phone)["accessToken"]
partners = call("GET", "/api/v1/partner/partners", token=partner)
pid = next(p["id"] for p in partners if p["verificationStatus"] == "APPROVED")
other_pid = next(p["id"] for p in call("GET", "/api/v1/partner/partners", token=other))
address = call("POST", "/api/v1/me/addresses", {"label": "Smoke",
    "formattedAddress": "Алматы, ул. Тестовая 1 (синтетический адрес)",
    "latitude": 43.238949, "longitude": 76.889709}, token=customer, expect=201)
items = [{"dishId": item["id"], "quantity": 1, "optionIds": []}]
quote = call("POST", "/api/v1/food/cart/quote", {"restaurantId": store["id"], "items": items}, token=customer)
order_request = {"restaurantId": store["id"], "items": items, "addressId": address["id"],
                 "paymentMethod": "DEV_NO_PAYMENT", "expectedTotalMinor": quote["totalMinor"]}
call("POST", "/api/v1/food/orders", {**order_request, "expectedTotalMinor": -1}, token=customer,
     headers={"Idempotency-Key": key()}, expect=409)
order_key = key()
order = call("POST", "/api/v1/food/orders", order_request, token=customer,
             headers={"Idempotency-Key": order_key}, expect=201)
assert order["paymentStatus"] == "NO_PAYMENT" and not order["simulated"] and order["fulfillment"] == "PARTNER", order
assert call("POST", "/api/v1/food/orders", order_request, token=customer,
            headers={"Idempotency-Key": order_key})["id"] == order["id"]
food = f"/api/v1/partner/partners/{pid}/food"
call("GET", f"/api/v1/partner/partners/{other_pid}/food/orders/{order['id']}", token=other, expect=404)
call("GET", f"{food}/orders/{order['id']}", token=partner)
for status in ["ACCEPTED", "PREPARING", "ON_THE_WAY", "DELIVERED"]:
    call("POST", f"{food}/orders/{order['id']}/status", {"status": status}, token=partner)
    assert call("GET", f"/api/v1/food/orders/{order['id']}", token=customer)["status"] == status
assert any(o["id"] == order["id"] for o in call("GET", "/api/v1/food/orders", token=customer))
print("FLOWERS SMOKE OK (synthetic order; no payment or actual delivery)")
