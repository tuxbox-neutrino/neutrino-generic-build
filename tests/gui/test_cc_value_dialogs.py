# Regression tests for the cc input dialogs that replaced the old fixed-cell
# input windows: the numeric dialog (string inputs, int inputs, number
# choosers), the PIN dialog (PIN prompts, CI enquiries) and the structured
# dialog (IP/MAC addresses, dates, times, weekdays, coordinates).
#
# Each test opens one of the demo entries at the end of the test menu's
# OSD-Components Demo, types on the remote, and reads what the demo shows
# afterwards: every demo answers a saved value with a message box naming
# it, which OCR reads back. A refused value keeps the dialog open with the
# reason on its hint line instead, which OCR reads as well.
#
# Navigation as in test_input_dialog.py: PAGEUP pins a menu to its first
# entry (it does not wrap), and from there the steps are fixed. The demo
# entries sit at the end of their list, which UP reaches by wrapping from
# the first entry - so they do not shift the steps the older tests count.
#
# The PC build without tuners raises "Kanal (zur Zeit) nicht verfuegbar"
# boxes on its own, and a key that meets one is gone: the rest of the walk
# then lands on live TV, where DOWN zaps and OK opens the channel list. So
# every walk proves its arrival - each demo's hint names it - and starts
# over when it did not get there.

import subprocess
import sys
import time
from pathlib import Path

import pytest

from . import utils

SETTLE = 1.3

# Steps UP from the first entry of the OSD-Components Demo, which wraps to
# the last entry; the demo list ends with these, in this order.
DECIMAL, WEEKDAYS, TIME, DATETIME, MAC, IP, PIN, NUMBER_STRING, NUMBER_SIGNED, NUMBER = range(1, 11)

# Where the result box of a demo and the hint line of an open dialog are
# drawn on the 1280x720 screen.
RESULT_BOX = (300, 110, 680, 220)
DIALOG_HINT = (230, 270, 820, 90)


def _send(*keys: str) -> None:
    try:
        subprocess.run(
            [sys.executable, "-m", "tests.gui.send_keys", *keys],
            check=True,
            capture_output=True,
        )
    except FileNotFoundError:
        pytest.skip("python3 not available to replay keys")
    except subprocess.CalledProcessError as exc:
        utils.fail_or_skip(exc)
    except SystemExit as exc:
        pytest.skip(str(exc))
    time.sleep(SETTLE)


def _require_gui() -> None:
    utils.ensure_neutrino_running()
    utils.require_binary("tesseract")


def _walk_to_demo(tmp_path: Path, steps_up: int) -> None:
    """Ground state, main menu -> Test menu (8 down) -> OSD-Components Demo
    (5 down) -> the entry steps_up from the end."""
    _send("HOME")
    _send("HOME")
    utils.wait_until_static(tmp_path)
    _send("MENU")
    utils.wait_until_static(tmp_path)
    _send(*(["PAGEUP"] * 5))
    for _ in range(2):
        _send(*(["DOWN"] * 4))
    _send("OK")
    utils.wait_until_static(tmp_path)
    _send(*(["PAGEUP"] * 5))
    _send(*(["DOWN"] * 5))
    _send("OK")
    utils.wait_until_static(tmp_path)
    _send(*(["PAGEUP"] * 5))
    _send(*(["UP"] * steps_up))
    _send("OK")
    utils.wait_until_static(tmp_path)


def _read(tmp_path: Path, region: tuple[int, int, int, int], tag: str) -> str:
    """OCR of a result box: white text on blue, which plain grey reads."""
    shot = tmp_path / f"{tag}.png"
    utils.capture_x11(shot)
    return utils.ocr_image(utils.crop_region(shot, region, f"_{tag}", scale=3))


def _read_hint(tmp_path: Path, tag: str) -> str:
    """OCR of a dialog's hint line. The red channel, thresholded: a refusal
    is red on the dark dialog body, which plain grey turns into two shades
    tesseract cannot tell apart, while the white hint stays bright in the
    red channel as well. Not for the result boxes: there the threshold
    turned a 2 into a 9."""
    region = DIALOG_HINT
    utils.require_module("cv2")
    utils.require_module("pytesseract")
    import cv2  # pylint: disable=import-error
    import pytesseract  # pylint: disable=import-error

    shot = tmp_path / f"{tag}.png"
    utils.capture_x11(shot)
    crop = utils.crop_region(shot, region, f"_{tag}", scale=3)
    image = cv2.imread(str(crop))
    if image is None:
        pytest.skip(f"Failed to read screenshot at {crop}")
    _, ink = cv2.threshold(image[:, :, 2], 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return pytesseract.image_to_string(cv2.bitwise_not(ink))


def _open_demo(tmp_path: Path, steps_up: int, token: str) -> None:
    """Walk to a demo until its hint, which contains token, is on screen."""
    for attempt in range(3):
        _walk_to_demo(tmp_path, steps_up)
        if token.lower() in _read_hint(tmp_path, f"arrive_{steps_up}_{attempt}").lower():
            return
        # Wherever the walk ended - a channel list, an error box, a menu,
        # an unedited dialog - HOME takes it down.
        _send("HOME")
        _send("HOME")
        _send("HOME")
    pytest.fail(f"the demo with '{token}' in its hint never opened")


def _leave_edited_dialog() -> None:
    """EXIT asks whether to discard; OK discards, HOME closes the menus."""
    _send("EXIT")
    _send("OK")
    _send("HOME", "HOME")


@pytest.mark.gui
def test_numeric_first_digit_replaces_and_range_refuses(tmp_path: Path) -> None:
    _require_gui()

    # The value opens marked: the first digit replaces it as a whole.
    _open_demo(tmp_path, NUMBER, "Ziffer")
    _send("5", "7", "OK")
    saved = _read(tmp_path, RESULT_BOX, "number_saved")
    _send("OK")
    assert '"57"' in saved or "57" in saved.split(), saved

    # 0 is outside 1-999: refused with the range on the hint line, the
    # dialog stays open.
    _open_demo(tmp_path, NUMBER, "Ziffer")
    _send("0", "OK")
    hint = _read_hint(tmp_path, "number_range")
    _leave_edited_dialog()
    assert "999" in hint, hint


@pytest.mark.gui
def test_pin_closes_on_its_last_digit_and_back_keeps_it_empty(tmp_path: Path) -> None:
    _require_gui()

    _open_demo(tmp_path, PIN, "vierte")
    # No 4: the thresholded OCR reads it as an A in this font.
    _send("2", "5", "8", "0")
    saved = _read(tmp_path, RESULT_BOX, "pin_saved")
    _send("OK")
    assert "2580" in saved and "Nicht" not in saved, saved

    _open_demo(tmp_path, PIN, "vierte")
    _send("1", "2", "HOME")
    cancelled = _read(tmp_path, RESULT_BOX, "pin_cancelled")
    _send("OK", "HOME", "HOME")
    assert "Nicht gespeichert" in cancelled and "12" not in cancelled, cancelled


@pytest.mark.gui
def test_ip_takes_twelve_digits_and_refuses_an_octet_over_255(tmp_path: Path) -> None:
    _require_gui()

    _open_demo(tmp_path, IP, "Zwoelf")
    _send("0", "1", "0", "0", "0", "0")
    _send("0", "0", "0", "0", "0", "7", "OK")
    saved = _read(tmp_path, RESULT_BOX, "ip_saved")
    _send("OK")
    assert "10.0.0.7" in saved, saved

    _open_demo(tmp_path, IP, "Zwoelf")
    _send("3", "OK")
    hint = _read_hint(tmp_path, "ip_range")
    _leave_edited_dialog()
    assert "255" in hint, hint


@pytest.mark.gui
def test_date_refuses_a_day_that_does_not_exist(tmp_path: Path) -> None:
    _require_gui()

    _open_demo(tmp_path, DATETIME, "Stelle")
    _send("3", "1", "0", "2", "2", "0", "3", "0", "OK")
    hint = _read_hint(tmp_path, "date_invalid")
    _leave_edited_dialog()
    assert "Datum" in hint, hint
