"""Capture actual KUNDE debug APKs on a fresh Android Actions emulator."""

import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "com.example.kunde_mobile"
APKS = Path(os.environ["RUNNER_TEMP"]) / "visual-apk"
REPORT = Path("reports/visual")


def adb(*args):
    return subprocess.check_output(["adb", *map(str, args)], timeout=30)


def find(*labels, node_class=None, clickable=False, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            adb("shell", "uiautomator", "dump", "/sdcard/kunde-visual.xml")
            tree = ET.fromstring(adb("exec-out", "cat", "/sdcard/kunde-visual.xml"))
        except (subprocess.SubprocessError, ET.ParseError):
            continue
        for node in tree.iter("node"):
            if node.get("package") != PACKAGE:
                continue
            text = {node.get("text", ""), *node.get("content-desc", "").splitlines()}
            if labels and not any(
                value == label or value.startswith(f"{label},")
                for label in labels for value in text
            ):
                continue
            if node_class and node.get("class") != node_class:
                continue
            if clickable and node.get("clickable") != "true":
                continue
            bounds = [int(x) for x in re.findall(r"\d+", node.get("bounds", ""))]
            if len(bounds) == 4:
                x1, y1, x2, y2 = bounds
                if x2 > x1 and y2 > y1:
                    return (x1 + x2) // 2, (y1 + y2) // 2
    raise RuntimeError(f"Could not locate UI element {labels or node_class}")


def tap(*labels, **options):
    adb("shell", "input", "tap", *find(*labels, **options))


def screenshot(name):
    time.sleep(1)
    png = adb("exec-out", "screencap", "-p")
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("adb did not return a PNG")
    (REPORT / f"{name}.png").write_bytes(png)


def launch(version):
    adb("shell", "am", "force-stop", PACKAGE)
    adb("install", "-r", APKS / f"{version}.apk")
    adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")


def home():
    find("Алматы", "Almaty", timeout=120)


def feed(version):
    home()
    find("Продукты", "Азық-түлік", "Groceries", timeout=120)
    screenshot(f"{version}-home")
    # The visible coordinates refer to the fixed emulator dimensions below.
    for _ in range(2):
        adb("shell", "input", "swipe", 180, 690, 180, 330, 350)
        time.sleep(.4)
    screenshot(f"{version}-feed")


def capture_tabs(version):
    tap("Поиск", "Каталог", "Search", clickable=True)
    find(node_class="android.widget.EditText", timeout=120)
    screenshot(f"{version}-catalog")

    tap("Заказы", "Orders", clickable=True)
    find("Мои заказы", "My orders", "Заказов пока нет", "No orders yet", timeout=120)
    screenshot(f"{version}-orders")

    tap("Профиль", "Profile", clickable=True)
    find("Тема", "Appearance", "Тақырып")
    screenshot(f"{version}-profile")

    tap("Главная", "Home", "Басты бет", clickable=True)
    home()
    try:
        tap("AI", clickable=True, timeout=5)
        assistant_is_tab = True
    except RuntimeError:
        tap("KUNDE AI")
        assistant_is_tab = False
    find("Скоро", "Soon", "Жақында")
    screenshot(f"{version}-assistant")
    if not assistant_is_tab:
        adb("shell", "input", "keyevent", 4)
    tap("Главная", "Home", "Басты бет", clickable=True)


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    adb("shell", "wm", "size", "390x844")
    adb("shell", "wm", "density", "160")
    launch("before")
    tap(node_class="android.widget.EditText")
    adb("shell", "input", "text", "7000000001")
    adb("shell", "input", "keyevent", 4)
    tap("Получить код", "Get code", "Код алу")
    find("Введите код", "Enter the code", "Кодты енгізіңіз", timeout=120)
    adb("shell", "input", "text", "123456")
    home()
    tap("Профиль", "Profile", clickable=True)
    tap("Язык приложения", "App language", "Қолданба тілі", clickable=True)
    tap("Русский")
    tap("Главная", "Home", "Басты бет", clickable=True)
    feed("before")
    capture_tabs("before")

    launch("after")
    feed("after")
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")
    home()
    capture_tabs("after")
    tap("Профиль", "Profile", clickable=True)
    tap("Тема", "Appearance", "Тақырып")
    tap("Главная", "Home", "Басты бет", clickable=True)
    home()
    screenshot("after-dark")
    adb("shell", "wm", "size", "320x640")
    home()
    screenshot("after-dark-small")
    for lang, menu_label, grid_label in [
        ("kk", "Қазақша", "Азық-түлік"),
        ("en", "English", "Groceries"),
        ("ru", "Русский", "Продукты"),
    ]:
        tap("Профиль", "Profile", clickable=True)
        tap("Язык приложения", "App language", "Қолданба тілі", clickable=True)
        tap(menu_label)
        tap("Главная", "Home", "Басты бет", clickable=True)
        find(grid_label)
        screenshot(f"after-dark-small-{lang}")
    log = adb("logcat", "-d", "-s", "flutter")
    if b"A RenderFlex overflowed" in log:
        raise RuntimeError("Flutter reported a RenderFlex overflow")


if __name__ == "__main__":
    main()
