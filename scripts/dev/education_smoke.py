#!/usr/bin/env python3
"""Verify the synthetic Education flow against an authorized DEV or local backend."""
import argparse
import json
import urllib.error
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_url", help="DEV backend URL without /api/v1")
    parser.add_argument("phone", help="DEV OTP allowlisted synthetic phone in E.164 format")
    args = parser.parse_args()
    if not args.phone.startswith("+7700000"):
        parser.error("Use an allowlisted synthetic KUNDE DEV phone")

    def call(method, path, body=None, token=None, key=None, expected=(200,)):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if key:
            headers["Idempotency-Key"] = key
        req = urllib.request.Request(args.base_url.rstrip("/") + "/api/v1/" + path,
                                     None if body is None else json.dumps(body).encode(),
                                     headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=90) as response:
                status, data = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, data = error.code, error.read()
        if status not in expected:
            raise RuntimeError(f"{method} {path.split('?')[0]}: HTTP {status}, expected {expected}")
        return json.loads(data) if data else None

    assert call("GET", "capabilities")["educationEnabled"] is True
    python_course = next(course for course in call("GET", "education/courses?q=Python")["items"]
                         if course["synthetic"] and course["id"] == "a00ed000-0000-4000-8000-000000000101")
    course_id = python_course["id"]
    cohorts = call("GET", f"education/courses/{course_id}/cohorts")
    recorded = next(cohort for cohort in cohorts if cohort["format"] == "ONLINE_RECORDED")

    call("POST", "auth/otp/request", {"phone": args.phone}, expected=(202,))
    token = call("POST", "auth/otp/verify", {"phone": args.phone, "code": "123456"})["accessToken"]
    entries = call("GET", "education/enrollments", token=token)
    enrollment = next((entry for entry in entries if entry["courseId"] == course_id), None)
    if enrollment is None:
        body = {"cohortId": recorded["id"], "expectedPriceMinor": recorded["priceMinor"], "paymentMethod": "TEST_CARD"}
        key = uuid.uuid4().hex
        enrollment = call("POST", "education/enrollments", body, token, key, expected=(201,))
        replay = call("POST", "education/enrollments", body, token, key)
        assert replay["id"] == enrollment["id"]
    assert enrollment["paymentStatus"] == "TEST_CAPTURED"
    path = f"education/enrollments/{enrollment['id']}"
    learning = call("GET", path + "/learning", token=token)
    for lesson in learning["lessons"]:
        if not lesson["completed"]:
            call("PUT", f"{path}/lessons/{lesson['modulePosition']}/{lesson['lessonPosition']}/completion", token=token)
    result = call("GET", path + "/learning", token=token)
    if result.get("quiz") and not result["enrollment"]["certificateCode"]:
        choice = result["quiz"]["choices"].index("Перебирает значения")
        result = call("POST", path + "/quiz-attempts", {"requestId": str(uuid.uuid4()), "choice": choice}, token)
    assert result["enrollment"]["status"] == "COMPLETED"
    code = result["enrollment"]["certificateCode"]
    assert call("GET", f"education/certificates/{code}")["title"] == python_course["title"]
    print("SMOKE OK: synthetic cohort, TEST_CARD, private learning and completion verification")


if __name__ == "__main__":
    main()
