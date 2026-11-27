#!/usr/bin/env python3
"""Synthetic DEV-only smoke of the Flowers & Gifts domain (ADR-026): catalogue, delivery windows, quote, idempotent order,
history and cancellation over HTTP.

Usage: flowers_domain_smoke.py BASE_URL [CUSTOMER_PHONE]. Creates (and cancels) one synthetic order; never use against
production. Needs FLOWERS_ENABLED and the synthetic DEV OTP. The old Food-vertical path is covered by flowers_smoke.py.
"""
import datetime
import json
import sys
import urllib.error
import urllib.request
import uuid

base = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://localhost:8080"
customer_phone = sys.argv[2] if len(sys.argv) > 2 else "+77000000001"


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
if not caps.get("flowersEnabled"):
    sys.exit("FAIL: flowersEnabled is false (set FLOWERS_ENABLED=true on the DEV backend)")

categories = call("GET", "/api/v1/flowers/categories")
assert any(c["code"] == "BOUQUETS" for c in categories), categories
shops = call("GET", "/api/v1/flowers/shops")
shop = next((s for s in shops if s["synthetic"] and s["open"] and s["productCount"] > 0), None)
if not shop:
    sys.exit("FAIL: no open synthetic flowers shop with products (seed: Food flowers demo is copied by V74, or FLOWERS_SEED_DEMO)")
detail = call("GET", "/api/v1/flowers/shops/" + shop["id"])
product = next(p for p in detail["products"] if p["available"] and (p["stockQty"] is None or p["stockQty"] >= 1))
call("GET", "/api/v1/flowers/products/popular")
call("GET", "/api/v1/flowers/shops/" + str(uuid.uuid4()), expect=404)

day = (datetime.date.today() + datetime.timedelta(days=3)).isoformat()
slots = call("GET", "/api/v1/flowers/delivery-slots?date=" + day)
assert len(slots) == 5, slots

session = call("POST", "/api/v1/auth/otp/request", {"phone": customer_phone}, expect=202)
token = call("POST", "/api/v1/auth/otp/verify", {"phone": customer_phone, "code": "123456"})["accessToken"]
items = [{"productId": product["id"], "quantity": 1}]
quote = call("POST", "/api/v1/flowers/cart/quote", {"shopId": shop["id"], "items": items, "deliveryMode": "ASAP"}, token=token)
assert quote["totalMinor"] == quote["subtotalMinor"] + quote["deliveryFeeMinor"], quote
body = {"shopId": shop["id"], "items": items, "deliveryMode": "ASAP", "addressLabel": "Smoke",
        "addressText": "Алматы, ул. Тестовая 1 (синтетический адрес)", "recipientName": "Тест",
        "cardText": "Синтетический заказ", "expectedTotalMinor": quote["totalMinor"]}
call("POST", "/api/v1/flowers/orders", {**body, "expectedTotalMinor": -1}, token=token,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=409)
key = "smoke-" + uuid.uuid4().hex
order = call("POST", "/api/v1/flowers/orders", body, token=token, headers={"Idempotency-Key": key}, expect=201)
assert order["paymentMethod"] == "DEV_NO_PAYMENT" and order["paymentStatus"] == "NO_PAYMENT", order
assert call("POST", "/api/v1/flowers/orders", body, token=token, headers={"Idempotency-Key": key})["id"] == order["id"]
assert any(o["id"] == order["id"] for o in call("GET", "/api/v1/flowers/orders", token=token))
call("GET", "/api/v1/flowers/orders/" + order["id"], token=token)
# the order is cancelled right away (free while PLACED), so the smoke leaves no live order and the stock goes back
cancelled = call("POST", f"/api/v1/flowers/orders/{order['id']}/cancel", token=token, expect=[200, 409])
print("FLOWERS DOMAIN SMOKE OK (synthetic order; status after cancel: %s)" % (cancelled or {}).get("status", "?"))
