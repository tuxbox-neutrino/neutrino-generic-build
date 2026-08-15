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
   - Creates an AppDir structure and invokes `appimagetool`.
   - Runtime still requires root privileges; the launcher prints a warning.
   - Dependencies are copied into the AppDir but remain dynamically linked.
   - The build now calls `scripts/ensure_appimagetool.sh` automatically. If `appimagetool` is missing, it is downloaded into `tools/` and re-used on subsequent runs.
   - Manual setup (handy for offline environments or custom mirrors):
     1. Download the current binary (continuous channel recommended if “latest” breaks):
        ```bash
        wget -O appimagetool-x86_64.AppImage \
          https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
        ```
     2. Make it executable and move it onto your `PATH`:
        ```bash
        chmod +x appimagetool-x86_64.AppImage
        sudo mv appimagetool-x86_64.AppImage /usr/local/bin/appimagetool
        # -- or, without root --
        mkdir -p "$HOME/.local/bin"
        mv appimagetool-x86_64.AppImage "$HOME/.local/bin/appimagetool"
        export PATH="$HOME/.local/bin:$PATH"
        ```
     3. Ensure FUSE (commonly `libfuse2`) is installed so AppImages can mount correctly:
        ```bash
        sudo apt install libfuse2        # Debian/Ubuntu
        sudo pacman -S fuse2             # Arch
        ```
     4. Verify via `appimagetool --version`.
     5. When FUSE is unavailable on the build host, the helper falls back to `APPIMAGE_EXTRACT_AND_RUN=1`, extracting the tool into a temporary directory. The generated AppImage itself still expects FUSE on the target system unless you extract it manually.
     - Arch Linux users can alternatively install `appimagetool-bin` / `appimagetool-git` from the AUR.

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
  - `appimagetool` (auto-downloaded by `scripts/ensure_appimagetool.sh`) and FUSE (`libfuse2`) for AppImage builds.
  - `dpkg-deb` (usually from `dpkg-dev`) for Debian packages.
  - `python3` for `scripts/version_info.sh` (already covered by `make deps`).
- Packaging targets can be executed without root, but installing the resulting artifacts almost always needs elevated privileges.
- To run everything in one go: `make package-appimage package-deb package-static`.
Note: The previous container workflow has been removed; all targets run on the host.

## Configuration knobs

All variables can be overridden on the command line (`make PACKAGE_VERSION=3.30.0 package-deb`) or persisted in `Makefile.local`. Defaults refer to the repository root (`${PWD}`).

| Variable | Default | Used by | Effect |
| --- | --- | --- | --- |
| `APPIMAGE_TOOL` | `appimagetool` | AppImage | Path/name of the AppImage generator binary. |
| `APPIMAGE_OUTPUT_DIR` | `artifacts/appimage` | AppImage | Destination folder for generated AppImage files. |
| `NEUTRINO_NAME` | `Neutrino` | AppImage | Prefix for the produced `Neutrino_<version>_<arch>.AppImage`. |
| `PACKAGE_NAME` | `neutrino-generic-pc` | Debian | Debian package name (`Package:` field and filename). |
| `PACKAGE_VERSION` | derived from git | Debian | Version string; override for release builds (e.g. `PACKAGE_VERSION=3.30.0`). |
| `DEB_OUTPUT_DIR` | `artifacts/deb` | Debian | Destination folder for `.deb` files. |
| `STATIC_OUTPUT_DIR` | `artifacts/static` | Static | Destination folder for static tarballs. |
| `NEUTRINO_INSTALL_DIR` | `artifacts/sysroot` | AppImage / Debian | Base sysroot copied into packaging layouts. |
| `NEUTRINO_INSTALL_DIR_STATIC` | `artifacts/sysroot-static` | Static | Location of static install tree (created by `make neutrino-static`). |
| `NEUTRINO_PREFIX` | `/usr` | All | Prefix inside the package or AppImage. Change to `/opt/neutrino` for relocatable installs. |

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
