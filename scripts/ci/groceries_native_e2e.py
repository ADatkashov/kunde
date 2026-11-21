"""Exercise Consumer Groceries on Android against the real API and isolated PostgreSQL (synthetic store, no real payment)."""
import os
import re
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import auto_native_e2e as mobile
import capture_android_visual as android
import rides_native_e2e as fixture


REPORT = Path("reports/groceries-native")
PHONE = "+77000000001"
GROCERIES = ("Продукты", "Азық-түлік", "Groceries")
PRODUCT = "Сыр Российский 200 г"  # 2 190 ₸ on the shelf: two pieces clear the 3 000 ₸ minimum order
ADD = ("Добавить в корзину", "Себетке қосу", "Add to cart")
CART = ("Корзина · 2",)
CHECKOUT = ("Оформить заказ", "Тапсырысты рәсімдеу", "Checkout")  # followed by " · <total>"
CONFIRM = "Подтвердить заказ"  # followed by " · <total>"


def tap_starting(prefix, timeout=60):
    """Buttons that carry the live total in their label ("Оформить заказ · 4 380 ₸") are matched by their fixed beginning."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        android.adb("shell", "uiautomator", "dump", "/sdcard/kunde-visual.xml")
        tree = ET.fromstring(android.adb("exec-out", "cat", "/sdcard/kunde-visual.xml"))
        for node in tree.iter("node"):
            if node.get("package") != fixture.CONSUMER:
                continue
            labels = {node.get("text", ""), *node.get("content-desc", "").splitlines()}
            if any(value.startswith(prefix) for value in labels):
                x1, y1, x2, y2 = (int(v) for v in re.findall(r"\d+", node.get("bounds", "")))
                if x2 > x1 and y2 > y1:
                    android.adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
                    return
        android.adb("shell", "input", "swipe", "185", "670", "185", "330", "300")
    raise RuntimeError(f"Could not locate UI element starting with {prefix!r}")


def wait_for_order(token):
    for _ in range(20):
        orders = fixture.call("GET", "food/orders", token=token)
        orders = orders if isinstance(orders, list) else orders.get("items", [])
        if orders:
            return orders[0]
        time.sleep(1)
    raise RuntimeError("Android did not create a Groceries order")


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = android.REPORT = REPORT
    phase = "backend"
    fixture.write_report("STARTED", phase)
    process = None
    try:
        process = fixture.start_backend(False)
        caps = fixture.call("GET", "capabilities")
        if not caps.get("groceriesEnabled"):
            raise RuntimeError("Groceries is disabled")
        token = fixture.session(PHONE)
        fixture.call("POST", "me/addresses", token=token, expected=201, body={
            "label": "Дом", "formattedAddress": "Алматы, ул. Тестовая 1",
            "latitude": 43.238, "longitude": 76.945})
        phase = "consumer_catalog"
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")
        android.adb("install", Path(os.environ["RUNNER_TEMP"], "groceries-apk", "consumer.apk"))
        fixture.launch(fixture.CONSUMER)
        mobile.sign_in(PHONE[2:], "Алматы", "Almaty")
        android.screenshot("01-home")
        mobile.tap(*GROCERIES)
        mobile.reveal(PRODUCT)
        android.screenshot("02-groceries-home")
        phase = "consumer_product"
        mobile.tap(PRODUCT)
        mobile.tap("+")
        mobile.reveal(*ADD)
        android.screenshot("03-product")
        mobile.tap(*ADD)
        phase = "consumer_checkout"
        mobile.tap(*CART)
        mobile.reveal("Итого", "Барлығы", "Total")
        android.screenshot("04-cart")
        tap_starting(CHECKOUT[0])
        android.screenshot("05-checkout")
        tap_starting(CONFIRM)
        order = wait_for_order(token)
        assert order["status"] == "PLACED", order
        fixture.completed.append("consumer_groceries_order")
        android.screenshot("06-order")
        fixture.write_report("PASSED", "completed")
    except Exception:
        fixture.write_report("FAILED", phase)
        log = Path(os.environ.get("RUNNER_TEMP", "/tmp"), "rides-backend.log")
        if log.exists():  # the isolated test backend only: synthetic data, no secrets
            REPORT.joinpath("backend-tail.log").write_text(
                "\n".join(log.read_text(errors="replace").splitlines()[-120:]))
        try:
            android.screenshot("failure")
        except Exception:
            pass
        raise
    finally:
        if process is not None:
            fixture.stop_backend(process)


if __name__ == "__main__":
    main()
