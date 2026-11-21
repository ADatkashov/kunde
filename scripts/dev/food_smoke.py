#!/usr/bin/env python3
"""End-to-end smoke test of the KUNDE Food DEV pilot over real HTTP (stdlib only).

Usage: food_smoke.py BASE_URL [PHONE] [--keep]
Uses a synthetic allowlisted DEV number (default +77000000001) and the DEV OTP code, so it only works against a
backend started with FOOD_ENABLED, AUTH_PHONE_ENABLED and AUTH_DEV_OTP_ENABLED in a dev/local/test environment.
Creates one synthetic address and one cancelled order; nothing else. Exit code 1 on the first failed check.
"""
import json
import sys
import time
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
    print(f"ok   {method} {path} -> {status}")
    return json.loads(raw) if raw else None


caps = call("GET", "/api/v1/capabilities")
if not caps.get("marketplaceEnabled"):
    sys.exit("FAIL: Food is not enabled on this backend (marketplaceEnabled=false)")
restaurants = call("GET", "/api/v1/food/restaurants")
if len(restaurants) < 5:
    sys.exit(f"FAIL: expected a seeded catalog, got {len(restaurants)} restaurants")
call("GET", "/api/v1/food/orders", expect=401)

call("POST", "/api/v1/auth/otp/request", {"phone": phone}, expect=202)
session = call("POST", "/api/v1/auth/otp/verify", {"phone": phone, "code": "123456"})
token = session["accessToken"]
call("POST", "/api/v1/auth/otp/verify", {"phone": phone, "code": "000000"}, expect=[400, 401, 429])

address = call("POST", "/api/v1/me/addresses", {
    "label": "Smoke", "formattedAddress": "Алматы, ул. Тестовая 1 (синтетический адрес)",
    "latitude": 43.238949, "longitude": 76.889709}, token=token, expect=201)

pick = next(r for r in restaurants if r["open"] and r["slug"] == "shaurma-express")
detail = call("GET", "/api/v1/food/restaurants/" + pick["id"])
dish = next(d for s in detail["sections"] for d in s["dishes"] if d["available"] and not d["optionGroups"]
            and d["name"] == "Шаурма с сыром")
cart = {"restaurantId": pick["id"], "items": [{"dishId": dish["id"], "quantity": 2, "optionIds": []}]}
quote = call("POST", "/api/v1/food/cart/quote", cart, token=token)
assert quote["subtotalMinor"] == dish["priceMinor"] * 2, quote

order_req = dict(cart, addressId=address["id"], paymentMethod="TEST_CARD", comment="smoke")
key = "smoke-" + uuid.uuid4().hex
order = call("POST", "/api/v1/food/orders", order_req, token=token, headers={"Idempotency-Key": key}, expect=201)
again = call("POST", "/api/v1/food/orders", order_req, token=token, headers={"Idempotency-Key": key}, expect=200)
assert again["id"] == order["id"], "idempotent replay must return the same order"
assert order["status"] == "PLACED" and order["totalMinor"] == quote["totalMinor"], order

history = call("GET", "/api/v1/food/orders", token=token)
assert any(o["id"] == order["id"] for o in history), "order missing from history"
call("GET", "/api/v1/food/orders/" + order["id"], token=token)
call("GET", "/api/v1/food/orders/" + order["id"] + "/repeat", token=token)
call("POST", "/api/v1/food/orders", dict(order_req, paymentMethod="BITCOIN"), token=token,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=422)

# Grocery vertical: same cart/order model, separate store list.
stores = call("GET", "/api/v1/food/restaurants?vertical=GROCERY")
assert len(stores) >= 3 and all(x["vertical"] == "GROCERY" for x in stores), "grocery stores missing"
market = next(x for x in stores if x["slug"] == "market-alatau")
market_menu = call("GET", "/api/v1/food/restaurants/" + market["id"])
bread = next(d for sct in market_menu["sections"] for d in sct["dishes"] if d["name"] == "Хлеб белый")
g_cart = {"restaurantId": market["id"], "items": [{"dishId": bread["id"], "quantity": 20, "optionIds": []}]}
g_order = call("POST", "/api/v1/food/orders", dict(g_cart, addressId=address["id"], paymentMethod="CASH_ON_DELIVERY"),
               token=token, headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=201)
assert g_order["vertical"] == "GROCERY", g_order
call("POST", "/api/v1/food/orders/" + g_order["id"] + "/cancel", token=token, expect=[200, 409])

# Weighed goods (grams, per-kg price), stock limit and substitution rules.
farm = next(x for x in stores if x["slug"] == "fermer-svezhest")
farm_menu = call("GET", "/api/v1/food/restaurants/" + farm["id"])
beef = next(d for sct in farm_menu["sections"] for d in sct["dishes"] if d["name"] == "Говядина вырезка")
assert beef["unit"] == "KG", beef
w_cart = {"restaurantId": farm["id"], "items": [{"dishId": beef["id"], "quantity": 1500, "optionIds": []}]}
w_quote = call("POST", "/api/v1/food/cart/quote", w_cart, token=token)
assert w_quote["subtotalMinor"] == (beef["priceMinor"] * 1500 + 500) // 1000, w_quote
call("POST", "/api/v1/food/cart/quote", {"restaurantId": farm["id"], "items": [{"dishId": beef["id"], "quantity": 150, "optionIds": []}]},
     token=token, expect=422)
alts = call("GET", "/api/v1/food/dishes/" + bread["id"] + "/alternatives")
assert alts and all(a["restaurantId"] == market["id"] for a in alts), alts
call("POST", "/api/v1/food/cart/quote", {"restaurantId": market["id"], "items": [
    {"dishId": bread["id"], "quantity": 20, "optionIds": [], "substitution": "CHOSEN", "substituteDishIds": []}]}, token=token, expect=422)
call("POST", "/api/v1/food/cart/quote", {"restaurantId": market["id"], "items": [
    {"dishId": bread["id"], "quantity": 20, "optionIds": [], "substitution": "CHOSEN", "substituteDishIds": [alts[0]["id"]]}]}, token=token)

# Food 2.0: server-side filters, promotions, pickup with a promo code, favorites and categories.
cats = call("GET", "/api/v1/food/categories")
assert cats and all("cuisine" in c for c in cats), cats
open_only = call("GET", "/api/v1/food/restaurants?openNow=true&sort=delivery_fee")
assert open_only and all(r["open"] for r in open_only), "openNow filter must return only open restaurants"
fees = [r["deliveryFeeMinor"] for r in open_only]
assert fees == sorted(fees), "sort=delivery_fee must be ascending"
call("GET", "/api/v1/food/restaurants?sort=distance", expect=400)
promos = call("GET", "/api/v1/food/promotions")
welcome = next((p for p in promos if p.get("code") == "WELCOME10"), None)
p_cart = dict(cart, fulfillmentType="PICKUP")
p_quote = call("POST", "/api/v1/food/cart/quote", p_cart, token=token)
assert p_quote["deliveryFeeMinor"] == 0 and p_quote["fulfillmentType"] == "PICKUP", p_quote
call("POST", "/api/v1/food/cart/quote", dict(p_cart, promoCode="NO-SUCH-CODE"), token=token, expect=422)
if welcome:
    d_quote = call("POST", "/api/v1/food/cart/quote", dict(p_cart, promoCode="welcome10"), token=token, expect=[200, 422])
    if d_quote and "discountMinor" in d_quote and d_quote.get("promoCode"):
        assert d_quote["discountMinor"] == d_quote["subtotalMinor"] // 10, d_quote
        assert d_quote["totalMinor"] == d_quote["subtotalMinor"] - d_quote["discountMinor"], d_quote
pickup_req = dict(p_cart, paymentMethod="CASH_ON_DELIVERY", expectedTotalMinor=p_quote["totalMinor"])
pickup = call("POST", "/api/v1/food/orders", pickup_req, token=token,
              headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=201)
assert pickup["fulfillmentType"] == "PICKUP" and pickup["deliveryFeeMinor"] == 0 and pickup["addressLabel"] == "Самовывоз", pickup
call("POST", "/api/v1/food/orders", dict(pickup_req, expectedTotalMinor=1), token=token,
     headers={"Idempotency-Key": "smoke-" + uuid.uuid4().hex}, expect=409)
call("POST", "/api/v1/food/orders/" + pickup["id"] + "/review", {"rating": 5}, token=token, expect=409)  # not delivered yet
call("POST", "/api/v1/food/orders/" + pickup["id"] + "/cancel", token=token, expect=[200, 409])
call("GET", "/api/v1/food/favorites", expect=401)
call("PUT", "/api/v1/food/favorites/" + pick["id"], token=token)
favs = call("GET", "/api/v1/food/favorites", token=token)
assert any(r["id"] == pick["id"] for r in favs), "favorite not stored"
call("DELETE", "/api/v1/food/favorites/" + pick["id"], token=token)
reviews = call("GET", "/api/v1/food/restaurants/" + pick["id"] + "/reviews")
assert "count" in reviews and "distribution" in reviews, reviews
call("GET", "/api/v1/admin/food/summary", token=token, expect=403)

# Re-open: the app restores its session from the stored refresh token and still sees the persisted order.
token2 = call("POST", "/api/v1/auth/token/refresh", {"refreshToken": session["refreshToken"]})["accessToken"]
history2 = call("GET", "/api/v1/food/orders", token=token2)
assert any(o["id"] == order["id"] for o in history2), "order not restored after session refresh"

if "--keep" not in sys.argv:
    cancelled = call("POST", "/api/v1/food/orders/" + order["id"] + "/cancel", token=token2, expect=[200, 409])
    print("cancelled" if cancelled and cancelled.get("status") == "CANCELLED" else "kept (already accepted)")
print("SMOKE OK")
