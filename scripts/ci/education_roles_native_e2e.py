"""Native Education Admin moderation and Executor attendance on isolated CI data."""

import datetime
import os
import subprocess
import time
import uuid
from pathlib import Path

import auto_native_e2e as mobile
import capture_android_visual as android
import rides_native_e2e as fixture


REPORT = Path("reports/education-roles-native")
OWNER = "+77000000002"
MODERATOR = "+77000000003"
INSTRUCTOR = "+77000000004"
STUDENT = "+77000000005"
TITLE = "Synthetic Android Education class"


def sql(statement):
    subprocess.run(
        ["docker", "exec", os.environ["EDUCATION_POSTGRES_CONTAINER"], "psql",
         "--username", "kunde_e2e", "--dbname", "kunde_e2e", "-v", "ON_ERROR_STOP=1",
         "-c", statement],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def prepare():
    ids = []
    for phone in (OWNER, MODERATOR, INSTRUCTOR):
        token = fixture.session(phone)
        ids.append(uuid.UUID(fixture.call("GET", "me", token=token)["id"]))
    owner, moderator, instructor = ids
    partner = uuid.uuid4()
    # A CI-only fixture creates narrowly scoped synthetic role holders.
    sql(f"""
        INSERT INTO marketplace.partners(id,display_name,verification_status,created_by_user_id)
            VALUES ('{partner}','Synthetic Android school','APPROVED','{owner}');
        INSERT INTO marketplace.partner_staff(partner_id,user_id,role,granted_by_user_id)
            VALUES ('{partner}','{owner}','OWNER','{owner}'),
                   ('{partner}','{instructor}','OPERATOR','{owner}');
        INSERT INTO identity.admin_grants(user_id,permission,reason)
            VALUES ('{moderator}','EDUCATION_OPERATIONS','Synthetic Android education fixture');
    """)
    owner_token = fixture.session(OWNER)
    root = f"partner/partners/{partner}/education/courses"
    course = fixture.call("POST", root, token=owner_token, expected=201, body={
        "title": TITLE, "description": "Synthetic offline training", "category": "IT",
        "city": "Алматы", "language": "ru", "format": "OFFLINE_GROUP", "priceMinor": 750, "durationMinutes": 30,
    })
    course_id = uuid.UUID(course["id"])
    starts = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=3)
    cohort = fixture.call("POST", f"{root}/{course_id}/cohorts", token=owner_token, expected=201, body={
        "format": "OFFLINE_GROUP", "startsAt": starts.isoformat(),
        "endsAt": (starts + datetime.timedelta(minutes=30)).isoformat(),
        "capacity": 2, "instructorId": str(instructor),
    })
    fixture.call("POST", f"{root}/{course_id}/submit", token=owner_token, body={})
    return course_id, uuid.UUID(cohort["id"])


def launch_and_login(app, package, phone, screen_title):
    apk = Path(os.environ["RUNNER_TEMP"], "education-role-apk", f"{app}.apk")
    android.adb("install", apk)
    for attempt in range(2):
        fixture.launch(package)
        try:
            fixture.login(phone[2:], screen_title)
            return
        except (RuntimeError, subprocess.SubprocessError):
            android.screenshot(f"{app}-login-attempt-{attempt + 1}")
            if attempt:
                raise
            android.adb("shell", "am", "force-stop", package)
            android.adb("shell", "pm", "clear", package)


def enter_reason(label_choices, value):
    android.find(*label_choices)
    android.tap(node_class="android.widget.EditText")
    android.adb("shell", "input", "text", value)
    android.adb("shell", "input", "keyevent", "4")
    mobile.tap("OK", "ОК", clickable=True)


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    fixture.REPORT = android.REPORT = REPORT
    phase = "fixture"
    fixture.write_report("STARTED", phase)
    process = None
    try:
        process = fixture.start_backend(False)
        course, cohort = prepare()
        android.adb("reverse", "tcp:8081", "tcp:8081")
        android.adb("shell", "wm", "size", "390x844")
        android.adb("shell", "wm", "density", "160")

        phase = "admin_moderation"
        launch_and_login("admin", "com.kunde.admin", MODERATOR, "KUNDE Control Center")
        mobile.tap("Модерация курсов", "Курстарды модерациялау", "Course moderation")
        mobile.reveal(TITLE)
        mobile.tap("Опубликовать", "Жариялау", "Publish")
        enter_reason(("Причина решения", "Шешімнің себебі", "Decision reason"), "Synthetic%stest")
        for _ in range(15):
            cards = fixture.call("GET", "education/courses?q=Synthetic")
            if any(card["id"] == str(course) for card in cards["items"]):
                break
            time.sleep(1)
        else:
            raise RuntimeError("The Admin APK did not publish the synthetic course")
        android.screenshot("01-admin-published")
        fixture.completed.append("admin_publication")

        phase = "executor_attendance"
        student = fixture.session(STUDENT)
        enrollment = fixture.call("POST", "education/enrollments", token=student, expected=201,
                                  key=uuid.uuid4().hex, body={"cohortId": str(cohort),
                                      "expectedPriceMinor": 750, "paymentMethod": "TEST_CARD"})
        sql(f"UPDATE marketplace.education_cohorts SET starts_at=now()-interval '1 minute' WHERE id='{cohort}';")
        teacher = fixture.session(INSTRUCTOR)
        roster = fixture.call("GET", f"executor/education/sessions/{cohort}/roster", token=teacher)
        assert any(row["id"] == enrollment["id"] for row in roster), "The fixture student is missing from the roster"
        launch_and_login("executor", "com.kunde.executor", INSTRUCTOR, "KUNDE Executor")
        mobile.tap("Мои занятия", "Сабақтарым", "My classes")
        mobile.reveal(TITLE)
        mobile.tap("Открыть список", "Тізімді ашу", "Open roster")
        android.find("Посещаемость", "Қатысу", "Attendance")
        mobile.tap(resource_id=f"education-attendance-present-{enrollment['id']}")
        for _ in range(15):
            result = fixture.call("GET", f"executor/education/sessions/{cohort}/roster", token=teacher)
            if any(row["id"] == enrollment["id"] and row["attendance"] == "PRESENT" for row in result):
                break
            time.sleep(1)
        else:
            raise RuntimeError("The Executor APK did not persist attendance")
        android.screenshot("02-executor-attendance")
        fixture.completed.append("executor_attendance")
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
