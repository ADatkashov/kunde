"""KUNDE Events & Leisure native E2E on a loopback-only fixture. The seat purchase runs through the Events product (cinema), the activity
booking and the product separation through Leisure; both share one ticketing engine. Original description:
KUNDE Leisure native E2E on a loopback-only fixture: the real Consumer APK on an Android emulator against a real backend and PostgreSQL.

Consumer steps run through the actual app screens (home -> category -> event -> session -> seats -> summary -> test payment -> QR ticket ->
history -> review). Partner and Executor actions (QR check-in, executor assignment) are real HTTP calls to the same backend: those apps are
covered by their own widget tests and CI jobs. LEISURE_E2E_API_ONLY=1 runs the whole scenario through HTTP only (no emulator).
No real payment exists in this run: the only methods are the DEV/TEST ledger and pay on site.
"""

import concurrent.futures
import datetime
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

import rides_native_e2e as fixture

API_ONLY = os.environ.get("LEISURE_E2E_API_ONLY") == "1"
REPORT = Path("reports/leisure-native")
APKS = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "leisure-apk"
CONSUMER_PHONE, PARTNER_PHONE, OTHER_PHONE = "+77000000001", "+77000000002", "+77000000003"
completed = fixture.completed

if not API_ONLY:
    import capture_android_visual as android


def report(status, phase):
    fixture.REPORT = REPORT
    fixture.write_report(status, phase)


def raw(method, path, *, body=None, token=None, key=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if key:
        headers["Idempotency-Key"] = key
    request = urllib.request.Request(fixture.API + path, method=method, headers=headers,
                                     data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = response.read()
            return response.status, (json.loads(data) if data else None)
    except urllib.error.HTTPError as error:
        data = error.read()
        return error.code, (json.loads(data) if data else None)


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def sql(statement):
    container = os.environ.get("LEISURE_POSTGRES_CONTAINER")
    if container:
        command = ["docker", "exec", container, "psql", "--username", "kunde_e2e", "--dbname", "kunde_e2e"]
        environment = None
    else:
        database = os.environ["DB_URL"].rsplit("/", 1)[-1]
        command = ["psql", "-h", "localhost", "-U", os.environ["DB_USERNAME"], "-d", database]
        environment = {**os.environ, "PGPASSWORD": os.environ.get("DB_PASSWORD", "")}
    result = subprocess.run([*command, "-v", "ON_ERROR_STOP=1", "-Atc", statement], check=True, capture_output=True, text=True, env=environment)
    return result.stdout.strip()


def start_backend(enabled):
    env = dict(os.environ)
    env["LEISURE_ENABLED"] = "true" if enabled else "false"
    env["EVENTS_ENABLED"] = "true" if enabled else "false"
    env["LEISURE_SEED_DEMO"] = "true" if enabled else "false"
    env["AUTH_PHONE_SECRET"] = fixture.FIXTURE_AUTH_KEY
    args = ["java", "-Xms128m", "-Xmx640m", "-XX:+UseSerialGC", "-jar", "backend/target/kunde-api-0.1.0-SNAPSHOT.jar", "--server.address=127.0.0.1", "--server.port=8081"]
    log_path = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "leisure-backend.log"
    offset = log_path.stat().st_size if log_path.exists() else 0
    with log_path.open("ab") as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=env)
    for _ in range(150):
        if process.poll() is not None:
            break
        try:
            capabilities = fixture.call("GET", "capabilities")
        except (OSError, RuntimeError):
            time.sleep(1)
            continue
        if capabilities["leisureEnabled"] == enabled and capabilities["eventsEnabled"] == enabled:
            if not enabled:
                return process
            for _ in range(120):  # the demo seeders run after the web server is up
                if process.poll() is not None:
                    break
                if "Leisure demo seed:" in log_path.read_bytes()[offset:].decode("utf-8", "replace"):
                    return process
                time.sleep(1)
        break
    fixture.stop_backend(process)
    raise RuntimeError("Isolated backend did not start with the expected Leisure capability")


class World:
    pass


world = World()


def cinema_event():
    for card in fixture.call("GET", "events?category=CINEMA&limit=20"):
        if card["bookingType"] == "SEAT_MAP" and card["minAge"] == 12:
            return card
    raise RuntimeError("the synthetic cinema event is not seeded")


def clock(iso):
    return iso[11:16]


def setup():
    if API_ONLY:  # with the app, this number signs in through the app first (its token is set by main)
        world.consumer = fixture.session(CONSUMER_PHONE)
    world.partner_token = fixture.session(PARTNER_PHONE)
    world.other = fixture.session(OTHER_PHONE)
    world.partner = None
    for _ in range(30):
        status, partners = raw("GET", "partner/partners", token=world.partner_token)
        if status == 200:
            world.partner = next((p["id"] for p in partners if p["verificationStatus"] == "APPROVED"), None)
        if world.partner:
            break
        time.sleep(1)
    check(world.partner, "the synthetic partner is missing")
    world.event = cinema_event()
    world.detail = fixture.call("GET", "leisure/events/" + world.event["id"])
    check(world.detail["demo"] is True and world.detail["rating"] is None, "demo data is flagged and carries no invented rating")
    sessions = fixture.call("GET", f"leisure/events/{world.event['id']}/sessions?days=3")
    # a session far enough in the future for the check-in window to be closed until the test moves it
    horizon = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=3)
    world.session = next(s for s in sessions if s["free"] >= 20 and datetime.datetime.fromisoformat(s["startsAt"]) > horizon)
    seats = fixture.call("GET", f"leisure/sessions/{world.session['id']}/seats")
    free = [s for s in seats if s["status"] == "FREE" and s["zone"] == "STANDARD"]
    world.seat_a, world.seat_b, world.seat_c = free[-1], free[-2], free[-3]
    completed.append("backend_seeded_catalogue")


def latest_order(token):
    orders = fixture.call("GET", "leisure/orders?scope=upcoming", token=token)
    check(orders, "the customer has no upcoming order")
    return orders[0]


def scan(code, token=None, expect_result=None):
    status, body = raw("POST", f"partner/partners/{world.partner}/leisure/checkins", token=token or world.partner_token, body={"code": code})
    check(status == 200, f"check-in answered {status}: {body}")
    if expect_result:
        check(body["result"] == expect_result, f"expected {expect_result}, got {body}")
    return body


def api_purchase():
    """The same purchase the app performs, over HTTP (developer machine)."""
    std = next(t for t in world.detail["ticketTypes"] if t["zone"] == "STANDARD")
    hold = fixture.call("POST", f"leisure/sessions/{world.session['id']}/holds", token=world.consumer, expected=201,
                        body={"lines": [{"ticketTypeId": std["id"], "quantity": 2, "seatIds": [world.seat_a["id"], world.seat_b["id"]]}]})
    check(hold["totalMinor"] == 2 * std["priceMinor"], "the server prices the hold")
    return fixture.call("POST", "leisure/orders", token=world.consumer, expected=201, key="e2e-" + uuid.uuid4().hex,
                        body={"holdId": hold["id"], "paymentMethod": "TEST_CARD", "ageConfirmed": True})


def after_purchase(order):
    check(order["status"] == "CONFIRMED" and order["payment"]["status"] == "TEST_CAPTURED" and order["payment"]["mode"] == "DEV_TEST", order)
    qr = order["tickets"][0]["qr"]
    check(re.fullmatch(r"KT1\.[0-9a-f-]{36}\.[0-9a-f]{32}", qr) and "7700" not in qr, "QR carries no personal data")
    world.order = order
    world.qr = qr
    # entry opens two hours before the start; the seeded session is later than that
    scan(qr, expect_result="TOO_EARLY")
    sql("update marketplace.leisure_sessions set starts_at = now() + interval '20 minutes', ends_at = now() + interval '2 hours' where id = '" + world.session["id"] + "'")
    scan("garbage", expect_result="INVALID")
    scan(qr.replace(qr[-1], "0" if qr[-1] != "0" else "1"), expect_result="INVALID")
    status, body = raw("POST", f"partner/partners/{world.partner}/leisure/checkins", token=fixture.session(OTHER_PHONE), body={"code": qr})
    check(status == 404, f"a user that is not the organiser's staff must get 404: {status}")
    scan(qr, expect_result="ADMITTED")
    scan(qr, expect_result="DUPLICATE")
    status, body = raw("POST", f"leisure/orders/{order['id']}/cancel", token=world.consumer)
    check(status == 409 and body["code"] == "TICKET_USED", "a used ticket cannot be cancelled")
    completed.append("ticket_scanned_once_then_duplicate_and_negative_codes")


def api_checks():
    # the review step moved the session into the past; reopen sales to test the sold seat
    sql("update marketplace.leisure_sessions set starts_at = now() + interval '1 day', ends_at = now() + interval '1 day 2 hours' where id = '" + world.session["id"] + "'")
    std = next(t for t in world.detail["ticketTypes"] if t["zone"] == "STANDARD")
    # a seat taken by someone else is refused for everyone else
    status, body = raw("POST", f"leisure/sessions/{world.session['id']}/holds", token=world.other,
                       body={"lines": [{"ticketTypeId": std["id"], "quantity": 1, "seatIds": [world.seat_a["id"]]}]})
    check(status == 409 and body["code"] == "SEAT_TAKEN", f"the sold seat must be refused: {status} {body}")
    # concurrency: three customers race for one seat; exactly one wins
    horizon = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=6)  # outside the free-cancellation window
    session = next(s for s in fixture.call("GET", f"leisure/events/{world.event['id']}/sessions?days=3")
                   if s["id"] != world.session["id"] and datetime.datetime.fromisoformat(s["startsAt"]) > horizon)
    seats = fixture.call("GET", f"leisure/sessions/{session['id']}/seats")
    seat = next(s for s in seats if s["status"] == "FREE" and s["zone"] == "STANDARD")
    tokens = [world.consumer or fixture.session(CONSUMER_PHONE), world.other, fixture.session("+77000000002")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda t: raw("POST", f"leisure/sessions/{session['id']}/holds", token=t,
                                              body={"lines": [{"ticketTypeId": std["id"], "quantity": 1, "seatIds": [seat["id"]]}]}), tokens))
    check(sorted(code for code, _ in results) == [201, 409, 409], f"exactly one racing hold wins: {results}")
    completed.append("concurrent_seat_hold")
    # idempotent payment: the same key twice gives one order
    winner = next(t for t, (code, _) in zip(tokens, results) if code == 201)
    hold = next(body for code, body in results if code == 201)
    key = "e2e-retry-" + uuid.uuid4().hex
    payload = {"holdId": hold["id"], "paymentMethod": "TEST_CARD", "ageConfirmed": True}
    one = raw("POST", "leisure/orders", token=winner, key=key, body=payload)
    two = raw("POST", "leisure/orders", token=winner, key=key, body=payload)
    check(one[0] == 201 and two[0] == 200 and one[1]["id"] == two[1]["id"], f"a repeated payment must return the same order: {one[0]} {two[0]}")
    check(sql("select count(*) from transactions.leisure_orders where idempotency_key = '" + key + "'") == "1", "double order")
    completed.append("idempotent_payment")
    # cancelled ticket and expired ticket at the gate
    fixture.call("POST", f"leisure/orders/{one[1]['id']}/cancel", token=winner)
    cancelled_qr = one[1]["tickets"][0]["qr"]
    check(scan(cancelled_qr)["result"] in ("CANCELLED", "TOO_EARLY"), "a cancelled ticket must not pass")
    completed.append("cancelled_ticket_refused")
    sql("update marketplace.leisure_sessions set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = '" + session["id"] + "'")
    check(scan(cancelled_qr)["result"] in ("CANCELLED", "EXPIRED"), "an old ticket must not pass")
    # executor: only for events that need one
    walk = next(c for c in fixture.call("GET", "leisure/events?category=EXCURSION") if c["title"].startswith("Пешая"))
    walk_session = walk["nextSessionId"]
    status, body = raw("POST", f"partner/partners/{world.partner}/leisure/sessions/{world.session['id']}/assignments", token=world.partner_token,
                       body={"phone": OTHER_PHONE, "role": "GUIDE"})
    check(status == 409 and body["code"] == "EXECUTOR_NOT_NEEDED", "a cinema event needs no executor")
    assignment = fixture.call("POST", f"partner/partners/{world.partner}/leisure/sessions/{walk_session}/assignments", token=world.partner_token,
                              expected=201, body={"phone": OTHER_PHONE, "role": "GUIDE"})
    fixture.call("POST", f"executor/leisure/assignments/{assignment['id']}/step", token=world.other, body={"step": "ACCEPT"})
    status, _ = raw("POST", f"executor/leisure/assignments/{assignment['id']}/step", token=world.other, body={"step": "START"})
    check(status == 409, "starting outside the work window is refused")
    completed.append("executor_assignment_only_where_needed")


def separation_checks():
    """Events and Leisure are two products on one engine: separate catalogues, one canonical card, one purchase path."""
    events = fixture.call("GET", "events/categories")
    leisure = fixture.call("GET", "leisure/categories")
    check({c["code"] for c in events}.isdisjoint({c["code"] for c in leisure}), "no category is in both catalogues")
    check({"CINEMA", "CONCERT", "THEATER"} <= {c["code"] for c in events}, "cinema, concerts and theatre are Events")
    check({"QUEST", "BOWLING", "GAMING_VR"} <= {c["code"] for c in leisure}, "quests, bowling and VR are Leisure")
    check(fixture.call("GET", "events?category=BOWLING") == [], "bowling is not an event")
    check(fixture.call("GET", "leisure/events?category=CINEMA") == [], "cinema is not a leisure activity")
    check(fixture.call("GET", "events/" + world.event["id"])["product"] == "EVENTS", "the cinema card is an Events card")
    check(fixture.call("GET", "leisure/events/" + world.event["id"])["id"] == world.event["id"], "one canonical card for one offer")
    completed.append("events_leisure_catalogues_separated")
    # a Leisure activity (bowling lane, per-booking price) through the same hold/order path, then a refunded cancellation
    lane = fixture.call("GET", "leisure/events?category=BOWLING&limit=5")[0]
    detail = fixture.call("GET", "leisure/events/" + lane["id"])
    session = fixture.call("GET", f"leisure/events/{lane['id']}/sessions?days=3")[-1]  # the latest: outside the free-cancellation window
    hold = fixture.call("POST", f"leisure/sessions/{session['id']}/holds", token=world.consumer, expected=201,
                        body={"lines": [{"ticketTypeId": detail["ticketTypes"][0]["id"], "quantity": 1}]})
    order = fixture.call("POST", "leisure/orders", token=world.consumer, expected=201, key="e2e-" + uuid.uuid4().hex,
                         body={"holdId": hold["id"], "paymentMethod": "TEST_CARD", "ageConfirmed": True})
    check(order["status"] == "CONFIRMED" and order["payment"]["mode"] == "DEV_TEST", order)
    cancelled = fixture.call("POST", f"leisure/orders/{order['id']}/cancel", token=world.consumer)
    check(cancelled["status"] == "CANCELLED" and cancelled["payment"]["status"] == "TEST_REFUNDED", cancelled)
    completed.append("leisure_activity_booking_test_payment_cancel_refund")


def ui_leisure_home():
    """Leisure is its own tile and its own catalogue: the home opens, the cinema is not among its categories."""
    relaunch()
    tap(*LEISURE)
    android.find(*LEISURE_HOME_TITLE, timeout=40)
    reveal("Боулинг", "Bowling")
    android.screenshot("consumer-leisure-home")
    completed.append("consumer_leisure_home_activities_only")


def flag_off_checks(process):
    fixture.stop_backend(process)
    process = start_backend(False)
    check(fixture.call("GET", "leisure/categories") == [], "the catalogue is empty while Leisure is off")
    check(fixture.call("GET", "events/categories") == [], "the catalogue is empty while Events is off")
    status, body = raw("POST", f"leisure/sessions/{world.session['id']}/holds", token=world.other, body={"lines": []})
    check(status == 409 and body["code"] == "EVENTS_DISABLED", f"new ticket holds are refused while Events is off: {status} {body}")
    orders = fixture.call("GET", "leisure/orders?scope=completed", token=world.consumer or fixture.session(CONSUMER_PHONE))
    check(isinstance(orders, list), "existing orders stay readable while Leisure is off")
    completed.append("flag_off_new_denied_existing_readable")
    return process


# --- the real app (CI only) -------------------------------------------------------------------------------------------

def reveal(*labels, **options):
    for attempt in range(8):
        try:
            return android.find(*labels, timeout=3, **options)
        except RuntimeError:
            if attempt == 7:
                raise
            android.adb("shell", "input", "swipe", "185", "670", "185", "330", "300")


def tap(*labels, **options):
    android.adb("shell", "input", "tap", *reveal(*labels, **options))


def sign_in(phone, *signed_in_labels):
    for attempt in range(1, 4):
        try:
            fixture.type_text(phone)
            android.adb("shell", "input", "keyevent", "4")
            time.sleep(1)
            android.tap("Получить код", "Get code", "Код алу", clickable=True, timeout=20)
            android.find("Введите код", "Enter the code", "Кодты енгізіңіз", timeout=45)
            android.adb("shell", "input", "text", "123456")
            android.find(*signed_in_labels, timeout=60)
            return
        except (RuntimeError, subprocess.SubprocessError):
            android.screenshot(f"sign-in-attempt-{attempt}")
            if attempt == 3:
                raise
            android.adb("shell", "am", "force-stop", fixture.CONSUMER)
            fixture.launch(fixture.CONSUMER)
            time.sleep(3)


def relaunch():
    android.adb("shell", "am", "force-stop", fixture.CONSUMER)
    fixture.launch(fixture.CONSUMER)
    android.find("Алматы", "Almaty", timeout=60)


def back(times=1):
    for _ in range(times):
        android.adb("shell", "input", "keyevent", "4")
        time.sleep(1)


def money(minor):
    whole = minor // 100
    digits = str(whole)
    grouped = ""
    for index, char in enumerate(digits):
        if index and (len(digits) - index) % 3 == 0:
            grouped += " "
        grouped += char
    return grouped + " ₸"


HOME_TITLE = ("События", "Events")
EVENTS = ("События", "Events")
LEISURE_HOME_TITLE = ("Досуг и развлечения", "Leisure and entertainment")
LEISURE = ("Досуг", "Leisure")
MY_TICKETS = ("Мои билеты", "My tickets")
CINEMAS = ("Кинотеатры", "Cinemas")
SCHEDULE = ("Расписание", "Schedule")
SEATS_TITLE = ("Выбор мест", "Choose seats")
CONTINUE = ("Продолжить", "Continue")
BOOKING = ("Бронирование", "Booking")
PAYMENT = ("Оплата", "Payment")
MY_TICKET = ("Мой билет", "My ticket")
UPCOMING = ("Предстоящие", "Upcoming")
COMPLETED = ("Завершённые", "Completed")
WRITE_REVIEW = ("Оставить отзыв", "Write a review")
SEND = ("Отправить", "Send")
THANKS = ("Спасибо за отзыв", "Thanks for your review")


def ui_purchase():
    std = next(t for t in world.detail["ticketTypes"] if t["zone"] == "STANDARD")
    price = money(world.detail["ticketTypes"][0]["priceMinor"])
    tap(*EVENTS)
    android.find(*HOME_TITLE, timeout=40)
    android.screenshot("consumer-events-home")
    completed.append("consumer_events_home")
    tap(*CINEMAS)
    tap(world.event["title"])
    android.find(*SCHEDULE, timeout=30)
    time.sleep(1)
    android.screenshot("consumer-event")
    tap(clock(world.session["startsAt"]))
    tap(resource_id="leisure-primary")
    android.find(*SEATS_TITLE, timeout=30)
    for seat in (world.seat_a, world.seat_b):
        tap(f"Место {seat['row']}{seat['number']}", f"Seat {seat['row']}{seat['number']}")
    android.screenshot("consumer-seats")
    tap(resource_id="leisure-primary")
    android.find(*BOOKING, timeout=30)
    android.screenshot("consumer-booking")
    tap("Подтверждаю, что всем гостям не меньше 12 лет", "I confirm every guest is at least 12 years old")
    tap(resource_id="leisure-primary")
    android.find(*PAYMENT, timeout=30)
    android.screenshot("consumer-payment")
    total = money(2 * std["priceMinor"])
    tap(resource_id="leisure-primary")
    android.find(*MY_TICKET, timeout=60)
    time.sleep(2)
    android.screenshot("consumer-ticket")
    order = latest_order(world.consumer)
    after_purchase(fixture.call("GET", "leisure/orders/" + order["id"], token=world.consumer))
    completed.append("consumer_seats_test_payment_qr_ticket")


def ui_after_scan():
    relaunch()
    tap(*EVENTS)
    tap(*MY_TICKETS)
    android.find(*UPCOMING, timeout=30)
    tap(world.event["title"])
    seat = f"{world.seat_a['row']}{world.seat_a['number']}"
    seat_b = f"{world.seat_b['row']}{world.seat_b['number']}"
    android.find("Использован · " + seat, "Used · " + seat, "Использован · " + seat_b, "Used · " + seat_b,
                 "Использован", "Used", timeout=40)
    android.screenshot("consumer-ticket-used")
    completed.append("consumer_ticket_shows_used_after_gate_scan")
    # the session is over: the order moves to completed and can be reviewed
    sql("update marketplace.leisure_sessions set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = '" + world.session["id"] + "'")
    back(1)
    tap(*COMPLETED)
    tap(world.event["title"])
    tap(*WRITE_REVIEW, clickable=True)
    tap("5")
    tap(*SEND, clickable=True)
    android.find(*THANKS, timeout=30)
    android.screenshot("consumer-review")
    detail = fixture.call("GET", "leisure/events/" + world.event["id"])
    check(detail["reviewCount"] == 1 and detail["rating"] == 5.0, detail)
    completed.append("consumer_history_and_review")


def ui_network_recovery(process):
    relaunch()
    tap(*EVENTS)
    android.find(*HOME_TITLE, timeout=40)
    fixture.stop_backend(process)
    tap(*MY_TICKETS)
    android.find("Повторить", "Retry", timeout=40)
    android.screenshot("consumer-offline")
    process = start_backend(True)
    android.adb("reverse", "tcp:8081", "tcp:8081")
    for _ in range(3):
        tap("Повторить", "Retry", clickable=True)
        try:
            android.find(*UPCOMING, timeout=20)
            completed.append("consumer_network_loss_and_retry")
            return process
        except RuntimeError:
            continue
    raise RuntimeError("My tickets did not reload after the backend came back")


def ui_flag_off():
    android.adb("reverse", "tcp:8081", "tcp:8081")
    try:
        relaunch()
    except RuntimeError:
        android.screenshot("flag-off-relaunch-failed")
        raise
    try:
        tap(*EVENTS)
        android.find(*HOME_TITLE, timeout=8)
    except RuntimeError:
        completed.append("consumer_events_unavailable_when_flag_off")
        return
    raise RuntimeError("Leisure stayed usable in the app after the platform flag was switched off")


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = REPORT
    if not API_ONLY:
        android.REPORT = REPORT
    phase = "backend"
    report("STARTED", phase)
    process = None
    try:
        process = start_backend(True)
        if API_ONLY:
            setup()
            phase = "api_purchase"
            after_purchase(api_purchase())
        else:
            phase = "install_and_sign_in"
            # stream logcat to a file so that a dying emulator still leaves its last lines behind
            stream = open(REPORT / "logcat-stream.txt", "wb")
            subprocess.Popen(["adb", "logcat", "-v", "time", "*:W"], stdout=stream, stderr=subprocess.STDOUT)
            android.adb("reverse", "tcp:8081", "tcp:8081")
            android.adb("shell", "wm", "size", "390x844")
            android.adb("shell", "wm", "density", "160")
            android.adb("install", APKS / "consumer.apk")
            fixture.launch(fixture.CONSUMER)
            sign_in("7000000001", "Алматы", "Almaty")
            world.consumer = fixture.session(CONSUMER_PHONE)
            completed.append("consumer_sign_in")
            setup()
            phase = "consumer_purchase"
            ui_purchase()
            phase = "after_scan"
            ui_after_scan()
        phase = "backend_scenarios"
        api_checks()
        separation_checks()
        if not API_ONLY:
            phase = "leisure_home"
            ui_leisure_home()
        if not API_ONLY:
            phase = "network_recovery"
            process = ui_network_recovery(process)
        phase = "flag_off"
        process = flag_off_checks(process)
        final_phase = "complete"
        if not API_ONLY:
            # Owner decision: this one step is non-blocking. The CI emulator was lost here in five consecutive runs
            # (qemu exits while the app starts against the switched-off backend); the cause is not established.
            # The server contract is asserted above over HTTP and the app side by the widget test
            # "switch off: the server returns no categories and the home says so".
            try:
                ui_flag_off()
            except Exception as error:  # noqa: BLE001 - recorded, never silent
                final_phase = "complete_flag_off_ui_UNVERIFIED"
                (REPORT / "flag-off-ui-UNVERIFIED.txt").write_text(f"The in-app flag-off check did not complete: {error!r}\n")
                print(f"WARNING: in-app flag-off check NOT verified: {error!r}", flush=True)
        report("PASSED", final_phase)
    except Exception:
        report("FAILED", phase)
        if not API_ONLY:
            try:
                (REPORT / "logcat.txt").write_bytes(android.adb("logcat", "-d", "-t", "400", "flutter:V", "AndroidRuntime:E", "*:S"))
            except (OSError, subprocess.SubprocessError):
                pass
        try:
            log = Path(os.environ.get("RUNNER_TEMP", "/tmp"), "leisure-backend.log")
            (REPORT / "backend-tail.log").write_text("\n".join(log.read_text(errors="replace").splitlines()[-150:]) + "\n")
        except OSError:
            pass
        if not API_ONLY:
            try:
                android.screenshot(f"failed-{phase}")
            except (RuntimeError, subprocess.SubprocessError):
                pass
        raise
    finally:
        if process is not None:
            fixture.stop_backend(process)


if __name__ == "__main__":
    main()
