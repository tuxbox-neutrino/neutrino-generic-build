# Smoke test that drives the main menu and verifies it via OCR.

import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

from . import utils


@pytest.mark.gui
def test_main_menu_title(tmp_path: Path) -> None:
    utils.ensure_neutrino_running()
    if "DISPLAY" not in os.environ:
        pytest.skip("DISPLAY not set – run `make run` before executing GUI tests")

    screenshot = tmp_path / "screen.png"

    try:
        subprocess.run(
            [sys.executable, "-m", "tests.gui.send_keys"],
            check=True,
            capture_output=True,
        )
    except FileNotFoundError:
        pytest.skip("python3 not available to replay keys")
    except subprocess.CalledProcessError as exc:
        err = (exc.stderr or b"").decode(errors="ignore")
        if "cannot be opened for writing" in err or "Permission denied" in err:
            pytest.skip("uinput device not writable - run as root or load uinput")
        if "FIFO '/tmp/neutrino.input' not found" in err:
            pytest.skip("Neutrino FIFO missing – start Neutrino (make run / run-now) before running GUI tests")
        raise
    except SystemExit as exc:  # send_keys handles missing evdev
        pytest.skip(str(exc))

    time.sleep(1)
    utils.capture_framebuffer(screenshot)

    text = utils.ocr_image(screenshot)
    assert text.strip(), "OCR returned empty string"
    assert any(
        needle in text.lower()
        for needle in ("main menu", "hauptmen", "haupt-menü")
    ), f"Expected menu title not found in OCR text: {text!r}"
