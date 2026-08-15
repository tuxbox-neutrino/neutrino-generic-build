# Emit remote control keys using Linux uinput/evdev.

import os
import stat
import time
from typing import Iterable, List

try:
    from evdev import UInput, ecodes as e  # type: ignore
except ImportError:  # pragma: no cover - runtime skip
    UInput = None  # type: ignore
    e = None


KEYS = {
    "UP": "KEY_UP",
    "DOWN": "KEY_DOWN",
    "LEFT": "KEY_LEFT",
    "RIGHT": "KEY_RIGHT",
    "OK": "KEY_OK",
    "BACK": "KEY_BACK",
    "MENU": "KEY_MENU",
}


def uinput_available() -> bool:
    if UInput is None or e is None:
        return False
    try:
        st = os.stat("/dev/uinput")
    except FileNotFoundError:
        return False
    if not stat.S_ISCHR(st.st_mode):
        return False
    # Fallback to FIFO if the device exists but is not writable (common without root/input group).
    return os.access("/dev/uinput", os.W_OK)


def tap(ui: "UInput", code: int, hold: float = 0.03, pause: float = 0.05) -> None:
    ui.write(e.EV_KEY, code, 1)
    ui.write(e.EV_SYN, e.SYN_REPORT, 0)
    time.sleep(hold)
    ui.write(e.EV_KEY, code, 0)
    ui.write(e.EV_SYN, e.SYN_REPORT, 0)
    time.sleep(pause)


def replay_uinput(keys: List[str]) -> None:
    if UInput is None or e is None:  # pragma: no cover - sanity guard
        raise SystemExit("python-evdev missing. Install via 'pip install evdev'.")
    with UInput() as ui:
        for key_name in keys:
            code = getattr(e, key_name)
            tap(ui, code)


def replay_fifo(keys: List[str]) -> None:
    fifo_path = os.environ.get("NEUTRINO_INPUT_FIFO", "/tmp/neutrino.input")
    if not os.path.exists(fifo_path):
        raise SystemExit(
            f"FIFO '{fifo_path}' not found. Ensure Neutrino is running (make run / run-now) or set NEUTRINO_INPUT_FIFO."
        )
    with open(fifo_path, "w", buffering=1) as fifo:
        for key_name in keys:
            fifo.write(f"{key_name}\n")
            fifo.flush()
            time.sleep(0.05)


def replay(keys: Iterable[str]) -> None:
    normalised: List[str] = []
    for name in keys:
        key = KEYS.get(name.upper())
        if key is None:
            raise ValueError(f"Unknown key: {name}")
        normalised.append(key)

    if uinput_available():
        replay_uinput(normalised)
    else:
        replay_fifo(normalised)


if __name__ == "__main__":
    replay(["MENU", "DOWN", "OK"])
