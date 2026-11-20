"""KUNDE Auto E2E on a loopback-only fixture: the real Consumer APK on an Android emulator against a real backend and PostgreSQL.

Consumer steps run through the actual app screens. Partner and Executor actions are real HTTP calls to the same backend: the
Partner and Executor apps are covered by their own widget tests and CI jobs, not by this native run. Set AUTO_E2E_API_ONLY=1 to
run the same scenario through HTTP only (no emulator), which is how the backend half is checked on a developer machine.
No real payment exists anywhere in this run: the only payment method is the DEV/TEST ledger.
"""

import concurrent.futures
import datetime
import json
import os
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import rides_native_e2e as fixture

API_ONLY = os.environ.get("AUTO_E2E_API_ONLY") == "1"
REPORT = Path("reports/auto-native")
APKS = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "auto-apk"
CONSUMER_PHONE, PARTNER_PHONE, OTHER_PHONE, THIRD_PHONE, SPECIALIST_PHONE = (
    f"+7700000000{i}" for i in (1, 2, 3, 4, 5))
WASH, STO = "auto-demo-wash", "auto-demo-sto"
completed = fixture.completed

if not API_ONLY:
    import capture_android_visual as android


# --- plumbing -------------------------------------------------------------------------------------------------------

def report(status, phase):
    fixture.REPORT = REPORT
    fixture.write_report(status, phase)


def raw(method, path, *, body=None, token=None, key=None):
    """Return (status, json) without raising on an HTTP error."""
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


def expect(method, path, status, **options):
    got, body = raw(method, path, **options)
    check(got == status, f"{method} {path}: expected {status}, got {got}: {body}")
    return body


def sql(statement):
    container = os.environ.get("AUTO_POSTGRES_CONTAINER")
    if container:
        command = ["docker", "exec", container, "psql", "--username", "kunde_e2e", "--dbname", "kunde_e2e"]
        environment = None
    else:  # developer machine: the same isolated database over loopback
        database = os.environ["DB_URL"].rsplit("/", 1)[-1]
        command = ["psql", "-h", "localhost", "-U", os.environ["DB_USERNAME"], "-d", database]
        environment = {**os.environ, "PGPASSWORD": os.environ.get("DB_PASSWORD", "")}
    result = subprocess.run([*command, "-v", "ON_ERROR_STOP=1", "-Atc", statement], check=True,
                            capture_output=True, text=True, env=environment)
    return result.stdout.strip()


def start_backend(auto_enabled):
    env = dict(os.environ)
    env["AUTO_ENABLED"] = "true" if auto_enabled else "false"
    env["AUTO_SEED_DEMO"] = "true" if auto_enabled else "false"
    env["AUTH_PHONE_SECRET"] = fixture.FIXTURE_AUTH_KEY
    args = ["java", "-jar", "backend/target/kunde-api-0.1.0-SNAPSHOT.jar",
            "--server.address=127.0.0.1", "--server.port=8081"]
    log_dir = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    with (log_dir / "auto-backend.log").open("ab") as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, env=env)
    for _ in range(120):
        if process.poll() is not None:
            break
        try:
            capabilities = fixture.call("GET", "capabilities")
        except (OSError, RuntimeError):
            time.sleep(1)
            continue
        if capabilities["autoEnabled"] == auto_enabled:
            return process
        break
    fixture.stop_backend(process)
    raise RuntimeError("Isolated backend did not start with the expected Auto capability")


def day(offset):
    today = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5)).date()
    return (today + datetime.timedelta(days=offset)).isoformat()


# --- domain helpers -------------------------------------------------------------------------------------------------

class World:
    pass


world = World()


def venue(slug):
    prefix = "Тестовая автомойка" if slug == WASH else "Тестовое СТО"
    for item in fixture.call("GET", "auto/venues"):
        if item["name"].startswith(prefix):
            return fixture.call("GET", "auto/venues/" + item["id"])
    raise RuntimeError(f"Venue {slug} is not seeded")


def service(detail, name):
    index = next(i for i, s in enumerate(detail["services"]) if s["name"] == name)
    return index, detail["services"][index]


def free_slots(detail, svc, offset):
    return fixture.call("GET", f"auto/slots?venueId={detail['venue']['id']}&serviceId={svc['id']}&date={day(offset)}")


def pick_day(detail, svc, start):
    """The first day from +start with free slots (the demo stations are closed on Sundays); also the day chip index in the app."""
    for offset in range(start, 14):
        if free_slots(detail, svc, offset):
            return offset
    raise RuntimeError(f"no free day from +{start}")


def vehicle(token, plate):
    return fixture.call("POST", "auto/vehicles", token=token, expected=201,
                        body={"make": "Toyota", "model": "Camry", "year": 2018, "plate": plate})


def book_by_api(token, detail, svc, offset, slot_index, method="PAY_ON_SITE", key=None, car=None):
    slots = free_slots(detail, svc, pick_day(detail, svc, offset))
    car = car or vehicle(token, "E2E" + uuid.uuid4().hex[:5].upper())
    quote = fixture.call("POST", "auto/quotes", token=token, expected=201, body={
        "venueId": detail["venue"]["id"], "serviceId": svc["id"], "vehicleId": car["id"],
        "startsAt": slots[slot_index]["startsAt"]})
    check(quote["priceMinor"] == svc["priceMinor"], "the server must compute the price")
    status, booking = raw("POST", "auto/bookings", token=token, key=key or "e2e-" + uuid.uuid4().hex,
                          body={"quoteId": quote["id"], "paymentMethod": method})
    check(status in (200, 201), f"booking failed: {status} {booking}")
    return booking


def act(booking_id, action, **extra):
    return fixture.call("POST", f"partner/partners/{world.partner}/booking/bookings/{booking_id}/action",
                        token=world.partner_token, body={"action": action, **extra})


def mine(token, booking_id):
    return fixture.call("GET", f"auto/bookings/{booking_id}", token=token)


# --- setup ----------------------------------------------------------------------------------------------------------

def setup():
    if API_ONLY:  # with the app, this number signs in through the app first so its code request is never throttled
        world.consumer = fixture.session(CONSUMER_PHONE)
    world.partner_token = fixture.session(PARTNER_PHONE)
    world.other = fixture.session(OTHER_PHONE)
    world.third = fixture.session(THIRD_PHONE)
    world.specialist = fixture.session(SPECIALIST_PHONE)
    world.partner = None
    for _ in range(30):  # the synthetic partner is seeded while the backend finishes starting
        status, partners = raw("GET", "partner/partners", token=world.partner_token)
        if status == 200:
            world.partner = next((p["id"] for p in partners if p["verificationStatus"] == "APPROVED"), None)
        if world.partner:
            break
        time.sleep(1)
    check(world.partner, "the synthetic partner is missing (PARTNER_OPS_SEED_DEMO)")
    sql("update marketplace.booking_venues set partner_id = '" + world.partner + "' where slug in ('" + WASH + "', '" + STO + "')")
    check(sql("select count(*) from marketplace.booking_venues where partner_id = '" + world.partner
              + "' and slug in ('" + WASH + "', '" + STO + "')") == "2", "venues were not linked to the synthetic partner")
    world.wash = venue(WASH)
    world.sto = venue(STO)
    completed.append("backend_partner_and_executor_fixture")


# --- the same business scenario through the app (CI) or HTTP only (developer machine) ---------------------------------

def finish_wash(booking):
    """Partner: confirm, check in, start, complete (fixed price, no approval needed)."""
    for action in ("CONFIRM", "CHECK_IN", "START", "COMPLETE"):
        act(booking["id"], action)
    done = mine(world.consumer, booking["id"])
    check(done["status"] == "COMPLETED", done)
    return done


def price_approval_lifecycle(booking):
    for action in ("CONFIRM", "CHECK_IN", "START"):
        act(booking["id"], action)
    act(booking["id"], "PROPOSE_PRICE", finalPriceMinor=1500000)
    pending = mine(world.consumer, booking["id"])
    check(pending["priceApproval"] == "PENDING", pending)
    got, body = raw("POST", f"partner/partners/{world.partner}/booking/bookings/{booking['id']}/action",
                    token=world.partner_token, body={"action": "COMPLETE"})
    check(got == 409, f"a price that is not approved must block completion: {got} {body}")


def finish_after_approval(booking):
    act(booking["id"], "COMPLETE")
    done = mine(world.consumer, booking["id"])
    check(done["status"] == "COMPLETED" and done["finalPriceMinor"] == 1500000, done)
    payment = done["payment"]
    check(payment["method"] == "TEST_CARD" and payment["status"] == "TEST_CAPTURED"
          and payment["capturedMinor"] == 1500000, payment)


def api_main_flow():
    wash_index, wash_service = service(world.wash, "Мойка кузова")
    first = book_by_api(world.consumer, world.wash, wash_service, 1, 0, method="TEST_CARD")
    check(first["status"] == "PENDING" and first["payment"]["status"] == "TEST_HELD", first)
    done = finish_wash(first)
    check(done["payment"]["status"] == "TEST_CAPTURED", done["payment"])
    fixture.call("POST", f"auto/bookings/{first['id']}/review", token=world.consumer, expected=201,
                 body={"rating": 5, "text": "Хорошо"})
    completed.append("booking_confirm_complete_review")

    _, oil = service(world.sto, "Замена масла")
    second = book_by_api(world.consumer, world.sto, oil, 2, 0, method="TEST_CARD")
    price_approval_lifecycle(second)
    fixture.call("POST", f"auto/bookings/{second['id']}/price-decision", token=world.consumer, body={"approve": True})
    finish_after_approval(second)
    completed.append("price_approval_and_test_payment_capture")

    third = book_by_api(world.consumer, world.wash, wash_service, 3, 0)
    moved = fixture.call("POST", f"auto/bookings/{third['id']}/reschedule", token=world.consumer,
                         body={"startsAt": free_slots(world.wash, wash_service, pick_day(world.wash, wash_service, 4))[0]["startsAt"]})
    check(moved["status"] in ("PENDING", "CONFIRMED") and moved["startsAt"] != third["startsAt"], moved)
    cancelled = fixture.call("POST", f"auto/bookings/{third['id']}/cancel", token=world.consumer)
    check(cancelled["status"] == "CANCELLED", cancelled)
    completed.append("reschedule_and_cancel")


# --- backend-level scenarios that need no UI ----------------------------------------------------------------------------

def api_checks():
    _, wash_service = service(world.wash, "Мойка кузова")

    # idempotent retry: a lost response is retried with the same quote and key and never books twice
    car = vehicle(world.other, "IDEM" + uuid.uuid4().hex[:4].upper())
    detail_day = pick_day(world.wash, wash_service, 5)
    start = free_slots(world.wash, wash_service, detail_day)[0]["startsAt"]
    quote = fixture.call("POST", "auto/quotes", token=world.other, expected=201, body={
        "venueId": world.wash["venue"]["id"], "serviceId": wash_service["id"], "vehicleId": car["id"], "startsAt": start})
    key = "e2e-retry-" + uuid.uuid4().hex
    payload = {"quoteId": quote["id"], "paymentMethod": "PAY_ON_SITE"}
    status_one, one = raw("POST", "auto/bookings", token=world.other, key=key, body=payload)
    status_two, again = raw("POST", "auto/bookings", token=world.other, key=key, body=payload)
    check(status_one == 201 and status_two in (200, 201) and one["id"] == again["id"], "an idempotent retry must return the same booking")
    check(sql("select count(*) from transactions.bookings where idempotency_key = '" + key + "'") == "1", "double booking")
    other_slot = free_slots(world.wash, wash_service, detail_day)[-1]["startsAt"]
    other_quote = fixture.call("POST", "auto/quotes", token=world.other, expected=201, body={
        "venueId": world.wash["venue"]["id"], "serviceId": wash_service["id"], "vehicleId": car["id"], "startsAt": other_slot})
    reused, body = raw("POST", "auto/bookings", token=world.other, key=key, body={"quoteId": other_quote["id"], "paymentMethod": "PAY_ON_SITE"})
    check(reused == 409 and body["code"] == "IDEMPOTENCY_KEY_REUSED", f"the same key for another booking must be refused: {reused} {body}")
    completed.append("idempotent_retry")

    # partner rejection frees the slot and releases the test hold
    rejected = book_by_api(world.third, world.wash, wash_service, 6, 0, method="TEST_CARD")
    act(rejected["id"], "REJECT", reason="Нет свободных постов")
    after = mine(world.third, rejected["id"])
    check(after["status"] == "CANCELLED" and after["cancelledBy"] == "PARTNER" and after["payment"]["status"] == "TEST_VOIDED", after)
    completed.append("partner_rejection")

    # concurrency: three simultaneous bookings for one time; the quoted post is taken once, a re-quote reaches the second post
    users = [world.consumer, world.other, world.third]
    slot = free_slots(world.wash, wash_service, pick_day(world.wash, wash_service, 9))[0]["startsAt"]
    prepared = []
    for token in users:
        car = vehicle(token, "RACE" + uuid.uuid4().hex[:4].upper())
        quote = fixture.call("POST", "auto/quotes", token=token, expected=201, body={
            "venueId": world.wash["venue"]["id"], "serviceId": wash_service["id"], "vehicleId": car["id"], "startsAt": slot})
        prepared.append((token, quote["id"]))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        outcomes = list(pool.map(lambda p: raw("POST", "auto/bookings", token=p[0], key="e2e-race-" + uuid.uuid4().hex,
                                               body={"quoteId": p[1], "paymentMethod": "PAY_ON_SITE"}), prepared))
    results = sorted(status for status, _ in outcomes)
    check(results == [201, 409, 409], f"a quote is bound to one post, so exactly one simultaneous booking wins: {outcomes}")
    check(all(body["code"] == "SLOT_TAKEN" for status, body in outcomes if status == 409), outcomes)
    check(sql("select count(*) from transactions.bookings where starts_at = '" + slot + "' and status = 'PENDING'") == "1", "double booking")
    # the app reloads the slots and re-quotes: the loser now gets the station's other post, the next one finds the time taken
    losers = [token for token, (status, _) in zip((p[0] for p in prepared), outcomes) if status == 409]
    retried = []
    for token in losers:
        car = fixture.call("GET", "auto/vehicles", token=token)[-1]
        status, quote = raw("POST", "auto/quotes", token=token, body={
            "venueId": world.wash["venue"]["id"], "serviceId": wash_service["id"], "vehicleId": car["id"], "startsAt": slot})
        if status == 201:
            status, booked = raw("POST", "auto/bookings", token=token, key="e2e-retry-" + uuid.uuid4().hex,
                                 body={"quoteId": quote["id"], "paymentMethod": "PAY_ON_SITE"})
        retried.append(status)
    check(sorted(retried) == [201, 409], f"the second post takes one loser, the next finds the time taken: {retried}")
    check(sql("select count(distinct master_id) from transactions.bookings where starts_at = '" + slot + "' and status = 'PENDING'") == "2",
          "two bookings at one time must sit on two different posts")
    completed.append("concurrent_booking")

    # no slots: a past day is refused, and the closed day (the demo stations do not work on Sundays) offers nothing
    expect("GET", f"auto/slots?venueId={world.wash['venue']['id']}&serviceId={wash_service['id']}&date={day(-1)}", 400)
    sunday = next(offset for offset in range(0, 8)
                  if datetime.date.fromisoformat(day(offset)).weekday() == 6)
    check(free_slots(world.wash, wash_service, sunday) == [], "a closed day must offer no slots")
    completed.append("no_slots")

    # roadside: Executor AUTO_SPECIALIST, privacy, price approval
    fixture.call("POST", "executor/auto/profile", token=world.specialist, body={"name": "E2E specialist"})
    sql("update transactions.auto_specialists set status = 'APPROVED'; "
        "insert into transactions.auto_specialist_categories(user_id, category) select user_id, 'ROADSIDE' "
        "from transactions.auto_specialists on conflict do nothing")
    fixture.call("PUT", "executor/auto/availability", token=world.specialist, body={"online": True})
    fixture.call("PUT", "executor/auto/location", token=world.specialist, expected=204, body={"latitude": 43.24, "longitude": 76.89})
    car = fixture.call("GET", "auto/vehicles", token=world.consumer)[0]
    job = fixture.call("POST", "auto/jobs", token=world.consumer, key="e2e-job-" + uuid.uuid4().hex, expected=201, body={
        "vehicleId": car["id"], "category": "ROADSIDE", "description": "Не заводится",
        "addressText": "Алматы, ул. Тестовая 5 (синтетический адрес)", "latitude": 43.25, "longitude": 76.9})
    listed = json.dumps(fixture.call("GET", "executor/auto/jobs/available", token=world.specialist))
    check(job["id"] in listed and "Тестовая" not in listed, "the open list must not reveal the address")
    accepted = fixture.call("POST", f"executor/auto/jobs/{job['id']}/accept", token=world.specialist)
    check("Тестовая" in accepted["addressText"], "the exact address is visible only after assignment")
    for action in ("ARRIVE", "START"):
        fixture.call("POST", f"executor/auto/jobs/{job['id']}/progress", token=world.specialist, body={"action": action})
    fixture.call("POST", f"executor/auto/jobs/{job['id']}/progress", token=world.specialist,
                 body={"action": "PROPOSE_PRICE", "finalPriceMinor": 2500000})
    expect("POST", f"executor/auto/jobs/{job['id']}/progress", 409, token=world.specialist, body={"action": "COMPLETE"})
    fixture.call("POST", f"auto/jobs/{job['id']}/price-decision", token=world.consumer, body={"approve": True})
    done = fixture.call("POST", f"executor/auto/jobs/{job['id']}/progress", token=world.specialist, body={"action": "COMPLETE"})
    check(done["status"] == "COMPLETED", done)
    expect("GET", f"auto/jobs/{job['id']}", 404, token=world.other)  # someone else's job
    completed.append("roadside_executor_auto_specialist")


def flag_off_checks(process):
    """The platform flag off: nothing new is accepted, but a booking that already exists can still be cancelled."""
    _, wash_service = service(world.wash, "Мойка кузова")
    pending = book_by_api(world.third, world.wash, wash_service, 12, 1)
    fixture.stop_backend(process)
    process = start_backend(False)
    check(fixture.call("GET", "auto/categories") == [], "the catalogue must be empty while Auto is off")
    car = fixture.call("GET", "auto/vehicles", token=world.third)[0]
    got, body = raw("POST", "auto/quotes", token=world.third, body={
        "venueId": world.wash["venue"]["id"], "serviceId": wash_service["id"], "vehicleId": car["id"],
        "startsAt": pending["startsAt"]})
    check(got in (404, 409, 422), f"a quote must be refused while Auto is off: {got} {body}")
    cancelled = fixture.call("POST", f"auto/bookings/{pending['id']}/cancel", token=world.third)
    check(cancelled["status"] == "CANCELLED", "an existing booking must stay cancellable while Auto is off")
    completed.append("flag_off_new_denied_existing_cancellable")
    return process


# --- the real app (CI only) ---------------------------------------------------------------------------------------------

def reveal(*labels, direction="down", **options):
    start, end = ("670", "330") if direction == "down" else ("330", "670")
    for attempt in range(8):
        try:
            return android.find(*labels, timeout=3, **options)
        except RuntimeError:
            if attempt == 7:
                raise
            android.adb("shell", "input", "swipe", "185", start, "185", end, "300")


def tap(*labels, **options):
    android.adb("shell", "input", "tap", *reveal(*labels, **options))


def tap_day(index):
    """The day chips scroll sideways: bring the wanted one into view first (stations are closed on Sundays, so it can be far)."""
    identifier = f"auto-day-{index}"
    for _ in range(10):
        try:
            android.adb("shell", "input", "tap", *android.find(resource_id=identifier, timeout=3))
            return
        except RuntimeError:
            android.adb("shell", "input", "swipe", "330", "288", "60", "288", "250")
    raise RuntimeError(f"Could not bring the day chip {index} into view")


def field_text(identifier):
    """The current text of a field, read from the accessibility tree."""
    android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-field.xml")
    tree = ET.fromstring(android.adb("exec-out", "cat", "/sdcard/kunde-field.xml"))
    for node in tree.iter("node"):
        if node.get("package") == fixture.CONSUMER and node.get("resource-id", "").rsplit("/", 1)[-1] == identifier:
            return node.get("text", "")
    return None


def enter(identifier, value):
    """Type slowly and verify: the emulator sometimes drops the first characters of fast input."""
    for _ in range(4):
        tap(resource_id=identifier)
        for _ in range(len(value) + 6):
            android.adb("shell", "input", "keyevent", "KEYCODE_DEL")
        for character in value:
            android.adb("shell", "input", "text", character)
        typed = field_text(identifier) or ""
        if not typed or typed.replace(" ", "") == value.replace(" ", ""):  # an unreadable field is not rejected
            android.adb("shell", "input", "keyevent", "4")
            return
    raise RuntimeError(f"Could not type {identifier!r} reliably (last read {typed!r})")


def sign_in(phone, *signed_in_labels):
    """Sign in through the app; a stuck code request is retried from a clean start (screens are kept as evidence)."""
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
    """A fresh start on the home screen (the saved session is restored), not the screen the app was left on."""
    android.adb("shell", "am", "force-stop", fixture.CONSUMER)
    fixture.launch(fixture.CONSUMER)
    android.find("Алматы", "Almaty", timeout=60)


def back(times=1):
    for _ in range(times):
        android.adb("shell", "input", "keyevent", "4")


AUTO = ("Авто", "Auto")
MY_BOOKINGS = ("Мои записи", "Менің жазылуларым", "My bookings")
HISTORY = ("История обслуживания", "Қызмет көрсету тарихы", "Service history")
RETRY = ("Повторить", "Қайталау", "Retry")
CONFIRM = ("Подтвердить запись", "Жазылуды растау", "Confirm booking")
TEST_CARD = ("Тестовая карта", "Тест картасы", "Test card")
RESCHEDULE = ("Перенести", "Көшіру", "Reschedule")
CANCEL = ("Отменить запись", "Жазылудан бас тарту", "Cancel booking")
PENDING_LABEL = ("Ожидает подтверждения", "Растауды күтуде", "Waiting for confirmation")
COMPLETED_LABEL = ("Завершена", "Аяқталды", "Completed")
CANCELLED_LABEL = ("Отменена", "Бас тартылды", "Cancelled")
APPROVE = ("Согласовать", "Келісу", "Approve")
RATE = ("Оценить", "Бағалау", "Rate")
SEND = ("Отправить", "Жіберу", "Send")
THANKS = ("Спасибо за отзыв!", "Пікіріңіз үшін рахмет!", "Thank you for your review!")
ADD_CAR = ("Добавить автомобиль", "Көлік қосу", "Add a car")
SAVE = ("Сохранить", "Сақтау", "Save")


def open_venue(name_prefix):
    tap(*AUTO)
    android.find(*MY_BOOKINGS, timeout=30)
    tap(name_prefix)


def newest_booking_id(token, status=None):
    bookings = fixture.call("GET", "auto/bookings", token=token)
    bookings = [b for b in bookings if status is None or b["status"] == status]
    return sorted(bookings, key=lambda b: b["createdAt"] if "createdAt" in b else "")[-1]["id"]


def ui_book(prefix, service_index, day_index, *, with_car, test_card):
    open_venue(prefix)
    tap(resource_id=f"auto-book-{service_index}")
    if with_car:
        tap(*ADD_CAR)
        for identifier, value in [("auto-make", "Toyota"), ("auto-model", "Camry"), ("auto-year", "2018"), ("auto-plate", "UI777A02")]:
            enter(identifier, value)
        tap(*SAVE)
    tap(resource_id="auto-vehicle-0")
    tap_day(day_index)
    tap(resource_id="auto-slot-0")
    reveal("Предварительная стоимость", "Алдын ала құны", "Estimated cost")
    if test_card:
        tap(*TEST_CARD)
    tap(*CONFIRM)
    android.find(*PENDING_LABEL, timeout=30)


def ui_main_flow():
    wash_index, wash_service = service(world.wash, "Мойка кузова")
    oil_index, oil_service = service(world.sto, "Замена масла")
    first_day = pick_day(world.wash, wash_service, 1)
    oil_day = pick_day(world.sto, oil_service, 2)
    third_day = pick_day(world.wash, wash_service, 3)
    moved_day = pick_day(world.wash, wash_service, 4)

    ui_book("Тестовая автомойка «Демо»", wash_index, first_day, with_car=True, test_card=True)
    android.screenshot("consumer-booking-pending")
    first = newest_booking_id(world.consumer)
    check(mine(world.consumer, first)["payment"]["status"] == "TEST_HELD", "the test hold is created with the booking")
    finish_wash({"id": first})
    completed.append("consumer_add_car_catalog_slot_quote_book_pending")
    relaunch()
    tap(*AUTO)
    tap(*MY_BOOKINGS)
    reveal(*HISTORY)
    tap(*COMPLETED_LABEL)
    tap(*RATE)
    tap("5")
    tap(*SEND)
    android.find(*THANKS, timeout=20)
    android.screenshot("consumer-review")
    completed.append("consumer_history_and_review")

    relaunch()
    ui_book("Тестовое СТО «Демо»", oil_index, oil_day, with_car=False, test_card=True)
    second = newest_booking_id(world.consumer, "PENDING")
    price_approval_lifecycle({"id": second})
    relaunch()
    tap(*AUTO)
    tap(*MY_BOOKINGS)
    tap("Замена масла")  # the active booking opens its detail, where the proposed price is decided
    reveal(*APPROVE)
    android.screenshot("consumer-price-approval")
    tap(*APPROVE, clickable=True)
    time.sleep(2)
    finish_after_approval({"id": second})
    completed.append("consumer_price_approval_and_test_payment")

    relaunch()
    ui_book("Тестовая автомойка «Демо»", wash_index, third_day, with_car=False, test_card=False)
    third = newest_booking_id(world.consumer, "PENDING")
    tap(*RESCHEDULE, clickable=True)
    tap_day(moved_day)
    tap(resource_id="auto-slot-0")
    tap(*RESCHEDULE, clickable=True)
    android.find(*PENDING_LABEL, timeout=30)
    tap(*CANCEL, clickable=True)
    tap(*CANCEL, clickable=True)
    android.find(*CANCELLED_LABEL, timeout=30)
    check(mine(world.consumer, third)["status"] == "CANCELLED", "cancel from the app must reach the backend")
    android.screenshot("consumer-cancelled")
    completed.append("consumer_reschedule_and_cancel")


def ui_network_recovery(process):
    relaunch()
    tap(*AUTO)
    android.find(*MY_BOOKINGS, timeout=30)
    fixture.stop_backend(process)
    tap(*MY_BOOKINGS)
    android.find(*RETRY, timeout=35)
    android.screenshot("consumer-offline")
    process = start_backend(True)
    android.adb("reverse", "tcp:8081", "tcp:8081")
    for _ in range(3):
        tap(*RETRY, clickable=True)
        try:
            android.find(*HISTORY, timeout=20)
            completed.append("consumer_network_loss_and_retry")
            return process
        except RuntimeError:
            continue
    raise RuntimeError("The bookings list did not reload after the backend came back")


def ui_flag_off():
    relaunch()
    android.find("Алматы", "Almaty", timeout=60)
    try:
        tap(*AUTO)
        android.find(*MY_BOOKINGS, timeout=8)
    except RuntimeError:
        completed.append("consumer_auto_unavailable_when_flag_off")
        return
    raise RuntimeError("Auto remained usable in the app after the platform flag was switched off")


# --- run ----------------------------------------------------------------------------------------------------------------

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
        setup()
        if API_ONLY:
            phase = "api_main_flow"
            api_main_flow()
        else:
            phase = "install_and_sign_in"
            android.adb("reverse", "tcp:8081", "tcp:8081")
            android.adb("shell", "wm", "size", "390x844")
            android.adb("shell", "wm", "density", "160")
            android.adb("install", APKS / "consumer.apk")
            fixture.launch(fixture.CONSUMER)
            sign_in("7000000001", "Алматы", "Almaty")
            world.consumer = fixture.session(CONSUMER_PHONE)
            completed.append("consumer_sign_in")
            phase = "consumer_flows"
            ui_main_flow()
            phase = "network_recovery"
            process = ui_network_recovery(process)
        phase = "backend_scenarios"
        api_checks()
        phase = "flag_off"
        process = flag_off_checks(process)
        if not API_ONLY:
            ui_flag_off()
        report("PASSED", "complete")
    except Exception:
        report("FAILED", phase)
        if not API_ONLY:
            try:  # what the app itself reported, to tell an app problem from a server problem
                (REPORT / "logcat.txt").write_bytes(android.adb("logcat", "-d", "-t", "400", "flutter:V", "AndroidRuntime:E", "*:S"))
            except (OSError, subprocess.SubprocessError):
                pass
        try:  # the backend log helps to tell an app problem from a server problem
            log = Path(os.environ.get("RUNNER_TEMP", "/tmp"), "auto-backend.log")
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
