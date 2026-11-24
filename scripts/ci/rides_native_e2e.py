"""Run the Consumer and Executor APKs on a loopback-only Android CI fixture."""

import json
import os
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

import capture_android_visual as android

REPORT = Path("reports/rides-native")
APKS = Path(os.environ["RUNNER_TEMP"]) / "rides-apk"
CONSUMER = "com.example.kunde_mobile"
EXECUTOR = "com.kunde.executor"
API = "http://127.0.0.1:8081/api/v1/"


class Stages(list):
    """Completed stage names plus the seconds since the run began when each finished (emulator on a CI runner, not a device)."""

    def __init__(self):
        super().__init__()
        self.started = time.monotonic()
        self.seconds = {}

    def append(self, name):
        super().append(name)
        self.seconds[name] = round(time.monotonic() - self.started, 1)


completed = Stages()
FIXTURE_AUTH_KEY = secrets.token_urlsafe(48)


def write_report(status, phase):
    (REPORT / "status.json").write_text(json.dumps({
        "status": status,
        "phase": phase,
        "completed": completed,
        "secondsSinceStart": completed.seconds,
        "data": "synthetic",
        "paymentEnabled": False,
    }, indent=2) + "\n")


def call(method, path, *, body=None, token=None, expected=200, key=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if key:
        headers["Idempotency-Key"] = key
    req = urllib.request.Request(API + path, method=method, headers=headers,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as response:
        status, raw = response.code, response.read()
    if status != expected:
        raise RuntimeError(f"{method} {path}: expected {expected}, got {status}")
    return json.loads(raw) if raw else None


def start_backend(enabled):
    env = dict(os.environ)
    if not enabled:
        env["RIDES_ENABLED"] = "false"
        env["RIDES_SYNTHETIC_ROUTING_ENABLED"] = "false"
    env["AUTH_PHONE_SECRET"] = FIXTURE_AUTH_KEY
    args = [
        "java", "-jar", "backend/build/libs/kunde-api-0.1.0-SNAPSHOT.jar",
        "--server.address=127.0.0.1", "--server.port=8081",
    ]
    tariff = {
        "version": "synthetic-e2e-1", "base-kzt": 100, "per-kilometer-kzt": 100,
        "per-minute-kzt": 10, "minimum-kzt": 300, "fixed-fee-kzt": 0,
    }
    args.extend(f"--app.rides.pricing.tariffs.economy.{key}={value}" for key, value in tariff.items())
    with Path(os.environ["RUNNER_TEMP"], "rides-backend.log").open("wb") as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=env)
    for _ in range(90):
        if process.poll() is not None:
            break
        try:
            caps = call("GET", "capabilities")
        except (OSError, RuntimeError):
            time.sleep(1)
            continue
        if caps["ridesEnabled"] == enabled:
            return process
        break
    stop_backend(process)
    raise RuntimeError("Isolated backend did not start with the expected Rides capability")


def stop_backend(process):
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def session(phone):
    call("POST", "auth/otp/request", body={"phone": phone}, expected=202)
    return call("POST", "auth/otp/verify", body={"phone": phone, "code": "123456"})["accessToken"]


def seed_driver():
    token = session("+77000000002")
    driver = call("POST", "executor/rides/profile", body={"displayName": "Synthetic driver"}, token=token)
    call("POST", "executor/rides/vehicle", body={
        "description": "Synthetic vehicle", "plate": "UITEST1", "rideClass": "ECONOMY",
    }, token=token)
    driver_id = str(uuid.UUID(driver["userId"]))
    # This fixture precondition is limited to the isolated Postgres service created in CI.
    subprocess.run([
        "docker", "exec", os.environ["RIDES_POSTGRES_CONTAINER"],
        "psql", "--username", "kunde_e2e", "--dbname", "kunde_e2e",
        "-v", "ON_ERROR_STOP=1", "-c",
        f"update transactions.ride_drivers set status = 'APPROVED' where user_id = '{driver_id}'; "
        f"update transactions.ride_vehicles set status = 'APPROVED' where driver_id = '{driver_id}';",
    ], check=True, stdout=subprocess.DEVNULL)


def launch(package):
    android.PACKAGE = package
    android.adb("shell", "am", "start", "-W", "-n", f"{package}/com.example.kunde_mobile.MainActivity")


def type_text(value):
    android.tap(node_class="android.widget.EditText")
    android.adb("shell", "input", "text", value)


def login(phone, *signed_in_labels):
    type_text(phone)
    android.adb("shell", "input", "keyevent", "4")
    android.tap("Получить код", "Get code", "Код алу")
    android.find("Введите код", "Enter the code", "Кодты енгізіңіз", timeout=60)
    android.adb("shell", "input", "text", "123456")
    android.find(*signed_in_labels, timeout=60)


def open_rides():
    for _ in range(4):
        try:
            android.tap("Поездки", "Rides", "Сапарлар", timeout=5)
            # Rides opens on the category hub (RidesHubScreen); city rides is the only category with a backend contract.
            android.tap("По городу", "City rides", "Қала бойынша", timeout=15)
            android.find("Откуда", "Pickup", "Қайдан", timeout=15)
            return
        except RuntimeError:
            android.adb("shell", "input", "swipe", "190", "680", "190", "325", "300")
    raise RuntimeError("Rides category did not open")


def pick_address(label, address):
    android.tap(*label)
    type_text("Synthetic")
    android.adb("shell", "input", "keyevent", "66")
    android.tap(address)


def create_ride():
    android.tap("Узнать стоимость", "Get fare", "Бағасын білу")
    android.find("Тестовый маршрут", "Test route", "Сынақ бағыты")
    android.tap("Заказать поездку", "Request ride", "Сапарға тапсырыс беру")
    android.find("Ищем водителя...", "Finding a driver...", "Жүргізуші ізделуде...", timeout=45)


def find_completed():
    android.find(
        "Поездка завершена", "Ride complete", "Сапар аяқталды",
        "Тестовый маршрут · Поездка завершена",
        "Test route · Ride complete",
        "Сынақ бағыты · Сапар аяқталды",
    )


def open_history(back_first=False):
    """Reach the History tab from wherever the previous step left the app (Rides is now a hub plus a city screen)."""
    if back_first:
        android.adb("shell", "input", "keyevent", "4")
    for _ in range(5):
        try:
            android.tap("История", "History", "Тарих", timeout=4)
            return
        except RuntimeError:
            android.adb("shell", "input", "keyevent", "4")
    raise RuntimeError("History did not open")


def capture_failure():
    """Keep what the screen showed when a step failed: a failed run must be diagnosable from its artifact alone."""
    try:
        android.screenshot("failure")
        android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-failure.xml")
        (android.REPORT / "failure-ui.xml").write_bytes(android.adb("exec-out", "cat", "/sdcard/kunde-failure.xml"))
    except Exception as error:  # diagnostics must never mask the original failure
        print(f"could not capture failure state: {error}")


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    android.REPORT = REPORT
    phase = "backend"
    write_report("STARTED", phase)
    process = None
    try:
        process = start_backend(True)
        seed_driver()
        phase = "install_and_sign_in"
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")
        android.adb("install", APKS / "consumer.apk")
        android.adb("install", APKS / "executor.apk")
        for permission in ("ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION"):
            android.adb("shell", "pm", "grant", EXECUTOR, f"android.permission.{permission}")
        android.adb("emu", "geo", "fix", "76.92", "43.24")
        launch(EXECUTOR)
        login("7000000002", "На линии", "Online", "Желіде")
        # The driver screen shows a Switch (#243); tap it only once it is enabled (it is disabled while the screen loads).
        android.tap("На линии", "Online", "Желіде", node_class="android.widget.Switch", enabled=True, anchor="right")
        for _ in range(3):
            android.adb("emu", "geo", "fix", "76.92", "43.24")
            time.sleep(2)
        completed.append("executor_identity_and_online")

        launch(CONSUMER)
        login("7000000001", "Алматы", "Almaty")
        phase = "consumer_request"
        open_rides()
        pick_address(("Откуда", "Pickup", "Қайдан"), "[TEST] Synthetic pickup")
        pick_address(("Куда", "Destination", "Қайда"), "[TEST] Synthetic destination")
        create_ride()
        completed.append("consumer_request")

        phase = "assignment"
        launch(EXECUTOR)
        android.tap("Принять", "Accept", "Қабылдау")
        android.find("Выехать", "Depart", "Жолға шығу")
        completed.append("executor_accept")
        launch(CONSUMER)
        android.find("Водитель назначен", "Driver assigned", "Жүргізуші тағайындалды")
        android.find("Местоположение водителя", "Driver location", "Жүргізушінің орналасуы")
        android.find("Synthetic driver")
        android.find("Synthetic vehicle · UITEST1")
        android.screenshot("consumer-assigned")
        completed.append("consumer_driver_position")

        phase = "complete"
        launch(EXECUTOR)
        # Trip actions are disabled while the driver screen reloads; tap each one only when enabled and wait for the next step.
        android.tap("Выехать", "Depart", "Жолға шығу", enabled=True)
        android.tap("Я на месте", "I have arrived", "Келдім", enabled=True)
        android.tap("Начать поездку", "Start ride", "Сапарды бастау", enabled=True)
        android.find("Завершить", "Complete", "Аяқтау", enabled=True, timeout=60)
        android.tap("Завершить", "Complete", "Аяқтау", enabled=True)
        find_completed()
        android.screenshot("executor-history")
        completed.append("executor_arrival_start_complete_history")

        launch(CONSUMER)
        android.find("Поездка завершена!", "Ride complete!", "Сапар аяқталды!", timeout=60)
        android.screenshot("consumer-completed")
        completed.append("consumer_trip_completed_screen")
        android.tap("Оценка: 5 из 5", "Rating: 5 of 5", "Баға: 5-тен 5")
        android.tap("Готово", "Done", "Дайын", clickable=True)
        rides_now = call("GET", "rides", token=session("+77000000001"))
        assert rides_now[0]["status"] == "COMPLETED" and rides_now[0]["rating"]["stars"] == 5, "Rating from the UI was not stored"
        completed.append("consumer_rating_stored_in_backend")
        open_history()
        find_completed()
        android.screenshot("consumer-history")
        completed.append("consumer_history")

        phase = "network_retry_and_cancellation"
        android.adb("shell", "input", "keyevent", "4")
        stop_backend(process)
        open_history()
        android.find("Повторить", "Retry", "Қайталау", timeout=30)
        process = start_backend(True)
        android.tap("Повторить", "Retry", "Қайталау")
        find_completed()
        completed.append("consumer_network_retry")
        android.adb("shell", "input", "keyevent", "4")  # History -> the city screen, which keeps both chosen addresses
        create_ride()
        android.tap("Отменить поездку", "Cancel ride", "Сапардан бас тарту")
        android.tap("Отменить поездку", "Cancel ride", "Сапардан бас тарту", clickable=True)
        android.find("Поездка отменена", "Ride cancelled", "Сапар тоқтатылды")
        completed.append("consumer_cancellation")

        phase = "repeat_and_feature_flag"
        token = session("+77000000001")
        quote = call("POST", "rides/quotes", body={
            "rideClass": "ECONOMY", "pickup": {"latitude": 43.24, "longitude": 76.92},
            "destination": {"latitude": 43.25, "longitude": 76.94},
        }, token=token, expected=201)
        key = str(uuid.uuid4())
        body = {"quoteId": quote["id"]}
        first = call("POST", "rides", body=body, token=token, key=key, expected=201)
        replay = call("POST", "rides", body=body, token=token, key=key)
        assert first["id"] == replay["id"], "Repeat request created a different ride"
        completed.append("backend_idempotent_repeat")
        ride_id = first["id"]
        driver = session("+77000000002")
        call("PUT", "executor/rides/location", body={"latitude": 43.24, "longitude": 76.92},
             token=driver, expected=204)
        call("POST", f"rides/{ride_id}/dispatch", token=token)
        offers = call("GET", "executor/rides/offers", token=driver)
        offer = next(offer for offer in offers if offer["rideId"] == ride_id)
        call("POST", f"executor/rides/offers/{offer['id']}/response", body={"accept": True},
             token=driver, expected=204)
        progress = f"executor/rides/trips/{ride_id}/progress"
        for step in ("DEPART", "ARRIVE", "START"):
            call("POST", progress, body={"step": step}, token=driver, expected=204)
        stop_backend(process)
        process = start_backend(False)
        call("POST", "rides/quotes", body={
            "rideClass": "ECONOMY", "pickup": {"latitude": 43.24, "longitude": 76.92},
            "destination": {"latitude": 43.25, "longitude": 76.94},
        }, token=token, expected=404)
        completed.append("backend_feature_flag_off")
        assert call("GET", f"rides/{ride_id}", token=token)["status"] == "IN_PROGRESS"
        call("POST", progress, body={"step": "COMPLETE"}, token=driver, expected=204)
        assert call("GET", f"rides/{ride_id}", token=token)["status"] == "COMPLETED"
        completed.append("backend_active_ride_completes_with_flag_off")
        write_report("PASSED", phase)
    except Exception:
        write_report("FAILED", phase)
        capture_failure()
        raise
    finally:
        if process is not None and process.poll() is None:
            stop_backend(process)
        try:
            android.adb("shell", "rm", "-f", "/sdcard/kunde-visual.xml")
        except subprocess.SubprocessError:
            pass


if __name__ == "__main__":
    main()
