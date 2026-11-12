"""Black-box Android Consumer/browser session checks. Never emit raw UI or credentials."""
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET
import urllib.request
import urllib.parse

from native_identity_stack import docker
import native_browser

PACKAGE = "com.example.kunde_mobile"
APP = PACKAGE + "/.MainActivity"
SAFE_LABELS = {"Sign in", "Sign In", "Sign out", "Profile", "Home", "Edit profile", "Save changes",
               "Profile saved", "Try again", "Cannot connect. Check your connection and try again.",
               "Accept & continue", "Use without an account", "No thanks", "Continue", "Wait", "Close app",
               "Welcome to Chrome", "Make Chrome your own", "Sign in to your account", "Username or email",
               "Username", "Password", "Your connection is not private", "This site can’t be reached",
               "This site can't be reached", "Checking your session…", "Sign in did not complete. Try again."}
NOT_EXECUTED = ["native registration", "refresh replay capture", "provider outage", "session expiry",
                "iOS", "TalkBack", "large text", "full RU/KK profile journeys", "physical devices"]


def adb(*args):
    return subprocess.run(["adb", *args], check=True, capture_output=True, timeout=30).stdout


def hierarchy():
    # The dump can contain passwords/authorization URLs: keep it in memory and delete device copy.
    try:
        adb("shell", "uiautomator", "dump", "/data/local/tmp/kunde-e2e.xml")
        data = adb("exec-out", "cat", "/data/local/tmp/kunde-e2e.xml")
        return ET.fromstring(data)
    finally:
        adb("shell", "rm", "-f", "/data/local/tmp/kunde-e2e.xml")


def labels(node):
    values = []
    for key in ("text", "content-desc"):
        for line in node.get(key, "").splitlines():
            values.append(line.strip())
    return values


def matches(node, wanted):
    return any(value.casefold() == label.casefold() or value.casefold().startswith(label.casefold() + ", ")
               for value in labels(node) for label in wanted)


def center(node):
    parts = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if not parts:
        return None
    x1, y1, x2, y2 = map(int, parts.groups())
    return ((x1 + x2) // 2, (y1 + y2) // 2) if x2 > x1 and y2 > y1 else None


def find_label(tree, wanted, package=None):
    return next((n for n in tree.iter("node") if matches(n, wanted) and center(n)
                 and n.get("enabled", "true") == "true"
                 and (package is None or n.get("package") == package)), None)


def editable(tree, password=False):
    nodes = [n for n in tree.iter("node") if n.get("class", "").endswith("EditText") and center(n)
             and n.get("enabled", "true") == "true"
             and not any(x in n.get("resource-id", "") for x in ("url_bar", "search_box", "omnibox"))]
    chosen = [n for n in nodes if (n.get("password") == "true") == password]
    if len(chosen) != 1:
        return None
    return chosen[0]


def safe_diagnostics(tree):
    nodes = list(tree.iter("node"))
    return {"nodeCount": len(nodes),
            "editableCount": sum(n.get("class", "").endswith("EditText") for n in nodes),
            "safeVisibleLabels": sorted({v for n in nodes for v in labels(n) if v in SAFE_LABELS}),
            "packages": sorted({n.get("package") for n in nodes if n.get("package") in
                                {PACKAGE, "com.android.chrome", "android", "com.android.systemui", "com.google.android.gms"}}),
            "resourceIds": sorted({n.get("resource-id") for n in nodes if re.fullmatch(
                r"(?:com\.android\.chrome|android):id/[a-zA-Z0-9_]+|username|password|kc-login", n.get("resource-id", ""))})}



def network_diagnostics():
    # Fixed loopback probes only. Raw command output and browser URLs never escape.
    result = {}
    for port, path in ((8180, "/realms/kunde-consumer-check/.well-known/openid-configuration"),
                       (8081, "/actuator/health")):
        request = f"GET {path} HTTP/1.0\r\nHost: localhost:{port}\r\n\r\n"
        script = "{ printf '" + request.replace("\r", "\\r").replace("\n", "\\n") + "'; sleep 1; } | toybox nc -w 5 127.0.0.1 " + str(port)
        try:
            probe = subprocess.run(["adb", "shell", script], capture_output=True, timeout=10)
            match = re.search(rb"HTTP/\d\.\d (\d{3})", probe.stdout)
            result[str(port)] = {"exitCode": probe.returncode, "httpStatus": int(match[1]) if match else None,
                                 "ncUnsupported": b"Unknown command" in probe.stderr or b"Unknown option" in probe.stderr}
        except subprocess.TimeoutExpired:
            result[str(port)] = {"timeout": True}
    try:
        log = adb("logcat", "-d", "-s", "chromium:I").decode(errors="replace")
        result["chromeNetErrors"] = sorted(set(re.findall(r"net::ERR_[A-Z_]+", log)))
        adb("forward", "tcp:19222", "localabstract:chrome_devtools_remote")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open("http://127.0.0.1:19222/json/list", timeout=3) as response:
            targets = json.load(response)
        try:
            result["browserDOM"] = native_browser.page_state()
        except Exception as error:
            result["browserDOMError"] = type(error).__name__
        result["chromePages"] = [{"type": t.get("type") if t.get("type") in {"page", "other", "background_page"} else "unknown",
                                  "location": "fixture" if urllib.parse.urlparse(t.get("url", "")).hostname == "localhost"
                                  else "chrome_error" if t.get("url", "").startswith("chrome-error:") else "other"}
                                 for t in targets]
    except Exception as error:
        result["chromeDiagnosticsError"] = type(error).__name__
    return result


class Scenario:
    def __init__(self, state):
        self.state = state
        self.stage = "setup"
        self.completed = []
        self.last_tree = None

    def wait(self, predicate, seconds=60):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                self.last_tree = hierarchy()
                value = predicate(self.last_tree)
                if value is not None and value is not False:
                    return value
            except (ET.ParseError, subprocess.CalledProcessError):
                pass
            time.sleep(1)
        raise TimeoutError("Native UI stage did not complete")

    def tap(self, node):
        x, y = center(node)
        adb("shell", "input", "tap", str(x), str(y))

    def tap_label(self, *wanted, package=None):
        self.tap(self.wait(lambda tree: find_label(tree, wanted, package)))

    def app_label(self, label):
        return self.wait(lambda tree: find_label(tree, [label], PACKAGE))

    def hide_keyboard(self):
        status = adb("shell", "dumpsys", "input_method").decode(errors="replace")
        if re.search(r"(?:mInputShown|isInputViewShown|mIsInputViewShown)=true", status):
            adb("shell", "input", "keyevent", "4")

    def enter(self, node, value):
        if not re.fullmatch(r"[A-Za-z0-9-]+", value):
            raise ValueError("Only synthetic ASCII input is supported")
        self.tap(node)
        adb("shell", "input", "keyevent", "123", *(["67"] * 90))
        adb("shell", "input", "text", value)
        self.hide_keyboard()

    def launch(self):
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", APP)

    def profile(self):
        self.app_label("Profile")
        self.tap_label("Profile", package=PACKAGE)
        self.app_label("Edit profile")

    def db_profile(self):
        # Inputs are generated UUID/constant issuer; no arbitrary user SQL or tokens.
        subject = self.state["subject"]
        if not re.fullmatch(r"[a-f0-9-]{36}", subject):
            raise ValueError("Unexpected synthetic subject")
        query = ("SELECT json_build_object('id',p.user_id,'name',p.display_name,'language',p.preferred_language,"
                 "'version',p.version) FROM profile.consumer_profiles p JOIN identity.external_bindings b "
                 "ON b.user_id=p.user_id WHERE b.issuer='http://localhost:8180/realms/kunde-consumer-check' "
                 "AND b.subject='" + subject + "'")
        rows = docker("exec", self.state["marker"] + "-db", "psql", "-U", "kunde_ci", "-d", "kunde",
                      "-Atq", "-c", query).splitlines()
        if len(rows) != 1:
            raise AssertionError("Expected one canonical synthetic identity")
        return json.loads(rows[0])

    def login_form(self):
        adb("forward", "tcp:19222", "localabstract:chrome_devtools_remote")
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                if native_browser.form_present():
                    return
            except Exception:
                pass  # Details may include authorization URLs. Report only safe diagnostics.
            time.sleep(1)
        raise TimeoutError("Fixture credential form unavailable in Chrome")

    def login(self):
        self.login_form()
        native_browser.submit(self.state["username"], self.state["password"])
        self.app_label("Profile")

    def run(self):
        self.stage = "chrome_setup"
        if adb("shell", "getprop", "ro.kernel.qemu").strip() != b"1":
            raise ValueError("Only an isolated Android emulator is allowed")
        adb("shell", "pm", "path", "com.android.chrome")
        adb("shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1")
        adb("shell", "cmd", "role", "add-role-holder", "android.app.role.BROWSER", "com.android.chrome")
        # Fresh emulator only; no user browser/profile is touched.
        adb("shell", "am", "set-debug-app", "--persistent", "com.android.chrome")
        adb("shell", "echo 'chrome --no-first-run --disable-fre --no-default-browser-check --force-renderer-accessibility' > /data/local/tmp/chrome-command-line")
        adb("shell", "am", "force-stop", "com.android.chrome")
        adb("reverse", "tcp:8180", "tcp:8180")
        adb("reverse", "tcp:8081", "tcp:8081")
        adb("install", "-r", "mobile/build/app/outputs/flutter-apk/app-debug.apk")
        adb("shell", "pm", "clear", PACKAGE)
        self.launch()
        self.stage = "welcome_locales"
        self.wait(lambda tree: find_label(tree, ["Sign in", "Войти", "Кіру"], PACKAGE))
        for language, login in (("Русский", "Войти"), ("Қазақша", "Кіру"), ("English", "Sign in")):
            self.tap_label("App language", "Язык приложения", "Қолданба тілі", package=PACKAGE)
            self.tap_label(language, package=PACKAGE)
            self.app_label(login)
        self.completed.append("native RU/KK/EN welcome labels")
        self.stage = "system_browser_pkce_login"
        self.tap_label("Sign in", package=PACKAGE)
        self.login()
        original = self.db_profile()
        if original["id"] == self.state["subject"]:
            raise AssertionError("Canonical UUID must not equal IdP subject")
        self.completed.append("system-browser login and native PKCE callback to verified API")
        self.stage = "profile_edit"
        self.profile()
        self.tap_label("Edit profile", package=PACKAGE)
        self.enter(self.wait(lambda tree: editable(tree)), "NativeValidated")
        self.tap_label("English", package=PACKAGE)
        self.tap_label("Save changes", package=PACKAGE)
        self.app_label("Profile saved")
        saved = self.db_profile()
        if saved["id"] != original["id"] or saved["name"] != "NativeValidated" or saved["language"] != "en":
            raise AssertionError("Native profile edit did not persist")
        # Capture only the verified application screen, never browser/credential forms.
        self.app_label("NativeValidated")
        self.wait(lambda tree: True if {n.get("package") for n in tree.iter("node") if n.get("package")}
                  <= {PACKAGE, "com.android.systemui"} else None)
        Path("reports/native-profile.png").write_bytes(adb("exec-out", "screencap", "-p"))
        self.completed.append("native profile edit persisted to same canonical account")
        self.stage = "secure_vault_refresh_restore"
        for _ in range(2):
            self.launch()
            self.profile()
            self.app_label("NativeValidated")
            if self.db_profile() != saved:
                raise AssertionError("Restart changed canonical profile")
        self.completed.append("two process restarts with secure-vault restore and rotated refresh persistence")
        self.stage = "api_offline_retry"
        adb("reverse", "--remove", "tcp:8081")
        self.launch()
        self.app_label("Cannot connect. Check your connection and try again.")
        adb("reverse", "tcp:8081", "tcp:8081")
        self.tap_label("Try again", package=PACKAGE)
        self.profile()
        self.app_label("NativeValidated")
        self.completed.append("native API offline state and retry without account loss")
        self.stage = "provider_logout_relogin"
        self.tap_label("Sign out", package=PACKAGE)
        self.app_label("Sign in")
        self.tap_label("Sign in", package=PACKAGE)
        self.login_form()  # A still-active browser SSO session would return directly to the app and fail this check.
        self.login()
        self.profile()
        self.app_label("NativeValidated")
        if self.db_profile() != saved:
            raise AssertionError("Logout/relogin changed canonical profile")
        self.completed.append("provider logout, subsequent credential form and same-account relogin")


def main():
    Path("reports").mkdir(exist_ok=True)
    state = json.loads((Path(os.environ["KUNDE_NATIVE_DIR"]) / "fixture.json").read_text())
    scenario = Scenario(state)
    result = {"status": "FAILED", "nativeE2E": "NOT_EXECUTED", "completed": scenario.completed,
              "notExecuted": NOT_EXECUTED, "productionReadiness": "NOT_APPROVED"}
    try:
        scenario.run()
        result["status"] = "PASSED_EXECUTED_SCENARIOS"
    except Exception as error:
        result.update(stage=scenario.stage, errorClass=type(error).__name__)
        result["networkDiagnostics"] = network_diagnostics()
        if scenario.last_tree is not None:
            result["diagnostics"] = safe_diagnostics(scenario.last_tree)
    if scenario.completed:
        result["nativeE2E"] = "EXECUTED_PARTIAL"
    Path("reports/e2e-status.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("Consumer native scenario: **" + result["status"] + "**. TASK-006 remains in_progress.\n")
    return 0 if result["status"] == "PASSED_EXECUTED_SCENARIOS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
