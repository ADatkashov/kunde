"""Capture Android visual comparisons against the isolated CI backend."""

import capture_android_visual as visual
import rides_native_e2e as fixture


def main():
    process = fixture.start_backend(False)
    try:
        visual.adb("reverse", "tcp:8081", "tcp:8081")
        visual.main()
    finally:
        fixture.stop_backend(process)


if __name__ == "__main__":
    main()
