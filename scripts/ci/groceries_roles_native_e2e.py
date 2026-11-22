"""Groceries order fulfilment: the real Partner APK picks and hands over an order; Executor and Admin steps use the same API.

Fixture role holders (partner staff, approved courier, admin grant) are synthetic rows in the isolated CI PostgreSQL only.
"""
import os
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import auto_native_e2e as mobile
import capture_android_visual as android
import groceries_native_e2e as consumer
import rides_native_e2e as fixture


REPORT = Path("reports/groceries-roles-native")
CUSTOMER, OWNER, ADMIN, COURIER = "+77000000001", "+77000000002", "+77000000003", "+77000000004"
PARTNER_PACKAGE = "com.kunde.kunde_partner"
CHEESE = "Сыр Российский 200 г"


def sql(statement):
    subprocess.run(
        ["docker", "exec", os.environ["GROCERIES_POSTGRES_CONTAINER"], "psql", "--username", "kunde_e2e",
         "--dbname", "kunde_e2e", "-v", "ON_ERROR_STOP=1", "-c", statement],
        check=True, stdout=subprocess.DEVNULL)


def user_id(phone):
    return uuid.UUID(fixture.call("GET", "me", token=fixture.session(phone))["id"])


def prepare():
    owner, admin, courier = user_id(OWNER), user_id(ADMIN), user_id(COURIER)
    partner = uuid.uuid4()
    sql(f"""
        INSERT INTO marketplace.partners(id,display_name,verification_status,created_by_user_id)
            VALUES ('{partner}','Synthetic Android store','APPROVED','{owner}');
        INSERT INTO marketplace.partner_staff(partner_id,user_id,role,granted_by_user_id)
            VALUES ('{partner}','{owner}','OWNER','{owner}');
        UPDATE marketplace.food_restaurants SET partner_id='{partner}' WHERE slug='fresh-market-almaty';
        INSERT INTO identity.admin_grants(user_id,permission,reason)
            VALUES ('{admin}','GROCERIES_OPERATIONS','Synthetic Android groceries fixture');
        INSERT INTO transactions.delivery_couriers(user_id,display_name,vehicle,status,online,max_grams,max_side_cm)
            VALUES ('{courier}','Synthetic courier','BICYCLE','APPROVED',true,20000,60);
    """)
    return partner


def place_order():
    token = fixture.session(CUSTOMER)
    address = fixture.call("POST", "me/addresses", token=token, expected=201, body={
        "label": "Дом", "formattedAddress": "Алматы, ул. Тестовая 1", "latitude": 43.238, "longitude": 76.945})
    store = next(s for s in fixture.call("GET", "food/restaurants?vertical=GROCERY") if s["slug"] == "fresh-market-almaty")
    menu = fixture.call("GET", f"food/restaurants/{store['id']}")
    cheese = next(d for sec in menu["sections"] for d in sec["dishes"] if d["name"] == CHEESE)
    return fixture.call("POST", "food/orders", token=token, expected=201, key=uuid.uuid4().hex, body={
        "restaurantId": store["id"], "items": [{"dishId": cheese["id"], "quantity": 2, "optionIds": []}],
        "addressId": address["id"], "paymentMethod": "TEST_CARD"}), token


def wait_status(order_id, token, wanted):
    for _ in range(25):
        status = fixture.call("GET", f"food/orders/{order_id}", token=token)["status"]
        if status == wanted:
            return
        time.sleep(1)
    raise RuntimeError(f"The order did not reach {wanted}")


def partner_login():
    android.PACKAGE = PARTNER_PACKAGE
    android.adb("install", Path(os.environ["RUNNER_TEMP"], "groceries-role-apk", "partner.apk"))
    android.adb("shell", "am", "start", "-W", "-n", f"{PARTNER_PACKAGE}/.MainActivity")
    android.tap(node_class="android.widget.EditText")
    time.sleep(.5)
    for digit in OWNER[1:]:
        android.adb("shell", "input", "text", digit)
    android.adb("shell", "input", "keyevent", "4")
    mobile.tap("Получить код", "Код алу", "Get code")
    android.find("Войти", "Кіру", "Sign in", timeout=60)
    time.sleep(.5)
    for digit in "123456":
        android.adb("shell", "input", "text", digit)
    android.adb("shell", "input", "keyevent", "4")
    mobile.tap("Войти", "Кіру", "Sign in", clickable=True)
    android.find("Заведение", "Мекеме", "Business", timeout=60)


def confirm_if_asked():
    try:
        android.tap("Подтвердить", "Растау", "Confirm", clickable=True, timeout=4)
    except RuntimeError:
        pass


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = android.REPORT = REPORT
    phase = "fixture"
    fixture.write_report("STARTED", phase)
    process = None
    try:
        process = fixture.start_backend(False)
        partner = prepare()
        order, customer = place_order()
        order_id = order["id"]
        assert order["status"] == "PLACED" and order["vertical"] == "GROCERY", order
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")

        phase = "partner_fulfilment"
        partner_login()
        mobile.tap("Заказы", "Тапсырыстар", "Orders")
        consumer.tap_starting("2× Сыр")
        android.screenshot("01-partner-order")
        mobile.tap("Принять заказ", "Тапсырысты қабылдау", "Accept order")
        confirm_if_asked()
        wait_status(order_id, customer, "ACCEPTED")
        mobile.tap("Начать готовить", "Дайындауды бастау", "Start preparing")
        confirm_if_asked()
        wait_status(order_id, customer, "PREPARING")
        mobile.tap("Собрано", "Жиналды", "Picked")
        android.screenshot("02-partner-picking")
        mobile.tap("Заказ готов", "Тапсырыс дайын", "Order is ready")
        confirm_if_asked()
        wait_status(order_id, customer, "READY_FOR_PICKUP")
        android.screenshot("03-partner-ready")
        fixture.completed.append("partner_apk_picking_and_handover")

        phase = "executor_delivery"
        courier = fixture.session(COURIER)
        tasks = fixture.call("GET", "executor/food/tasks/open", token=courier)
        task = next(t for t in tasks if t["orderId"] == order_id) if tasks and "orderId" in tasks[0] else tasks[0]
        for step in ("accept", "pickup", "deliver"):
            fixture.call("POST", f"executor/food/tasks/{task['id']}/{step}", token=courier)
        wait_status(order_id, customer, "DELIVERED")
        fixture.completed.append("executor_delivery_api")

        phase = "admin_control_center"
        admin = fixture.session(ADMIN)
        summary = fixture.call("GET", "admin/groceries/summary", token=admin)
        assert summary, "empty Control Center summary"
        listed = fixture.call("GET", "admin/groceries/orders", token=admin)
        rows = listed if isinstance(listed, list) else listed.get("items", [])
        assert any(row.get("id") == order_id for row in rows), "the order is missing in the Admin list"
        fixture.completed.append("admin_control_center_api")
        fixture.write_report("PASSED", "completed")
    except Exception as error:
        fixture.write_report("FAILED", phase)
        (REPORT / "failure-step.txt").write_text(str(error), encoding="utf-8")
        log = Path(os.environ.get("RUNNER_TEMP", "/tmp"), "rides-backend.log")
        if log.exists():  # the isolated test backend only: synthetic data, no secrets
            (REPORT / "backend-tail.log").write_text("\n".join(log.read_text(errors="replace").splitlines()[-120:]))
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
