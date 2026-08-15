# Packaging

## Quick Navigation

- [Project Overview](README.en.md)
- [Quickstart](QUICKSTART.en.md)
- [Testing Guide](TESTING.en.md)
- [Packaging Guide](PACKAGING.en.md) *(this page)*
- [Hardware Notes](HARDWARE.en.md)
- Prefer German? See [PACKAGING.de.md](PACKAGING.de.md)

This setup produces three distribution formats:

1. **AppImage (`make package-appimage`)**
   - Builds Neutrino a second time and packs the result together with its data.
   - Runs without root. Root is needed for DVB and input devices, and for the
     web interface: it is configured for port 80, which an unprivileged process
     may not bind. Without root Neutrino falls back to 8080 and gives up if that
     is taken too; change `WebsiteMain.port` in the per-user `nhttpd.conf` after
     the first start to pick a port of your own.
   - Verify the result with `make package-appimage-verify` (see below).

   **Why a second build.** Neutrino learns its data directories at configure
   time: `acinclude.m4` turns every `--with-*dir` into a string literal in
   `config.h`, so the path a build was configured with is the only path the
   binary will ever look at. A package made from the developer tree therefore
   searches for its icons, locales and webroot underneath the directory *you*
   built in, which exists on no other machine.

   The AppImage build is consequently configured against a neutral prefix
   (`/opt/neutrino`, override with `APPIMAGE_RUNTIME_PREFIX`) and gets its own
   build and staging directories, so it never overwrites the binary your
   `make run` uses. Dependencies that do not depend on that prefix —
   libstb-hal, libdvbsi++, ffmpeg, lua — are reused from `artifacts/sysroot`
   instead of being rebuilt.

   **How the data is found at runtime.** The generated `AppRun` maps the
   bundled tree onto `/opt/neutrino` inside a private mount namespace, so
   nothing is written to your filesystem and the mapping disappears with the
   process. Two mounts, because Neutrino writes below the same prefix:

   | | source | mounted at | mode |
   |---|---|---|---|
   | data | the AppImage | `/opt/neutrino` as a whole | read-only |
   | state | `${XDG_DATA_HOME:-~/.local/share}/neutrino-appimage` | `/opt/neutrino/usr/var` | writable, seeded on first run |

   Point `NEUTRINO_APPIMAGE_STATE` somewhere else to keep several
   configurations apart, or to start from scratch.

   `AppRun` needs a private mount namespace and tries three ways to get one:
   as root directly, otherwise through unprivileged user namespaces, otherwise
   through `bwrap` (package `bubblewrap`, which helps on Ubuntu 24.04 where
   AppArmor restricts user namespaces). If none works it says so instead of
   starting without a user interface. Container runtimes block all three;
   Docker needs `--privileged`, being root inside the container is not enough.

   This mapping is a bridge, not a destination. It disappears once Neutrino
   resolves its data paths at runtime rather than baking them in.

   **Tooling.** `scripts/ensure_appimagetool.sh` provisions three artefacts
   into `tools/`, each pinned to a tagged release and verified against a
   recorded SHA-256:

   | artefact | what for |
   |---|---|
   | `appimagetool` | packs the AppDir |
   | `runtime` (type2-runtime) | statically linked with fuse3, so no `libfuse2` has to be installed on the target |
   | `linuxdeploy` | collects the shared libraries and applies the upstream exclude list |

   The exclude list is what keeps `libGL`, `libGLX` and `libGLdispatch` out of
   the package: those are the entry point into the graphics driver of whatever
   machine the AppImage runs on, and bundling them breaks exactly the systems
   they were excluded for. `libGLEW` and `libglut` are bundled, as are
   `libfreetype` and `libcom_err`, which the exclude list drops but Neutrino
   needs on a stock system.

   **GStreamer.** Playback is the one part a dependency walk cannot find.
   GStreamer loads its elements with `dlopen`, and libstb-hal builds its
   pipeline with `gst_element_factory_make("playbin", …)` when playback starts —
   so a package without those modules starts perfectly, shows its menus, and
   then plays nothing. They are therefore copied in whole from the build host
   (`pkg-config --variable=pluginsdir gstreamer-1.0`), together with the libraries
   they need — measured, that is the difference between a 35 MB and a 136 MB
   package. `APPIMAGE_BUNDLE_GSTREAMER=0` builds the small variant, at the price
   of needing GStreamer on the target.

   Their dependencies are worked out rather than assumed. The upstream exclude
   list drops `libfontconfig`, `libharfbuzz`, `libfribidi` and `libasound` on the
   assumption that the host has them; a stock Debian 13 does not, and the result
   was 19 modules that were in the package and could not be loaded — including
   `libgstlibav`, i.e. every `avdec_*` decoder and the ALSA sink, with nothing in
   a file listing to show for it. The closure is therefore computed after
   linuxdeploy has run, skipping only what has to come from the machine itself.

   Four kinds of module are dropped again straight away. `va`, `vaapi`, `vdpau`
   and `nvcodec` hand decoding to the host GPU driver, which is the same reason
   `libGL` is not bundled; `gtk`, `gtkwayland` and `onnx` serve purposes Neutrino
   has none of and pulled in GTK 3 and an ML runtime. Everything else stays:
   which demuxer a stream needs is decided at runtime, and a hand-picked list
   would be wrong for somebody's media soon enough.

   A checksum mismatch fails the build. That is deliberate: it means the pinned
   upstream asset changed, and the new one should be looked at before the
   recorded checksum in `scripts/ensure_appimagetool.sh` is updated.

   Set `APPIMAGE_TOOL` to an executable of your own to bypass the pinned
   appimagetool, for instance when testing different tooling.

2. **Debian package (`make package-deb`)**
   - Generates a minimal `DEBIAN/control` file and a `postinst` script with root guidance.
   - Install with `dpkg -i neutrino-generic-pc_<version>_<arch>.deb`.
   - Recommended follow-up: add the user to `video`, `input`, `plugdev` groups.

3. **Static archive (`make package-static`)**
   - Triggers `make neutrino-static` and archives the result.
   - Caution: static binaries grow in size and may conflict with proprietary graphics stacks.

## Preparation Checklist

- Run `make neutrino` at least once before packaging so the staged sysroot `artifacts/sysroot` is populated.  
  Static bundles additionally require `make neutrino-static`.
- Ensure your environment includes the CLI helpers used by the scripts:
  - `chrpath` or `patchelf` for AppImage builds. The linker records the staging
    directory as `RUNPATH`; without one of these the package would name the
    machine it was built on, so the build refuses to continue.
  - `docker` if you want `make package-appimage-verify` to start the package on
    a clean system, and the GStreamer development files if you want its playback
    probe to be built. The tooling itself (`appimagetool`, the runtime and
    `linuxdeploy`) is fetched by `scripts/ensure_appimagetool.sh`; no `libfuse2`
    has to be installed, on the build host or on the target. A target without any
    `fusermount` prints a line starting with `Error:` and then extracts itself to
    a temporary directory and runs anyway.
  - `dpkg-deb` (usually from `dpkg-dev`) for Debian packages.
  - `python3` for `scripts/version_info.sh` (already covered by `make deps`).
- Packaging targets can be executed without root, but installing the resulting artifacts almost always needs elevated privileges.
- To run everything in one go: `make package-appimage package-deb package-static`.
Note: The previous container workflow has been removed; all targets run on the host.

## Verifying an AppImage

```bash
make package-appimage-verify
```

`ldd` on the build machine proves nothing, because every dependency is
installed there. That is precisely why the package looked fine for a long time
while shipping no data at all. So the check works on the finished artefact and
then starts it on a system that has never built Neutrino:

- the binary resolves its data below the prefix the package actually carries,
  so a developer build cannot be packaged by mistake;
- no path of the build machine survives, in the binary, in the `RUNPATH`, or
  in any other file the package ships. One documented exception: LuaJIT is
  built with `PREFIX` set to the staging directory instead of `/usr` plus
  `DESTDIR`, so its compiled-in module search path names the build machine.
  `AppRun` sets `LUA_PATH` and `LUA_CPATH` so that default is never used;
  removing the string itself means changing how LuaJIT is built, which would
  move the module path for the developer build too;
- icons, locales, webroot, fonts and the configuration seed are present;
- no library of the libGL family and no part of the C runtime is bundled, every
  bundled library matches the binary's architecture, and the libraries the host
  does not provide are present. `libva`, `libva-drm`, `libva-x11`, `libvdpau`
  and `libwayland-egl` do ship: the host `libavcodec` that `libgstlibav` needs
  lists them in `DT_NEEDED`, and dropping them costs every `avdec_*` decoder.
  Unlike libGL they fail soft, falling back to software decoding when the host
  driver does not match. X11 and Wayland client libraries are left to the
  upstream exclude list, which is why some of them ship — they are protocol
  libraries, not driver entry points;
- on an untouched `debian:13`, before anything is installed, the only libraries
  the package cannot resolve are the host graphics stack it deliberately leaves
  out. That sweep is what makes the host requirement below a measured number
  instead of a promise: a library that was meant to be bundled and is not shows
  up here, and on the build host it never would;
- it then starts in that container with the documented host requirement
  installed, **parses** its bundled font from the mapped prefix and reads its
  locale. The proof has to come from a line printed after the file was opened:
  Neutrino prints `font file: <path>` from a compile-time constant *before* it
  calls `access()`, so matching that line passes a package whose data tree is
  empty — which is exactly what it once did;
- it creates a per-user configuration from the shipped defaults;
- every bundled GStreamer module is checked for unresolved libraries on that
  clean system, and a probe built for the occasion confirms a `playbin` can
  still be created. Listing the files answers neither question: a module whose
  own dependency was left out is present and unloadable at the same time.

`APPIMAGE_VERIFY_CONTAINER=0` limits it to the static checks. Those static
checks are themselves tested, offline, by `tests/shell/test_appimage_verify.sh`:
every assertion there breaks one property of a known-good package and requires
the gate to name it, because a check that cannot fail is the failure mode this
gate has had twice. `tests/shell/test_appimage_bridge.sh` covers the other half,
the AppRun mapping and the library policy in `gen_appimage.sh`. Both run as part
of `make test-shell`.

## What the package needs on the target

The AppImage is built against the build host's C library and cannot run on a
machine with an older one. Measured on the current Debian 13 build host, the
floor is **glibc 2.39, GLIBCXX 3.4.32 and CXXABI 1.3.15**: Ubuntu 24.04 and
Fedora 41 work, Debian 12 and Ubuntu 22.04 do not (`version GLIBC_2.38 not
found`). The binary itself only needs 2.38 — the bundled `libsystemd` is what
raises it — so `make package-appimage-verify` measures the whole package
against that number and fails if a newer build host pushes it up.

That floor is a property of the build host, not of the code — building on an
older base lowers it for everyone.

Besides the C library the target has to provide **the OpenGL and X11 stack**:
`libgl1` on Debian and Ubuntu (it pulls in `libX11`), `mesa-libGL` plus
`libglvnd-glx` on Fedora. That is the direct consequence of not bundling the
graphics libraries — they talk to the machine's own driver, and a bundled copy
is the classic way to make an AppImage fail on the systems it was meant to
support. An untouched `debian:13` therefore stops with
`libGL.so.1: cannot open shared object file`, and `make package-appimage-verify`
measures that set on every run so this list cannot quietly grow.

Nothing beyond that: no `libfuse2`, no GStreamer, no Neutrino build
dependencies. A machine with no `fusermount` at all prints one line starting
with `Error:` and then extracts and runs.

The packaged web interface is configured for **port 80**, not the 31344 that
`NEUTRINO_WEB_PORT` sets for the developer build: the shipped `nhttpd.conf`
carries Neutrino's own default. Port 80 needs privileges an ordinary user does
not have, so a rootless run falls back to 8080 and aborts the web server if that
is occupied as well. Set `WebsiteMain.port` in
`~/.local/share/neutrino-appimage/tuxbox/config/nhttpd.conf` after the first
start to something above 1024 for a rootless setup.

## Configuration knobs

All variables can be overridden on the command line (`make PACKAGE_VERSION=3.30.0 package-deb`) or persisted in `Makefile.local`. Defaults refer to the repository root (`${PWD}`).

| Variable | Default | Used by | Effect |
| --- | --- | --- | --- |
| `APPIMAGE_TOOL` | unset | AppImage | Executable to use instead of the pinned appimagetool. Leave unset for reproducible packages. |
| `APPIMAGE_OUTPUT_DIR` | `artifacts/appimage` | AppImage | Destination folder for generated AppImage files. |
| `APPIMAGE_RUNTIME_PREFIX` | `/opt/neutrino` | AppImage | Prefix the packaged Neutrino is configured against and that AppRun maps at runtime. |
| `APPIMAGE_BUILD_DIR` | `build/neutrino-appimage` | AppImage | Build directory of the packaging variant, separate from the developer build. |
| `APPIMAGE_SYSROOT` | `artifacts/sysroot-appimage` | AppImage | Staging tree of the packaging variant. |
| `NEUTRINO_APPIMAGE_STATE` | `${XDG_DATA_HOME:-~/.local/share}/neutrino-appimage` | AppImage (runtime) | Where the finished package keeps its configuration. Read by AppRun, not by the build. |
| `APPIMAGE_VERIFY_IMAGE` | `debian:13` | Verification | Container image the package is started in. |
| `APPIMAGE_VERIFY_CONTAINER` | `1` | Verification | Set to `0` to run only the static checks, without starting the package. |
| `APPIMAGE_BUNDLE_GSTREAMER` | `1` | AppImage | Set to `0` to leave the GStreamer modules out. Much smaller, but playback then needs GStreamer on the target. |
| `NEUTRINO_NAME` | `Neutrino` | AppImage | Prefix for the produced `Neutrino_<version>_<arch>.AppImage`. |
| `PACKAGE_NAME` | `neutrino-generic-pc` | Debian | Debian package name (`Package:` field and filename). |
| `PACKAGE_VERSION` | derived from git | Debian | Version string; override for release builds (e.g. `PACKAGE_VERSION=3.30.0`). |
| `DEB_OUTPUT_DIR` | `artifacts/deb` | Debian | Destination folder for `.deb` files. |
| `STATIC_OUTPUT_DIR` | `artifacts/static` | Static | Destination folder for static tarballs. |
| `NEUTRINO_INSTALL_DIR` | `artifacts/sysroot` | AppImage / Debian | Base sysroot copied into packaging layouts. |
| `NEUTRINO_INSTALL_DIR_STATIC` | `artifacts/sysroot-static` | Static | Location of static install tree (created by `make neutrino-static`). |
| `NEUTRINO_PREFIX` | `/usr` | All | Prefix for the binary and libraries inside the package. Not the data prefix — that is `APPIMAGE_RUNTIME_PREFIX`. |

Tip: When scripting releases, combine overrides in a single command:

```bash
make PACKAGE_VERSION=3.30.0 \
     PACKAGE_NAME=neutrino-generic-pc \
     NEUTRINO_NAME="Neutrino Desktop" \
     package-appimage package-deb
```

## Licensing

- Preserve license files of bundled libraries (GPL, LGPL, MIT, ...).
- For AppImage/static bundles consider shipping a dedicated `LICENSES/` directory.

## Common pitfalls

- **`appimagetool not found`**: Run `scripts/ensure_appimagetool.sh` (invoked automatically by `make package-appimage`) or download from https://appimage.github.io/AppImageKit/ and add to `PATH`.
- **`dpkg-deb` missing**: Install the `dpkg-dev` package.
- **Static build fails**: Ensure dependencies support `--enable-static` (switching to musl may help).

See `docs/README.en.md` for a broader overview.

## Installing and launching generated artifacts

- **AppImage** (e.g. `Neutrino_0a129a0-x86_64.AppImage`)
  1. Copy the AppImage to the target machine.
  2. Make it executable: `chmod +x Neutrino_<version>-<arch>.AppImage`.
  3. Run (root recommended for device access): `sudo ./Neutrino_<version>-<arch>.AppImage`. Use `ALLOW_NON_ROOT=1` only if you accept limited device support.

- **Debian package** (e.g. `neutrino-generic-pc_3.25.0+git0a129a0_amd64.deb`)
  1. Install via `sudo apt install ./neutrino-generic-pc_<version>_<arch>.deb`.
  2. The binary is deployed under `/usr/bin/neutrino`; start with `sudo neutrino` (or create a service/unit as desired). Post-install script prints reminders about root/device requirements.
