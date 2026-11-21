"""Exercise Consumer Education with Android, the real API and isolated PostgreSQL."""
import os
import time
from pathlib import Path

import auto_native_e2e as mobile
import capture_android_visual as android
import rides_native_e2e as fixture


REPORT = Path("reports/education-native")
PHONE = "+77000000001"
EDUCATION = ("Обучение", "Білім", "Education")
MY_COURSES = ("Мои курсы", "Курстарым", "My courses")
COMPLETE = ("Завершить урок", "Сабақты аяқтау", "Complete lesson")


def wait_for_learning(token, identifier, predicate, description):
    for _ in range(15):
        snapshot = fixture.call("GET", f"education/enrollments/{identifier}/learning", token=token)
        if predicate(snapshot):
            return snapshot
        time.sleep(1)
    raise RuntimeError(f"Android did not persist {description}")


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = android.REPORT = REPORT
    phase = "backend"
    fixture.write_report("STARTED", phase)
    process = None
    try:
        process = fixture.start_backend(False)
        if not fixture.call("GET", "capabilities")["educationEnabled"]:
            raise RuntimeError("Education is disabled")
        card = fixture.call("GET", "education/courses?q=Python")["items"][0]
        title = card["title"]
        phase = "consumer_catalog"
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")
        android.adb("install", Path(os.environ["RUNNER_TEMP"], "education-apk", "consumer.apk"))
        fixture.launch(fixture.CONSUMER)
        mobile.sign_in(PHONE[2:], "Алматы", "Almaty")
        mobile.tap(*EDUCATION)
        mobile.reveal(title)
        android.screenshot("01-catalog")
        mobile.tap(title)
        mobile.tap("Выбрать поток", "Топты таңдау", "Choose a cohort")
        mobile.tap("В записи", "Жазба", "Recorded")
        android.screenshot("02-cohort-and-payment")
        phase = "consumer_payment"
        mobile.tap("Оплатить TEST_CARD", "TEST_CARD арқылы төлеу", "Pay with TEST_CARD")
        mobile.reveal("Тестовая оплата подтверждена", "Сынақ төлемі расталды", "Test payment captured")
        token = fixture.session(PHONE)
        entries = fixture.call("GET", "education/enrollments", token=token)
        assert len(entries) == 1 and entries[0]["paymentStatus"] == "TEST_CAPTURED"
        identifier = entries[0]["id"]
        fixture.completed.append("consumer_test_card")
        phase = "consumer_learning"
        mobile.back(2)
        mobile.tap(*MY_COURSES)
        mobile.tap(title)
        mobile.tap("Переменные")
        mobile.tap(*COMPLETE)
        wait_for_learning(token, identifier, lambda data: data["lessons"][0]["completed"], "the first lesson")
        mobile.tap("Условия и циклы")
        mobile.tap(*COMPLETE)
        recap = wait_for_learning(token, identifier, lambda data: all(
            lesson["completed"] for lesson in data["lessons"]), "both lessons")
        if recap.get("quiz"):
            mobile.tap("Перебирает значения")
        recap = wait_for_learning(token, identifier, lambda data: data["enrollment"]["certificateCode"],
                                  "the course completion code")
        code = recap["enrollment"]["certificateCode"]
        assert fixture.call("GET", f"education/certificates/{code}")["title"] == title
        mobile.reveal("Копировать", "Көшіру", "Copy", clickable=True)
        android.screenshot("03-course-completed")
        fixture.completed.append("consumer_learning_and_verification_code")
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
