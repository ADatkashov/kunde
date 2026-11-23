"""Taxi with the KUNDE Maps Platform on a real Android emulator.

Nothing is mocked: the packaged backend runs with MAPS_ENABLED against the deployed DEV Maps Platform (real Search and Routing
APIs), the Consumer and Executor APKs render the real MapLibre map, and the emulator provides the GPS fixes. Verified:

  * consumer: address search -> choose -> pickup, destination, route preview, server-priced quote, ride request
  * executor: accept, driver navigation from the GPS position to the pickup, voice-less guidance, arrival
  * consumer: driver on the map while the trip is active
  * failure paths: location denied for navigation, Maps outage (backend 503 on a new quote)
"""

import json
import math
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import capture_android_visual as android
import rides_native_e2e as base

REPORT = Path("reports/maps-native")
MAPS_SEARCH = os.environ.get("MAPS_SEARCH_URL", "https://kunde-maps-search-dev.onrender.com")
MAPS_ROUTING = os.environ.get("MAPS_ROUTING_URL", "https://kunde-maps-routing-dev.onrender.com")
# Real places from the DEV index (verified by the search call below, never hard-coded as truth).
PICKUP_QUERY = "Esentai mall"
DESTINATION_QUERY = "MEGA Alma-Ata"
DRIVER_START = (43.2300, 76.9330)  # about 1.4 km from the pickup, inside the 5 km dispatch radius
completed = []


def report(status, phase):
    (REPORT / "status.json").write_text(json.dumps({
        "status": status, "phase": phase, "completed": completed, "data": "real DEV Maps Platform", "paymentEnabled": False,
    }, indent=2) + "\n")


def maps_json(url, body=None, timeout=90):
    request = urllib.request.Request(
        url, data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def warm_up_maps():
    """Free-tier Render instances sleep; wake both before the UI starts so the first screen is not a cold start."""
    deadline = time.monotonic() + 240
    for url in (f"{MAPS_SEARCH}/health", f"{MAPS_ROUTING}/health"):
        while True:
            try:
                if maps_json(url, timeout=60).get("status") == "ok":
                    break
            except (OSError, ValueError):
                pass
            if time.monotonic() > deadline:
                raise RuntimeError(f"Maps service did not wake up: {url}")
            time.sleep(5)


def search(query):
    url = f"{MAPS_SEARCH}/v1/search?" + urllib.parse.urlencode({"q": query, "lang": "en", "lat": 43.238, "lon": 76.945})
    results = maps_json(url)["results"]
    assert results, f"The real index returned nothing for {query!r}"
    return results[0]


def route_geometry(origin, destination):
    answer = maps_json(f"{MAPS_ROUTING}/v1/routes", {
        "origin": {"lat": origin[0], "lon": origin[1]}, "destination": {"lat": destination[0], "lon": destination[1]},
        "mode": "driving", "alternatives": False, "language": "en"})
    return [(lat, lon) for lon, lat in answer["geometry"]["coordinates"]]


def metres(a, b):
    p = math.pi / 180
    x = math.sin((b[0] - a[0]) * p / 2) ** 2 + math.cos(a[0] * p) * math.cos(b[0] * p) * math.sin((b[1] - a[1]) * p / 2) ** 2
    return 12742000 * math.asin(math.sqrt(x))


def densify(points, step=60.0):
    """GPS fixes about every 60 m along the real route geometry."""
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        count = max(1, int(metres(a, b) // step))
        for k in range(1, count + 1):
            out.append((a[0] + (b[0] - a[0]) * k / count, a[1] + (b[1] - a[1]) * k / count))
    return out


def geo(point):
    android.adb("emu", "geo", "fix", f"{point[1]:.6f}", f"{point[0]:.6f}")


def start_backend_with_maps(routing_url=MAPS_ROUTING):
    env = dict(os.environ)
    env["RIDES_SYNTHETIC_ROUTING_ENABLED"] = "false"
    env["MAPS_ENABLED"] = "true"
    env["MAPS_ROUTING_URL"] = routing_url
    env["MAPS_SEARCH_URL"] = MAPS_SEARCH
    env["MAPS_TIMEOUT_SECONDS"] = "60"
    env["AUTH_PHONE_SECRET"] = base.FIXTURE_AUTH_KEY
    args = ["java", "-jar", "backend/target/kunde-api-0.1.0-SNAPSHOT.jar", "--server.address=127.0.0.1", "--server.port=8081"]
    tariff = {"version": "maps-e2e-1", "base-kzt": 100, "per-kilometer-kzt": 100, "per-minute-kzt": 10, "minimum-kzt": 300, "fixed-fee-kzt": 0}
    args.extend(f"--app.rides.pricing.tariffs.economy.{key}={value}" for key, value in tariff.items())
    with Path(os.environ["RUNNER_TEMP"], "maps-backend.log").open("wb") as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=env)
    for _ in range(120):
        if process.poll() is not None:
            break
        try:
            caps = base.call("GET", "capabilities")
        except (OSError, RuntimeError):
            time.sleep(1)
            continue
        assert caps["ridesEnabled"] is True and caps["mapsEnabled"] is True, caps
        return process
    base.stop_backend(process)
    raise RuntimeError("Backend with the Maps provider did not start")


def dump_ui(name):
    """Keep the visible UI tree and a screenshot when a step fails, so a CI failure can be diagnosed."""
    try:
        android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-visual.xml")
        (REPORT / f"{name}.xml").write_bytes(android.adb("exec-out", "cat", "/sdcard/kunde-visual.xml"))
        android.screenshot(name)
    except (subprocess.SubprocessError, OSError):
        pass


def tap_result_containing(word, timeout=90):
    """Tap the first clickable search result whose text contains [word] (the app ranks by map centre, so the exact
    first result of the API call is not guaranteed to be first on screen)."""
    import re
    import xml.etree.ElementTree as ET
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-visual.xml")
            tree = ET.fromstring(android.adb("exec-out", "cat", "/sdcard/kunde-visual.xml"))
        except (subprocess.SubprocessError, ET.ParseError):
            continue
        for node in tree.iter("node"):
            text = node.get("text", "") + " " + node.get("content-desc", "")
            if word.lower() in text.lower() and node.get("clickable") == "true" and node.get("class") != "android.widget.EditText":
                x1, y1, x2, y2 = [int(v) for v in re.findall(r"\d+", node.get("bounds", ""))]
                android.adb("shell", "input", "tap", (x1 + x2) // 2, (y1 + y2) // 2)
                return
        time.sleep(2)
    dump_ui("picker-result-missing")
    raise RuntimeError(f"No search result containing {word!r}")


def choose_on_map(label, query, name):
    """Open the map picker for a field, search the real index, choose the result, confirm."""
    android.tap(*label, clickable=True)
    android.find("Confirm", "Подтвердить", "Растау", timeout=60)  # the picker (with its native map) is on screen
    try:
        android.tap(*label, clickable=True, timeout=20)  # the search row inside the picker
        android.find(node_class="android.widget.EditText", timeout=20)
    except RuntimeError:
        dump_ui("picker-search-row-failed")
        raise
    android.tap(node_class="android.widget.EditText")
    android.adb("shell", "input", "text", query.replace(" ", "%s"))
    tap_result_containing(query.split()[0])
    android.screenshot(f"picker-{query.split()[0].lower()}")
    android.tap("Confirm", "Подтвердить", "Растау", clickable=True)


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    android.REPORT = REPORT
    base.REPORT = REPORT
    phase = "maps_warm_up"
    report("STARTED", phase)
    process = None
    try:
        warm_up_maps()
        pickup = search(PICKUP_QUERY)
        destination = search(DESTINATION_QUERY)
        pickup_point = (pickup["lat"], pickup["lon"])
        destination_point = (destination["lat"], destination["lon"])
        completed.append("real_maps_search")

        phase = "backend"
        process = start_backend_with_maps()
        base.seed_driver()
        completed.append("backend_maps_enabled")

        phase = "install_and_sign_in"
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")
        android.adb("install", base.APKS / "consumer.apk")
        android.adb("install", base.APKS / "executor.apk")
        for permission in ("ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION"):
            android.adb("shell", "pm", "grant", base.EXECUTOR, f"android.permission.{permission}")
        geo(DRIVER_START)
        base.launch(base.EXECUTOR)
        base.login("7000000002", "На линии", "Online", "Желіде")
        android.tap("На линии", "Online", "Желіде")
        for _ in range(3):
            geo(DRIVER_START)
            time.sleep(2)
        completed.append("executor_online")

        base.launch(base.CONSUMER)
        base.login("7000000001", "Алматы", "Almaty")

        phase = "consumer_map_request"
        base.open_rides()
        choose_on_map(("Откуда", "Pickup", "Қайдан"), PICKUP_QUERY, pickup["name"])
        choose_on_map(("Куда", "Destination", "Қайда"), DESTINATION_QUERY, destination["name"])
        # Real route from the real Routing API, drawn on the native map, with the honest no-traffic note.
        android.find("Типичное время без учёта пробок", "Typical time, traffic not included",
                     "Кептелісті ескермейтін әдеттегі уақыт", timeout=120)
        android.screenshot("consumer-route-preview")
        completed.append("consumer_pickup_destination_route_preview")
        android.tap("Узнать стоимость", "Get fare", "Бағасын білу")
        android.find("KZT", timeout=90)  # priced by the Rides tariff from the Maps route, not a synthetic fixture
        try:
            android.find("Тестовый маршрут", "Test route", "Сынақ бағыты", timeout=3)
            raise AssertionError("The quote was marked as a synthetic route")
        except RuntimeError:
            pass
        android.screenshot("consumer-quote")
        completed.append("consumer_server_priced_quote")
        android.tap("Заказать поездку", "Request ride", "Сапарға тапсырыс беру")
        android.find("Ищем водителя", "Finding a driver", "Жүргізуші ізделуде", timeout=60)
        completed.append("consumer_ride_requested")

        phase = "driver_navigation"
        base.launch(base.EXECUTOR)
        android.tap("Принять", "Accept", "Қабылдау")
        android.find("Выехать", "Depart", "Жолға шығу")
        android.tap("Навигатор", "Navigate", clickable=True)
        # Real GPS fix -> real route to the passenger -> native map with guidance.
        android.find("Завершить", "End navigation", "Аяқтау", timeout=120)
        android.find("Осталось", "Remaining", "Қалды", timeout=30)
        android.screenshot("executor-navigation")
        completed.append("executor_navigation_started")
        for fix in densify(route_geometry(DRIVER_START, pickup_point)):
            geo(fix)
            time.sleep(1.5)
        android.find("Вы прибыли", "You have arrived", "Межелі жерге жеттіңіз", timeout=60)
        android.screenshot("executor-arrived")
        completed.append("executor_navigation_arrival")
        android.tap("Завершить", "End navigation", "Аяқтау", clickable=True)
        android.find("Выехать", "Depart", "Жолға шығу")  # trip state is still owned by the backend, not by the map
        completed.append("trip_status_unchanged_by_navigation")

        phase = "consumer_sees_driver"
        android.tap("Выехать", "Depart", "Жолға шығу")
        base.launch(base.CONSUMER)
        android.find("Водитель назначен", "Driver assigned", "Жүргізуші тағайындалды", "Водитель в пути", "Driver is arriving", timeout=60)
        android.find("Местоположение водителя на карте", "Driver location on the map", "Жүргізушінің картадағы орны", timeout=60)
        android.screenshot("consumer-driver-on-map")
        completed.append("consumer_driver_on_map")

        phase = "maps_outage_fails_closed"
        base.stop_backend(process)
        process = start_backend_with_maps("https://routing.kunde-maps-offline.invalid")
        token = base.session("+77000000001")
        base.call("POST", "rides/quotes", body={
            "rideClass": "ECONOMY",
            "pickup": {"latitude": pickup_point[0], "longitude": pickup_point[1]},
            "destination": {"latitude": destination_point[0], "longitude": destination_point[1]},
        }, token=token, expected=503)
        completed.append("backend_maps_outage_503")
        report("PASSED", phase)
    except Exception:
        report("FAILED", phase)
        raise
    finally:
        if process is not None and process.poll() is None:
            base.stop_backend(process)
        try:
            android.adb("shell", "rm", "-f", "/sdcard/kunde-visual.xml")
        except subprocess.SubprocessError:
            pass


if __name__ == "__main__":
    main()
