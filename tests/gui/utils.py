# Utilities for GUI smoke tests (headless Neutrino).

import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest


def require_binary(name: str) -> None:
    """Skip the test if the given binary is not available."""
    if shutil.which(name) is None:
        pytest.skip(f"{name} binary is required for this test")


def ensure_neutrino_running() -> None:
    """Skip if the Neutrino binary is not reachable."""
    install_dir = os.environ.get("NEUTRINO_INSTALL_DIR")
    prefix = os.environ.get("NEUTRINO_PREFIX", "/usr")
    candidate = Path(install_dir or "") / prefix.strip("/") / "bin" / "neutrino"
    if not candidate.exists():
        pytest.skip("Neutrino binary not installed – run `make neutrino` first")


def send_keys_skip_reason(stderr: str) -> str | None:
    """The reason to skip over, when send_keys failed for want of an
    environment rather than because the key transport is broken.

    An installed binary is not a running one: ensure_neutrino_running() only
    checks that Neutrino was built, so a suite started without `make run`
    reaches send_keys and dies there on a FIFO nobody reads. That is a missing
    precondition, not a defect, and it has to read like one - otherwise the
    first thing a newcomer sees is a CalledProcessError naming a subprocess.

    Returns None for anything unrecognised, so a genuine failure still raises.
    """
    known = (
        "has no reader",
        "not found. Ensure Neutrino is running",
        "is not a FIFO",
        "python-evdev missing",
    )
    for marker in known:
        if marker in stderr:
            return f"cannot replay keys: {stderr.strip().splitlines()[-1]}"
    return None


def capture_framebuffer(destination: Path, delay: float = 0.5) -> None:
    """Capture a framebuffer screenshot using fbgrab."""
    require_binary("fbgrab")
    # fbgrab being installed says nothing about there being something to grab:
    # a PC build renders into X (Xvfb), and such a host usually has no
    # framebuffer device at all. Without this check the test fails on a plain
    # environment mismatch instead of skipping like every other missing piece.
    # Same reading as fbgrab's own `device=${FRAMEBUFFER:-/dev/fb0}`: an empty
    # value falls back to the default rather than naming an empty path.
    device = os.environ.get("FRAMEBUFFER") or "/dev/fb0"
    if not os.access(device, os.R_OK):
        pytest.skip(f"no readable framebuffer at {device} – fbgrab cannot capture here")
    time.sleep(delay)
    subprocess.run(["fbgrab", str(destination)], check=True)


def capture_x11(destination: Path, delay: float = 0.5) -> None:
    """Capture the screen of a PC build, which renders into X rather than a
    framebuffer device.

    Separate from capture_framebuffer() on purpose: that one grabs /dev/fb0 and
    skips where there is none, which is exactly the PC-build case. A test that
    needs a picture from an Xvfb-hosted Neutrino has to come here instead.
    """
    require_binary("import")
    display = os.environ.get("DISPLAY")
    if not display:
        pytest.skip("DISPLAY not set - start Neutrino under Xvfb before running this test")
    time.sleep(delay)
    subprocess.run(["import", "-window", "root", str(destination)], check=True)


def images_differ(first: Path, second: Path) -> int:
    """Number of differing pixels between two screenshots.

    Uses ImageMagick's compare, which reports the count on stderr and exits
    non-zero whenever the images are not identical - that is a result here, not
    a failure, so the exit code is deliberately not checked.
    """
    require_binary("compare")
    proc = subprocess.run(
        ["compare", "-metric", "AE", str(first), str(second), "null:"],
        capture_output=True,
    )
    out = (proc.stderr or b"").decode(errors="ignore").strip().split()
    if not out:
        pytest.skip("compare produced no metric - cannot tell the screenshots apart")
    try:
        # some builds print "1234 (0.001)"
        return int(float(out[0]))
    except ValueError:
        pytest.skip(f"compare returned an unreadable metric: {out[0]!r}")


def ocr_image(path: Path) -> str:
    """Perform OCR on image using Tesseract, skip if binary missing."""
    require_binary("tesseract")
    require_module("pytesseract")
    require_module("cv2")

    import cv2  # pylint: disable=import-error
    import pytesseract  # pylint: disable=import-error

    image = cv2.imread(str(path))
    if image is None:
        pytest.skip(f"Failed to read screenshot at {path}")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    return pytesseract.image_to_string(gray)


def require_module(name: str) -> None:
    """Skip if the Python module is not installed."""
    try:
        __import__(name)
    except ImportError:
        pytest.skip(f"Python module '{name}' required for this test")
