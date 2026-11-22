"""Run actual Delivery Consumer and Executor screens with the isolated Postgres fixture."""

import os
import re
import secrets
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import capture_android_visual as android
import rides_native_e2e as fixture

REPORT = Path("reports/delivery-native")
APKS = Path(os.environ["RUNNER_TEMP"]) / "delivery-apk"
PICKUP = ("Откуда забрать", "Pickup", "Алып кету мекенжайы")
DESTINATION = ("Куда доставить", "Destination", "Жеткізу мекенжайы")
COMPLETED = ("Доставка завершена", "Completed", "Жеткізу аяқталды")


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


def focused_field(identifier):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-visual.xml")
        root = ET.fromstring(android.adb("exec-out", "cat", "/sdcard/kunde-visual.xml"))
        for node in root.iter("node"):
            if node.get("resource-id", "").rsplit("/", 1)[-1] == identifier:
                for editor in node.iter("node"):
                    if editor.get("class") == "android.widget.EditText" and editor.get("focused") == "true":
                        return editor.get("text", "")
    raise RuntimeError(f"Text entry did not focus {identifier}")


def enter(identifier, value):
    tap(resource_id=identifier)
    focused_field(identifier)
    android.adb("shell", "input", "text", value)
    actual = focused_field(identifier)
    if actual != value:
        android.adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
        android.adb("shell", "input", "keyevent", *(["KEYCODE_DEL"] * len(actual)))
        android.adb("shell", "input", "text", value)
        if focused_field(identifier) != value:
            raise RuntimeError(f"Text entry did not populate {identifier}")
    android.adb("shell", "input", "keyevent", "4")


def read_code():
    android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-visual.xml")
    nodes = ET.fromstring(android.adb("exec-out", "cat", "/sdcard/kunde-visual.xml"))
    codes = {
        value
        for node in nodes.iter("node")
        if node.get("package") == fixture.CONSUMER
        for value in [node.get("text", ""), *node.get("content-desc", "").splitlines()]
        if re.fullmatch(r"[0-9]{8}", value)
    }
    if len(codes) != 1:
        raise RuntimeError("One-time handoff code was not visible to the sender")
    android.adb("shell", "rm", "/sdcard/kunde-visual.xml")
    return codes.pop()


def seed_courier():
    token = fixture.session("+77000000002")
    profile = fixture.call("POST", "executor/deliveries/profile", token=token,
                           body={"name": "Synthetic courier", "vehicle": "BICYCLE"})
    courier = str(uuid.UUID(profile["userId"]))
    subprocess.run([
        "docker", "exec", os.environ["DELIVERY_POSTGRES_CONTAINER"],
        "psql", "--username", "kunde_e2e", "--dbname", "kunde_e2e", "-v", "ON_ERROR_STOP=1", "-c",
        "update transactions.delivery_couriers set status = 'APPROVED', max_grams = 3000, max_side_cm = 40 "
        f"where user_id = '{courier}'",
    ], check=True, stdout=subprocess.DEVNULL)


def create_delivery(*, capture_quote=True):
    tap("Доставка", "Delivery", "Жеткізу")
    tap("Отправить посылку", "Send a parcel", "Сәлемдеме жіберу", clickable=True)
    tap(*PICKUP)
    tap("[DEV/TEST] Отправитель", "[DEV/TEST] Pickup", "[DEV/TEST] Жіберуші")
    tap(*DESTINATION)
    tap("[DEV/TEST] Получатель", "[DEV/TEST] Destination", "[DEV/TEST] Алушы")
    for identifier, value in [
        ("delivery-weight", "500"),
        ("delivery-length", "30"),
        ("delivery-width", "20"),
        ("delivery-height", "2"),
        ("delivery-recipient", "SyntheticRecipient"),
        ("delivery-phone", "+77000000000"),
        ("delivery-description", "Documents"),
    ]:
        enter(identifier, value)
    tap("В отправлении нет запрещённых или опасных предметов",
        "The shipment contains no prohibited or dangerous items",
        "Жөнелтілімде тыйым салынған немесе қауіпті заттар жоқ")
    tap("Рассчитать стоимость", "Get a quote", "Бағасын есептеу")
    # The quote is inserted above the submit button. On a scrolled form the
    # quote label can appear above the current viewport after layout.
    reveal("DEV/TEST · тестовый маршрут", "DEV/TEST · synthetic route", "DEV/TEST · сынақ бағыты",
           direction="up")
    if capture_quote:
        android.screenshot("consumer-quote")
    tap("Подтвердить доставку", "Confirm delivery", "Жеткізуді растау")


HISTORY = ("История отправлений", "Shipment history", "Жөнелтілімдер тарихы")
RETRY = ("Повторить", "Retry", "Қайталау")


def recover_history():
    # A connection opened before the fixture stopped can fail once more
    # after restart. Wait for the app to offer Retry again before resubmitting.
    android.adb("reverse", "tcp:8081", "tcp:8081")
    for _ in range(3):
        tap(*RETRY, clickable=True)
        try:
            android.find(*COMPLETED, timeout=18)
            return
        except RuntimeError:
            continue
    raise RuntimeError("Delivery history did not reload after backend restart")


def cancel_second_delivery():
    android.adb("shell", "am", "force-stop", fixture.CONSUMER)
    fixture.launch(fixture.CONSUMER)
    android.find("Алматы", "Almaty", timeout=60)
    create_delivery(capture_quote=False)
    android.find("Ищем курьера", "Finding a courier", "Курьер ізделуде")
    cancel = ("Отменить доставку", "Cancel delivery", "Жеткізуден бас тарту")
    tap(*cancel, clickable=True)
    tap(*cancel, clickable=True)
    reveal("Отменено", "Cancelled", "Бас тартылды")
    android.screenshot("consumer-cancelled-after-reconnect")


def confirm_disabled_intake():
    if fixture.call("GET", "capabilities")["deliveryEnabled"]:
        raise RuntimeError("Delivery intake remained enabled in the disabled fixture")
    android.adb("shell", "am", "force-stop", fixture.CONSUMER)
    fixture.launch(fixture.CONSUMER)
    android.find("Алматы", "Almaty", timeout=60)
    try:
        android.find("Доставка", "Delivery", "Жеткізу", timeout=8)
    except RuntimeError:
        return
    raise RuntimeError("Delivery entry remained visible after both active shipments were closed")


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = REPORT
    android.REPORT = REPORT
    process = None
    phase = "backend"
    fixture.write_report("STARTED", phase)
    os.environ["DELIVERY_HANDOFF_KEY"] = secrets.token_urlsafe(48)
    try:
        process = fixture.start_backend(False)
        capabilities = fixture.call("GET", "capabilities")
        if not capabilities["deliveryEnabled"] or not capabilities["deliverySyntheticRouting"]:
            raise RuntimeError("Expected an explicitly synthetic and enabled Delivery fixture")
        seed_courier()
        phase = "install_and_sign_in"
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")
        android.adb("install", APKS / "consumer.apk")
        android.adb("install", APKS / "executor.apk")
        fixture.launch(fixture.EXECUTOR)
        fixture.login("7000000002", "KUNDE Executor")
        tap("Режим доставки", "Delivery mode", "Жеткізу режимі")
        tap("Готов принимать заказы", "Available for offers", "Тапсырыс қабылдауға дайынмын")
        tap("DEV/TEST · передать тестовую точку", "DEV/TEST · share synthetic location",
            "DEV/TEST · сынақ орнын жіберу")
        fixture.completed.append("executor_identity_and_online")

        phase = "consumer_quote_and_create"
        fixture.launch(fixture.CONSUMER)
        fixture.login("7000000001", "Алматы", "Almaty")
        create_delivery()
        android.find("Ищем курьера", "Finding a courier", "Курьер ізделуде")
        fixture.completed.append("consumer_create")

        phase = "executor_offer_pickup_and_transit"
        fixture.launch(fixture.EXECUTOR)
        tap("Принять", "Accept", "Қабылдау")
        tap("Выехать", "Depart", "Жолға шығу")
        tap("Я на месте", "Arrived", "Мен келдім")
        tap("Забрал посылку", "Picked up", "Сәлемдемені алдым")
        tap("Еду к получателю", "Start transit", "Алушыға барамын")
        fixture.completed.append("assignment_pickup_transit")

        phase = "proof_and_completion"
        fixture.launch(fixture.CONSUMER)
        tap("Получить код вручения", "Get handoff code", "Тапсыру кодын алу")
        android.find("DEV/TEST · передайте код получателю", "DEV/TEST · share the code with the recipient",
                     "DEV/TEST · кодты алушыға беріңіз")
        code = read_code()
        fixture.launch(fixture.EXECUTOR)
        tap("Подтвердить вручение", "Confirm handoff", "Тапсыруды растау")
        try:
            fixture.type_text(code)
        except subprocess.SubprocessError:
            raise RuntimeError("Could not enter the one-time code") from None
        tap("Проверить код", "Verify code", "Кодты тексеру")
        tap("Завершить", "Complete delivery", "Аяқтау")
        reveal(*COMPLETED)
        android.screenshot("executor-completed")
        fixture.completed.append("verified_handoff_executor_history")

        phase = "consumer_history"
        fixture.launch(fixture.CONSUMER)
        reveal(*COMPLETED)
        android.adb("shell", "input", "keyevent", "4")
        tap("История отправлений", "Shipment history", "Жөнелтілімдер тарихы")
        reveal(*COMPLETED)
        android.screenshot("consumer-history")
        fixture.completed.append("consumer_history")

        phase = "network_recovery_and_cancellation"
        android.adb("shell", "input", "keyevent", "4")
        fixture.stop_backend(process)
        process = None
        tap(*HISTORY)
        android.find(*RETRY, timeout=35)
        process = fixture.start_backend(False)
        recover_history()
        cancel_second_delivery()
        fixture.completed.append("android_network_recovery_and_cancellation")

        phase = "disabled_intake"
        fixture.stop_backend(process)
        process = None
        os.environ["DELIVERY_ENABLED"] = "false"
        process = fixture.start_backend(False)
        confirm_disabled_intake()
        fixture.completed.append("android_disabled_intake")
        fixture.write_report("PASSED", "complete")
    except Exception:
        fixture.write_report("FAILED", phase)
        if phase in ("consumer_quote_and_create", "network_recovery_and_cancellation", "disabled_intake"):
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
