# Testing

## Quick Navigation

- [Project Overview](README.en.md)
- [Quickstart](QUICKSTART.en.md)
- [Testing Guide](TESTING.en.md) *(this page)*
- [Packaging Guide](PACKAGING.en.md)
- [Hardware Notes](HARDWARE.en.md)
- Prefer German? Head over to [TESTING.de.md](TESTING.de.md)

## Overview

The Make targets focus on three layers:

- `make test-gui`: drive the Neutrino UI through `uinput`/`evdev`, validate via OCR.
- `make test-web`: Playwright smoke tests for the web interface (requires `NEUTRINO_WEB_BASE_URL`).
- `make test-hw`: Optional hardware scan (DVB/V4L2/Input).

`make test` runs the shell, GUI and web suites in that order. Only `make test-shell` is free of prerequisites.

## Prerequisites

- A running Neutrino instance (`make run` in a separate shell, **as your normal user** — see "Running the suites" below). `run` uses the host wrapper by default; use `make run-nspawn` only if you want systemd-nspawn/proot isolation.
- Helper tools installed: `fbgrab` plus a PNM→PNG converter (`netpbm` or GraphicsMagick/ImageMagick), `tesseract`, `evtest`, plus Python modules `opencv-python-headless`, `pytesseract`, `evdev`.
- `systemd-nspawn` is **not** needed for `make run`, which is the plain host wrapper. Install it (Debian/Ubuntu: `sudo apt-get install systemd-container`) only if you want the isolated `make run-nspawn` variant.
- Run `make deps` once so the Python virtualenv contains `pytest` and friends. The GUI suite refuses to run if `pytest` is missing.
- Optional: load the Linux `uinput` module when you want tests to inject keys via evdev. Without `/dev/uinput` the helper falls back to the Neutrino FIFO (`/tmp/neutrino.input`).

Quick host install (apt/dnf):

```bash
sudo ./scripts/setup_deps.sh --mode=auto
```

The script installs system packages (`tesseract`, `fbcat`, `xvfb`, `netpbm`, `evtest`) and prepares the Python virtualenv with `pytest`, `opencv-python-headless`, `pytesseract`, `evdev`. On Debian/Ubuntu/Fedora there is no `uinput` package—load the kernel module via `sudo modprobe uinput` and ensure your user can write to `/dev/uinput` (group `input` or run tests with `sudo`).

Example (Debian 12) to satisfy runtime libraries:

```bash
sudo apt-get install -y \
  libavcodec59 libavformat59 libavutil57 libswscale6 libswresample4 \
  libjpeg62-turbo freeglut3
```

### Environment variables worth knowing

| Variable | Default | Purpose |
| --- | --- | --- |
| `NEUTRINO_WEB_BASE_URL` | — | Target URL for Playwright. Point it at the web UI of your running Neutrino instance (e.g. `http://localhost:31344`). |
| `TEST_ARTIFACT_DIR` | `artifacts/tests` | Root folder used for screenshots, logs, and Playwright reports. |
| `PLAYWRIGHT_BIN` | `npx` | Command used to launch Playwright (`npx playwright …`). Override if Playwright is installed globally. |
| `ALLOW_NON_ROOT` | `0` | When set to `1`, skips the root check for GUI tests—useful for simulated environments without real devices. |
| `RUN_NEUTRINO_DISPLAY` | host `DISPLAY` (fallback `:99`) | DISPLAY used by `make run`; defaults to the host X server when present, otherwise a headless `:99`. |

Pass overrides inline to `make`, for example:

```bash
NEUTRINO_WEB_BASE_URL=http://localhost:31344 \
TEST_ARTIFACT_DIR=$PWD/out/tests \
make test-web
```

## Running the suites

1. Build and install Neutrino (`make neutrino`) if you have not already.
2. Start the runtime in a separate shell, **as your normal user**:
   ```bash
   make run
   ```
   Keep this process running while the tests execute. Do not put `sudo` in
   front of `make`: the run targets rebuild and re-stage first, so root would
   leave root-owned files in `.venv/` and `artifacts/` and break later builds.
   Root is only needed to reach real DVB devices — see
   [Hardware Notes](HARDWARE.en.md).
3. In another terminal run the desired target:
   - GUI only: `make test-gui`
   - Web only: `NEUTRINO_WEB_BASE_URL=http://localhost:31344 make test-web`
   - Hardware scan: `make test-hw` (enumerates devices only; no root needed)
   - Full suite: `make test`

Artifacts will be placed under `artifacts/tests/` unless you changed `TEST_ARTIFACT_DIR`.

## Artifacts

Test output lives under `artifacts/tests/`:

- `gui/` stores screenshots and logs.
- `web/` stores Playwright reports.

These are local artifacts. CI does **not** produce them: the workflow runs the
shell suite and the dependency preflight, never the GUI or web suites, and it
uploads only the dependency-doctor output plus build logs on failure.

## Adding GUI tests

1. Create a new test in `tests/gui/` using pytest conventions.
2. Reuse helpers from `tests/gui/utils.py` for OCR or screenshots.
3. Extend key sequences via `tests/gui/send_keys.py` or additional helpers.
4. Place golden images in `tests/gui/golden/` (create on demand) and compare in your test.

## Adding web tests

1. Add a Playwright spec under `tests/web/`.
2. Update `tests/web/package.json` if new npm packages are required.
3. Run locally with `NEUTRINO_WEB_BASE_URL=http://localhost:31344 npx playwright test`.

## Troubleshooting

- **`DISPLAY not set`**: Headless server not running. Start `make run` again.
- **`python-evdev missing`**: Rerun `make deps` or install the module manually.
- **Tesseract OCR returns empty text**: Validate that `fbgrab` produced a valid screenshot (open the file).
- **Playwright cannot reach the target**: Ensure `NEUTRINO_WEB_BASE_URL` resolves from the test environment and that the port is reachable.

See `docs/HARDWARE.en.md` for hardware-centric tips.
