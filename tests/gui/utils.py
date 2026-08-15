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


def capture_framebuffer(destination: Path, delay: float = 0.5) -> None:
    """Capture a framebuffer screenshot using fbgrab."""
    require_binary("fbgrab")
    time.sleep(delay)
    subprocess.run(["fbgrab", str(destination)], check=True)


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
