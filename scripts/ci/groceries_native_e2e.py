"""Exercise Consumer Groceries on Android against the real API and isolated PostgreSQL (synthetic store, no real payment)."""
import os
import time
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
CHECKOUT = ("Оформить заказ", "Тапсырысты рәсімдеу", "Checkout")
CONFIRM = ("Подтвердить заказ", "Тапсырысты растау", "Confirm order")


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
        mobile.reveal(*CHECKOUT)
        android.screenshot("04-cart")
        mobile.tap(*CHECKOUT)
        mobile.reveal(*CONFIRM)
        android.screenshot("05-checkout")
        mobile.tap(*CONFIRM)
        order = wait_for_order(token)
        assert order["status"] == "PLACED", order
        fixture.completed.append("consumer_groceries_order")
        android.screenshot("06-order")
        fixture.write_report("PASSED", "completed")
    except Exception:
        fixture.write_report("FAILED", phase)
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
