"""Consumer Health booking on Android against the isolated CI backend."""

import datetime
import os
import time
import urllib.parse
from pathlib import Path
from zoneinfo import ZoneInfo

import auto_native_e2e as mobile
import capture_android_visual as android
import rides_native_e2e as fixture


REPORT = Path("reports/health-native")
PHONE = "+77000000001"
HEALTH = ("Здоровье", "Денсаулық", "Health")
HOME = ("Здоровье и благополучие", "Денсаулық және әл-ауқат", "Health & Wellness")


def choose_slot(service, venue, master):
    today = datetime.datetime.now(ZoneInfo("Asia/Almaty")).date()
    for index in range(1, 4):
        qs = urllib.parse.urlencode({
            "venueId": venue["id"], "serviceId": service["id"], "masterId": master["id"],
            "date": (today + datetime.timedelta(days=index)).isoformat(),
        })
        slots = fixture.call("GET", "booking/slots?" + qs)
        if slots:
            return index, slots[0]["startsAt"][11:16]
    raise RuntimeError("No slot for the synthetic specialist in the next three days")


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = REPORT
    android.REPORT = REPORT
    phase = "backend"
    fixture.write_report("STARTED", phase)
    process = None
    try:
        process = fixture.start_backend(False)
        for _ in range(60):
            venues = fixture.call("GET", "booking/health/venues?direction=DOCTORS")
            if venues:
                break
            if process.poll() is not None:
                raise RuntimeError("Synthetic Health backend exited")
            time.sleep(1)
        else:
            raise RuntimeError("Synthetic Health seed did not become available")
        venue = venues[0]
        detail = fixture.call("GET", f"booking/venues/{venue['id']}")
        service = detail["services"][0]
        master = detail["masters"][0]
        index, clock = choose_slot(service, venue, master)
        phase = "consumer_catalog"
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")
        android.adb("install", Path(os.environ["RUNNER_TEMP"], "health-apk", "consumer.apk"))
        fixture.launch(fixture.CONSUMER)
        mobile.sign_in(PHONE[2:], "Алматы", "Almaty")
        mobile.tap(*HEALTH)
        android.find(*HOME)
        android.screenshot("01-health-home")
        mobile.tap("Врачи", "Дәрігерлер", "Doctors")
        mobile.reveal(venue["name"])
        android.screenshot("02-health-catalog")
        mobile.tap(venue["name"])
        android.find(service["name"])
        android.screenshot("03-organization")
        mobile.tap(master["name"])
        android.find("Синтетический профиль", "Синтетикалық профиль", "Synthetic profile")
        android.screenshot("04-specialist")
        fixture.completed.append("catalog_and_specialist")
        phase = "consumer_booking"
        mobile.tap(service["name"])
        mobile.tap(resource_id=f"health-day-{index}")
        mobile.tap(clock)
        android.screenshot("05-booking-slot")
        mobile.tap("Тестовая карта", "Сынақ картасы", "Test card")
        mobile.tap(resource_id="health-terms")
        mobile.reveal(resource_id="health-book-submit")
        android.screenshot("06-review-and-test-payment")
        mobile.tap(resource_id="health-book-submit")
        token = fixture.session(PHONE)
        # Fetch only the fixture customer's own records and verify what the app wrote.
        for _ in range(15):
            history = fixture.call("GET", "booking/bookings?healthOnly=true", token=token)
            if history:
                break
            time.sleep(1)
        else:
            raise RuntimeError("Android failed to persist an appointment")
        booking = history[0]
        if booking["status"] != "PENDING" or booking["paymentStatus"] != "TEST_HELD":
            raise RuntimeError("Expected a pending synthetic partner appointment with a test hold")
        android.find(booking["id"])
        android.screenshot("07-appointment-pending")
        fixture.completed.append("consumer_test_card_booking")
        phase = "consumer_cancellation"
        mobile.tap("Отменить запись", "Жазылудан бас тарту", "Cancel booking")
        android.find("Отменить запись?", "Жазылудан бас тарту керек пе?", "Cancel the booking?")
        android.tap("Отменить запись", "Жазылудан бас тарту", "Cancel booking", clickable=True)
        android.find("Отменена", "Бас тартылды", "Cancelled")
        result = fixture.call("GET", f"booking/bookings/{booking['id']}", token=token)
        if result["status"] != "CANCELLED" or result["paymentStatus"] != "TEST_VOIDED":
            raise RuntimeError("Expected cancellation and release of the test hold")
        android.screenshot("08-appointment-cancelled")
        fixture.completed.append("consumer_cancel")
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
