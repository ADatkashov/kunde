#!/usr/bin/env python3
"""Verify Health on a synthetic LOCAL/DEV/TEST deployment over HTTP."""

import argparse
import datetime
import json
import urllib.error
import urllib.parse
import urllib.request
import uuid
from zoneinfo import ZoneInfo


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base")
    parser.add_argument("--phone", default="+77000000001")
    parser.add_argument("--method", choices=("TEST_CARD", "PAY_ON_SITE"), default="TEST_CARD")
    args = parser.parse_args()
    if not args.phone.startswith("+7700000"):
        parser.error("use an allowlisted synthetic number")

    def call(method, path, body=None, token=None, key=None, expected=200):
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if key:
            headers["Idempotency-Key"] = key
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        request = urllib.request.Request(
            args.base.rstrip("/") + "/api/v1/" + path, method=method,
            data=data, headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        if status != expected:
            raise RuntimeError(f"{method} {path.split('?')[0]}: HTTP {status}; expected {expected}")
        return json.loads(raw) if raw else None

    assert call("GET", "capabilities")["healthEnabled"] is True
    venues = call("GET", "booking/health/venues?direction=DOCTORS")
    assert venues and all(venue["synthetic"] for venue in venues)
    detail = call("GET", f"booking/venues/{venues[0]['id']}")
    service = next(service for service in detail["services"] if service["available"])
    master = next(master for master in detail["masters"] if service["id"] in master["serviceIds"])
    day = datetime.datetime.now(ZoneInfo("Asia/Almaty")).date() + datetime.timedelta(days=2)
    for _ in range(6):
        query = urllib.parse.urlencode({
            "venueId": venues[0]["id"], "serviceId": service["id"],
            "masterId": master["id"], "date": day.isoformat(),
        })
        slots = call("GET", "booking/slots?" + query)
        if len(slots) >= 3:
            break
        day += datetime.timedelta(days=1)
    else:
        raise RuntimeError("expected at least three free slots for a synthetic specialist")

    path = "booking/bookings"
    call("GET", path + "?healthOnly=true", expected=401)
    call("POST", "auth/otp/request", {"phone": args.phone}, expected=202)
    token = call("POST", "auth/otp/verify", {"phone": args.phone, "code": "123456"})["accessToken"]
    body = {
        "venueId": venues[0]["id"], "serviceId": service["id"], "masterId": master["id"],
        "startsAt": slots[0]["startsAt"], "expectedPriceMinor": service["priceMinor"],
        "paymentMethod": args.method, "acceptsTerms": True,
    }
    key = str(uuid.uuid4())
    call("POST", path, {**body, "expectedPriceMinor": body["expectedPriceMinor"] + 1},
         token, key, expected=409)
    booked = call("POST", path, body, token, key, expected=201)
    item = path + "/" + booked["id"]
    open_status = "TEST_HELD" if args.method == "TEST_CARD" else "PAY_ON_SITE"
    cancel_status = "TEST_VOIDED" if args.method == "TEST_CARD" else "PAY_ON_SITE"
    try:
        assert booked["paymentStatus"] == open_status
        assert call("POST", path, body, token, key)["id"] == booked["id"]
        assert any(row["id"] == booked["id"] for row in call("GET", path + "?healthOnly=true", token=token))
        move = {"expectedStartsAt": booked["startsAt"], "startsAt": slots[-1]["startsAt"]}
        moved = call("POST", item + "/reschedule", move, token)
        assert moved["startsAt"] == move["startsAt"] and moved["paymentStatus"] == open_status
        assert call("POST", item + "/reschedule", move, token)["startsAt"] == moved["startsAt"]
        assert call("POST", path, body, token, key)["id"] == booked["id"]
    finally:
        cancelled = call("POST", item + "/cancel", token=token)
        assert cancelled["status"] == "CANCELLED" and cancelled["paymentStatus"] == cancel_status
    print(f"Health {args.method} smoke passed: catalog, price, booking, replay, history, move, cancellation")


if __name__ == "__main__":
    main()
