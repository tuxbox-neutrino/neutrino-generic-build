#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${NEUTRINO_INSTALL_DIR:-}"
OUTPUT_DIR="${APPIMAGE_OUTPUT_DIR:-artifacts/appimage}"
APPIMAGE_TOOL="${APPIMAGE_TOOL:-appimagetool}"
APPDIR="${OUTPUT_DIR}/Neutrino.AppDir"
NEUTRINO_PREFIX="${NEUTRINO_PREFIX:-/usr}"
NEUTRINO_NAME="${NEUTRINO_NAME:-Neutrino}"
# The prefix Neutrino was configured against. Its data directories are string
# literals in the binary (see make/package.mk), so the tree below it has to be
# shipped and mapped back onto this exact path at runtime.
DATA_PREFIX="${NEUTRINO_APPIMAGE_PREFIX:-/opt/neutrino}"

VERSION_JSON=$(scripts/version_info.sh)
# slug, not package: the package version carries a '+' because dpkg wants one,
# and a '+' in a release asset filename gets read as a space by uploaders that
# do not encode it, leaving the download link pointing at nothing.
VERSION_PKG=$(printf '%s' "${VERSION_JSON}" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("slug") or data.get("base") or "dev")')
ARCH=$(uname -m)
APPIMAGE_NAME="${NEUTRINO_NAME}_${VERSION_PKG}_${ARCH}.AppImage"

if [[ -z "${INSTALL_DIR}" || ! -d "${INSTALL_DIR}" ]]; then
  echo "[appimage] NEUTRINO_INSTALL_DIR invalid: ${INSTALL_DIR}" >&2
  exit 1
fi

# AppRun lays a tmpfs over the parent of DATA_PREFIX to create the mount point.
# A single-component prefix would make that parent "/", so refuse it here rather
# than discover it on a user's machine.
case "${DATA_PREFIX}" in
  /*/?*) ;;
  *)
    echo "[appimage] NEUTRINO_APPIMAGE_PREFIX must be an absolute path with at least two components: ${DATA_PREFIX}" >&2
    exit 1
    ;;
esac

DATA_SRC="${INSTALL_DIR}${DATA_PREFIX}"
# Kept outside the AppDir: linuxdeploy installs it through --custom-apprun, and
# handing it a file that is already at the destination would truncate it.
APPRUN_SRC="${OUTPUT_DIR}/AppRun.generated"
if [[ ! -d "${DATA_SRC}" ]]; then
  cat >&2 <<MSG
[appimage] No data tree at ${DATA_SRC}.
[appimage] The AppImage build has to be configured against ${DATA_PREFIX};
[appimage] use 'make package-appimage' instead of calling this script directly.
MSG
  exit 1
fi

mkdir -p "${APPDIR}"
rm -rf "${APPDIR:?}/"*
mkdir -p "${APPDIR}/usr"
cp -a "${INSTALL_DIR}${NEUTRINO_PREFIX}/." "${APPDIR}/usr/"

# The staging tree is a build sysroot, so it also holds things only a compiler
# ever wants. Two reasons to drop them: libtool archives and pkg-config files
# record the absolute staging directory, so they would ship the builder's home
# directory even though the binary itself no longer does; and headers and static
# archives are several megabytes that can never be used at runtime.
# usr/share/doc is deliberately not touched -- linuxdeploy puts the copyright
# files of the bundled libraries there, and those have to be redistributed.
for build_only in "${APPDIR}/usr/lib" "${APPDIR}/usr/lib64"; do
  [[ -d "${build_only}" ]] || continue
  find "${build_only}" \( -name '*.la' -o -name '*.a' \) -delete 2>/dev/null || true
done
rm -rf "${APPDIR}/usr/include" "${APPDIR}/usr/share/man" \
       "${APPDIR}/usr/lib/pkgconfig" "${APPDIR}/usr/lib64/pkgconfig" \
       "${APPDIR}/usr/share/pkgconfig"

# GStreamer keeps its actual functionality in modules it loads with dlopen, so
# nothing in the binary's DT_NEEDED list mentions them and a dependency walk
# cannot find them. libstb-hal builds its pipeline with
# gst_element_factory_make("playbin", ...) in cPlayback::Open, which means the
# application starts perfectly well without them and only fails when someone
# tries to play something -- exactly what a start-up smoke test cannot see.
#
# These are copied in before the dependency collection below, so the libraries
# the modules themselves need are picked up with everything else.
if [[ "${APPIMAGE_BUNDLE_GSTREAMER:-1}" == "1" ]]; then
  gst_plugin_dir="$(pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || true)"
  gst_scanner_dir="$(pkg-config --variable=pluginscannerdir gstreamer-1.0 2>/dev/null || true)"
  if [[ -z "${gst_plugin_dir}" || ! -d "${gst_plugin_dir}" ]]; then
    echo "[appimage] GStreamer plugin directory not found via pkg-config." >&2
    echo "[appimage] The package would start but play nothing. Install the GStreamer" >&2
    echo "[appimage] development files, or set APPIMAGE_BUNDLE_GSTREAMER=0 to accept it." >&2
    exit 1
  fi
  echo "[appimage] Bundling GStreamer modules from ${gst_plugin_dir}"
  mkdir -p "${APPDIR}/usr/lib/gstreamer-1.0"
  cp -a "${gst_plugin_dir}/." "${APPDIR}/usr/lib/gstreamer-1.0/"

  # Dropped again straight away, for two different reasons.
  #
  # va, vaapi, vdpau, nvcodec and vulkan hand work straight to the host's GPU
  # driver. Shipping our own copy of that path is the same mistake as bundling
  # libGL, and the exclude list linuxdeploy applies covers libGL but knows
  # nothing about these. Neutrino has no Vulkan path at all.
  #
  # Their libraries do still end up in the package, through the host libavcodec
  # that libgstlibav needs, and that is on purpose: libavcodec lists them in
  # DT_NEEDED, so removing them would make it unloadable and cost every libav
  # decoder -- H.264 among them. Unlike libGL they fail soft, falling back to
  # software decoding when the host driver does not match.
  #
  # gtk, gtkwayland and onnx serve purposes Neutrino does not have: it draws
  # through its own GL framebuffer and runs no inference. Measured on Debian 13,
  # those three alone pulled in GTK 3 and an ONNX runtime, 19 MB of the package.
  #
  # Everything else is kept. Which demuxer or decoder a stream needs is decided
  # by playbin at runtime, and a hand-picked list of those would be wrong for
  # somebody's media sooner rather than later.
  for gst_drop in libgstva libgstvaapi libgstvdpau libgstnvcodec libgstvulkan \
                  libgstgtk libgstgtkwayland libgstonnx; do
    rm -f "${APPDIR}/usr/lib/gstreamer-1.0/${gst_drop}.so"
  done
  # The plugin directory carries a couple of headers on some distributions.
  rm -rf "${APPDIR}/usr/lib/gstreamer-1.0/include"

  if [[ -x "${gst_scanner_dir}/gst-plugin-scanner" ]]; then
    mkdir -p "${APPDIR}/usr/libexec/gstreamer-1.0"
    cp -a "${gst_scanner_dir}/gst-plugin-scanner" "${APPDIR}/usr/libexec/gstreamer-1.0/"
  fi
fi

# The linker records the staging directory as RUNPATH, so the shipped binary
# would name the maintainer's build directory and look for its libraries in a
# path that exists on no other machine. Point it at the bundled lib directory.
appdir_bin="${APPDIR}/usr/bin/neutrino"
if [[ ! -f "${appdir_bin}" ]]; then
  echo "[appimage] No Neutrino binary at ${appdir_bin}." >&2
  exit 1
fi
if ! file -b "${appdir_bin}" | grep -q 'ELF'; then
  echo "[appimage] ${appdir_bin} is not an ELF binary; refusing to package it." >&2
  exit 1
fi
# patchelf first: chrpath can only rewrite an existing entry, and on a binary
# that was linked without one it fails -- printing its complaint on stdout, of
# all places, so redirecting stdout would have made the script die under set -e
# with nothing on stderr to explain it. Neither tool is trusted to have worked;
# the result is read back below.
if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath '$ORIGIN/../lib' "${appdir_bin}" || true
fi
if command -v chrpath >/dev/null 2>&1; then
  chrpath -r '$ORIGIN/../lib' "${appdir_bin}" >/dev/null 2>&1 || true
fi

appdir_runpath="$(readelf -d "${appdir_bin}" 2>/dev/null | awk '/RUNPATH|RPATH/ {print $NF}' | tr -d '[]')"
case "${appdir_runpath}" in
  ''|'$ORIGIN'*) ;;
  *)
    cat >&2 <<MSG
[appimage] The RUNPATH still points at this machine: ${appdir_runpath}
[appimage] Refusing to build a package that carries the maintainer's build path.
[appimage] Install chrpath or patchelf (Debian/Ubuntu: apt install patchelf).
MSG
    exit 1
    ;;
esac

# Icons, locales, themes, fonts, the webroot and the plugin directories all live
# below DATA_PREFIX, not below /usr. Copying only the latter is what left the
# earlier AppImages without a user interface.
mkdir -p "${APPDIR}${DATA_PREFIX}"
cp -a "${DATA_SRC}/." "${APPDIR}${DATA_PREFIX}/"
# Mount point for the per-user state that AppRun binds over the shipped
# defaults; keep it present even if this build installed nothing writable.
mkdir -p "${APPDIR}${DATA_PREFIX}/usr/var"

cat >"${APPDIR}/neutrino.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Neutrino (generic-pc)
Comment=Neutrino DTV application (requires root privileges for device access)
Exec=neutrino
Terminal=false
Icon=neutrino
Categories=AudioVideo;Video;TV;
EOF

{
  printf '#!/bin/sh\n'
  printf 'NEUTRINO_DATA_PREFIX=%q\n' "${DATA_PREFIX}"
  cat <<'EOF'
# AppRun for the Neutrino AppImage.
#
# Neutrino resolves its data directories through string literals that configure
# bakes into the binary, so it can only ever look at the prefix it was built
# with. Until Neutrino resolves those paths at runtime, this wrapper makes that
# prefix exist: the bundled tree is mapped onto it inside a private mount
# namespace. Nothing is created on the host filesystem, and the mapping
# disappears with the process.
set -eu

APPDIR="$(dirname "$(readlink -f "$0")")"
NEUTRINO_DATA_ROOT="${APPDIR}${NEUTRINO_DATA_PREFIX}"
NEUTRINO_MOUNT_PARENT="$(dirname "${NEUTRINO_DATA_PREFIX}")"
NEUTRINO_BIN="${APPDIR}/usr/bin/neutrino"
# No HOME fallback to a world-writable /tmp path: that name is predictable, so
# anyone on the machine could pre-create it as a symlink and have the seeding
# follow it. Without HOME there is nowhere sensible to keep configuration.
if [ -n "${NEUTRINO_APPIMAGE_STATE:-}" ]; then
  NEUTRINO_STATE_DIR="${NEUTRINO_APPIMAGE_STATE}"
elif [ -n "${XDG_DATA_HOME:-}" ]; then
  NEUTRINO_STATE_DIR="${XDG_DATA_HOME}/neutrino-appimage"
elif [ -n "${HOME:-}" ]; then
  NEUTRINO_STATE_DIR="${HOME}/.local/share/neutrino-appimage"
else
  echo "AppRun: neither HOME nor XDG_DATA_HOME is set; point NEUTRINO_APPIMAGE_STATE at a directory." >&2
  exit 1
fi

if [ ! -d "${NEUTRINO_DATA_ROOT}" ]; then
  echo "AppRun: the bundled data tree is missing at ${NEUTRINO_DATA_ROOT}." >&2
  exit 1
fi

# Neutrino builds its dummy frontend only when *both* hold: it found no tuner
# and SIMULATE_FE says so -- src/zapit/femanager.cpp, `femap.empty() &&
# simulate_fe_enabled()`. Without the variable a machine with no receiver simply
# ends up with no frontend, and nothing says why.
#
# The run targets in the build tree set it unconditionally
# (scripts/neutrino-wrapper.sh). This package must not: it is handed to
# strangers, and the same variable also switches off radiotext and other
# tuner-bound functions in src/gui/osd_setup.cpp and src/gui/channellist.cpp.
# Somebody who owns a receiver would lose those without ever learning the name
# of the switch. So it is set only where there is demonstrably no frontend, and
# never over a value the user chose -- SIMULATE_FE=0 stays off.
#
# The glob is a variable so a test can point it somewhere it controls; the
# default is the path zapit itself opens (src/zapit/frontend.cpp).
NEUTRINO_FRONTEND_GLOB="${NEUTRINO_FRONTEND_GLOB:-/dev/dvb/adapter*/frontend*}"
if [ -z "${SIMULATE_FE:-}" ]; then
  neutrino_have_tuner=0
  for neutrino_fe in ${NEUTRINO_FRONTEND_GLOB}; do
    if [ -e "${neutrino_fe}" ]; then
      neutrino_have_tuner=1
      break
    fi
  done
  if [ "${neutrino_have_tuner}" = 0 ]; then
    export SIMULATE_FE=1
  fi
fi

# If the mount point has to be created, a tmpfs goes over its parent -- and a
# tmpfs hides whatever was there. With a prefix below the user's home directory
# that would be the state directory seeded just below, or even this AppDir, and
# the mount would then fail with a bare ENOENT. Refuse instead.
case "${NEUTRINO_DATA_ROOT}/" in
  "${NEUTRINO_MOUNT_PARENT}"/*)
    echo "AppRun: ${NEUTRINO_MOUNT_PARENT} would be covered and contains the package itself." >&2
    exit 1
    ;;
esac

# A trailing slash would put the temporary seed directory built below *inside*
# the state directory instead of beside it. NEUTRINO_APPIMAGE_STATE is a
# documented, user-facing variable and shell completion appends that slash.
while :; do
  case "${NEUTRINO_STATE_DIR}" in
    */) NEUTRINO_STATE_DIR="${NEUTRINO_STATE_DIR%/}" ;;
    *) break ;;
  esac
done
if [ -z "${NEUTRINO_STATE_DIR}" ]; then
  echo "AppRun: NEUTRINO_APPIMAGE_STATE must not be the root directory." >&2
  exit 1
fi

case "${NEUTRINO_STATE_DIR}/" in
  "${NEUTRINO_MOUNT_PARENT}"/*)
    echo "AppRun: ${NEUTRINO_MOUNT_PARENT} would be covered and contains ${NEUTRINO_STATE_DIR}." >&2
    exit 1
    ;;
esac

# Configuration, bouquets, timers and the writable plugin directories all live
# below the prefix, so that part cannot stay inside the read-only image. Seed a
# per-user copy once, then mount it over the shipped defaults.
#
# The marker, rather than the directory, is what says "seeded": creating the
# directory first and copying into it afterwards leaves a half-filled state
# behind if the first start is interrupted, and every later start would skip the
# seeding and run on a truncated configuration.
#
# Nothing here ever deletes anything below the state directory. A directory
# without the marker is either an interrupted first start or the configuration
# of an older package that did not write one, and those are indistinguishable
# from the outside -- so the missing files are filled in and existing ones are
# left exactly as they are.
if [ ! -f "${NEUTRINO_STATE_DIR}/.seeded" ]; then
  if [ -d "${NEUTRINO_STATE_DIR}" ]; then
    if [ -d "${NEUTRINO_DATA_ROOT}/usr/var" ]; then
      cp -a -n "${NEUTRINO_DATA_ROOT}/usr/var/." "${NEUTRINO_STATE_DIR}/" || {
        echo "AppRun: cannot complete the configuration in ${NEUTRINO_STATE_DIR}." >&2
        exit 1
      }
    fi
    : > "${NEUTRINO_STATE_DIR}/.seeded" || {
      echo "AppRun: cannot write to ${NEUTRINO_STATE_DIR}." >&2
      exit 1
    }
  else
    mkdir -p "$(dirname "${NEUTRINO_STATE_DIR}")" || {
      echo "AppRun: cannot create $(dirname "${NEUTRINO_STATE_DIR}")." >&2
      exit 1
    }
    # Not "rm -rf" on the temp path first. That would destroy whatever sits
    # there, and the rule is that this script only ever removes what it created
    # itself. Bare mkdir is the atomic primitive that establishes exactly that:
    # it succeeds only for the process that created the directory, so from here
    # on the temp tree is unambiguously ours to clean up. A pid collision with
    # somebody else's leftover just moves us to the next name.
    neutrino_seed_tmp="${NEUTRINO_STATE_DIR}.seeding.$$"
    neutrino_seed_try=0
    while ! mkdir "${neutrino_seed_tmp}" 2>/dev/null; do
      neutrino_seed_try=$((neutrino_seed_try + 1))
      if [ "${neutrino_seed_try}" -gt 20 ]; then
        echo "AppRun: cannot create a staging directory next to ${NEUTRINO_STATE_DIR}." >&2
        exit 1
      fi
      neutrino_seed_tmp="${NEUTRINO_STATE_DIR}.seeding.$$-${neutrino_seed_try}"
    done
    if [ -d "${NEUTRINO_DATA_ROOT}/usr/var" ]; then
      cp -a "${NEUTRINO_DATA_ROOT}/usr/var/." "${neutrino_seed_tmp}/" || {
        rm -rf "${neutrino_seed_tmp}"
        echo "AppRun: cannot seed ${NEUTRINO_STATE_DIR} with the default configuration." >&2
        exit 1
      }
    fi
    : > "${neutrino_seed_tmp}/.seeded"
    # Two first starts at once are ordinary -- a launcher clicked twice. `mv`
    # onto an existing directory does not fail, it moves the source *inside* the
    # target, so the loser of that race would leave a second full copy of the
    # defaults sitting inside the winner's configuration. Whoever gets there
    # first produces a complete tree, so losing is success; only our own copy
    # has to go.
    if [ -e "${NEUTRINO_STATE_DIR}" ]; then
      rm -rf "${neutrino_seed_tmp}"
    elif ! mv "${neutrino_seed_tmp}" "${NEUTRINO_STATE_DIR}"; then
      rm -rf "${neutrino_seed_tmp}"
      echo "AppRun: cannot move the seeded configuration into place." >&2
      exit 1
    fi
    # The window between that test and the rename is small but not zero. What it
    # can leave behind carries this process's own pid in its name, so it can be
    # removed without touching anything a user could have put there.
    neutrino_seed_stray="${NEUTRINO_STATE_DIR}/${neutrino_seed_tmp##*/}"
    if [ -d "${neutrino_seed_stray}" ]; then
      rm -rf "${neutrino_seed_stray}"
    fi
  fi
fi

# Deliberately not exported. Everything below this line runs host binaries --
# id, unshare, bwrap, and mount and mkdir inside the namespace -- and an
# exported LD_LIBRARY_PATH makes them load the libraries bundled here instead of
# their own. That breaks bwrap on precisely the distributions the bwrap rung
# exists for, and a failure inside the bridge has no rung left to fall back to.
NEUTRINO_LIB_PATH="${APPDIR}/usr/lib:${APPDIR}/usr/lib64"
export APPDIR NEUTRINO_LIB_PATH
export NEUTRINO_DATA_PREFIX NEUTRINO_DATA_ROOT NEUTRINO_MOUNT_PARENT
export NEUTRINO_BIN NEUTRINO_STATE_DIR

# These are safe to export -- unlike LD_LIBRARY_PATH they mean nothing to the
# helper binaries below, and they have to survive into the namespace. The
# registry has to be written somewhere writable, which inside the namespace is
# the state bind; without a valid path GStreamer rescans every module on every
# single start.
# LuaJIT bakes its default module search path in at build time, and this build
# system builds it with PREFIX set to the staging directory, so the compiled-in
# default points at a path that exists only on the build machine. Overriding it
# here is what makes the bundled modules findable; the baked string itself is a
# build-system property and is recorded separately.
# Set without a trailing ";;": that would append the interpreter's compiled-in
# default, which is the build machine's staging directory, and the point here is
# that the default is never consulted. Because these replace the search path
# rather than extend it, they are only set when the directory they name is
# actually in the package -- NEUTRINO_LUA_FLAVOR also allows plain Lua, which
# installs under 5.4, and pointing the interpreter at an empty 5.1 path would
# take away the one that worked.
if [ -d "${APPDIR}/usr/share/lua/@LUA_ABI@" ] || [ -d "${APPDIR}/usr/lib/lua/@LUA_ABI@" ]; then
  LUA_PATH="${APPDIR}/usr/share/lua/@LUA_ABI@/?.lua;${APPDIR}/usr/share/lua/@LUA_ABI@/?/init.lua"
  LUA_CPATH="${APPDIR}/usr/lib/lua/@LUA_ABI@/?.so"
  export LUA_PATH LUA_CPATH
fi

if [ -d "${APPDIR}/usr/lib/gstreamer-1.0" ]; then
  GST_PLUGIN_SYSTEM_PATH="${APPDIR}/usr/lib/gstreamer-1.0"
  GST_PLUGIN_PATH="${APPDIR}/usr/lib/gstreamer-1.0"
  GST_REGISTRY="${NEUTRINO_DATA_PREFIX}/usr/var/gstreamer-registry.bin"
  export GST_PLUGIN_SYSTEM_PATH GST_PLUGIN_PATH GST_REGISTRY
  if [ -x "${APPDIR}/usr/libexec/gstreamer-1.0/gst-plugin-scanner" ]; then
    GST_PLUGIN_SCANNER="${APPDIR}/usr/libexec/gstreamer-1.0/gst-plugin-scanner"
    export GST_PLUGIN_SCANNER
  fi
fi

NEUTRINO_BRIDGE='
set -eu
if [ ! -d "${NEUTRINO_DATA_PREFIX}" ]; then
  if [ ! -d "${NEUTRINO_MOUNT_PARENT}" ]; then
    echo "AppRun: ${NEUTRINO_MOUNT_PARENT} does not exist, cannot create the mount point." >&2
    exit 1
  fi
  mount -t tmpfs tmpfs "${NEUTRINO_MOUNT_PARENT}" || {
    echo "AppRun: cannot map the bundled data onto ${NEUTRINO_DATA_PREFIX} (tmpfs on ${NEUTRINO_MOUNT_PARENT} failed)." >&2
    exit 1
  }
  mkdir -p "${NEUTRINO_DATA_PREFIX}"
fi
mount --bind "${NEUTRINO_DATA_ROOT}" "${NEUTRINO_DATA_PREFIX}" || {
  echo "AppRun: cannot map the bundled data onto ${NEUTRINO_DATA_PREFIX} (bind failed)." >&2
  exit 1
}
mount -o remount,ro,bind "${NEUTRINO_DATA_PREFIX}" || {
  echo "AppRun: cannot map the bundled data onto ${NEUTRINO_DATA_PREFIX} (read-only remount failed)." >&2
  exit 1
}
mount --bind "${NEUTRINO_STATE_DIR}" "${NEUTRINO_DATA_PREFIX}/usr/var" || {
  echo "AppRun: cannot map the bundled data onto ${NEUTRINO_DATA_PREFIX} (state bind failed)." >&2
  exit 1
}
exec env LD_LIBRARY_PATH="${NEUTRINO_LIB_PATH}" "${NEUTRINO_BIN}" "$@"
'

# Three ways to get a private mount namespace, in decreasing order of
# availability. Real root needs no user namespace at all, which is also the
# path the documented hardware setup takes. Unprivileged user namespaces cover
# the rootless case, except where a distribution restricts them -- Ubuntu 24.04
# does, via AppArmor -- and bwrap ships its own profile for exactly that.
#
# Every rung probes namespace creation before committing to it with exec, since
# being root is not the same as being allowed to create a mount namespace: in a
# restricted container it fails, and without the probe that failure would end
# here instead of trying the next rung. The probe cannot cover the mounting that
# follows, though -- that happens after exec, with no rung left -- so every
# mount in the bridge above reports what it was doing when it failed.
#
# --propagation private is not optional. It is what keeps the tmpfs and the
# binds below from propagating back into the mount namespace we came from; on a
# systemd host / is shared, so leaving it out would put them on the real system.
if [ "$(id -u)" = 0 ] && unshare --mount --propagation private true 2>/dev/null; then
  exec unshare --mount --propagation private /bin/sh -c "${NEUTRINO_BRIDGE}" sh "$@"
fi

if unshare --user --map-root-user --mount --propagation private true 2>/dev/null; then
  exec unshare --user --map-root-user --mount --propagation private \
    /bin/sh -c "${NEUTRINO_BRIDGE}" sh "$@"
fi

if command -v bwrap >/dev/null 2>&1 && bwrap --dev-bind / / true 2>/dev/null; then
  exec bwrap --dev-bind / / \
    --tmpfs "${NEUTRINO_MOUNT_PARENT}" \
    --ro-bind "${NEUTRINO_DATA_ROOT}" "${NEUTRINO_DATA_PREFIX}" \
    --bind "${NEUTRINO_STATE_DIR}" "${NEUTRINO_DATA_PREFIX}/usr/var" \
    --setenv LD_LIBRARY_PATH "${NEUTRINO_LIB_PATH}" \
    -- "${NEUTRINO_BIN}" "$@"
fi

cat >&2 <<MSG
AppRun: cannot map the bundled data onto ${NEUTRINO_DATA_PREFIX}.

Neutrino only looks for its icons, locales and webroot at that path, so
starting it without the mapping would give you an application without a user
interface. One of these is needed:

  - run the AppImage as root, or
  - unprivileged user namespaces (Debian and Fedora enable them by default;
    on Ubuntu 24.04 they are restricted by AppArmor), or
  - bubblewrap, packaged as "bubblewrap" on Debian/Ubuntu and Fedora.

Container runtimes usually block all three. Docker needs --privileged for
this to work, being root inside the container is not enough.
MSG
exit 1
EOF
} >"${APPRUN_SRC}"

# The interpreter's module directory is named after its ABI version, and
# NEUTRINO_LUA_FLAVOR decides which one gets built -- luajit installs under 5.1,
# plain Lua under 5.4. Read it off the staged tree instead of assuming.
lua_abi=""
for lua_dir in "${APPDIR}"/usr/lib/lua/*/ "${APPDIR}"/usr/share/lua/*/; do
  [[ -d "${lua_dir}" ]] || continue
  lua_abi="$(basename "${lua_dir}")"
  break
done
sed -i "s|@LUA_ABI@|${lua_abi:-5.1}|g" "${APPRUN_SRC}"

install -m 0755 "${APPRUN_SRC}" "${APPDIR}/AppRun"

if [[ -f "${INSTALL_DIR}${NEUTRINO_PREFIX}/share/icons/hicolor/256x256/apps/neutrino.png" ]]; then
  cp "${INSTALL_DIR}${NEUTRINO_PREFIX}/share/icons/hicolor/256x256/apps/neutrino.png" "${APPDIR}/neutrino.png"
else
  # Generate a simple placeholder icon if none was installed.
  python3 - "${APPDIR}/neutrino.png" <<'PY'
import sys
from pathlib import Path

try:
    from PIL import Image
except ModuleNotFoundError:
    Image = None

dest = Path(sys.argv[1])
if Image is None:
    # fallback: create a minimal PNG via RGB tuples using stdlib only
    import struct, zlib
    width = height = 64
    pixels = b''.join(b'\x00' + b'\x00\x66\xa3\xff' * width for _ in range(height))
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    data = zlib.compress(pixels, 9)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', data) + chunk(b'IEND', b'')
    dest.write_bytes(png)
else:
    img = Image.new('RGBA', (256, 256), (0, 102, 163, 255))
    img.save(dest)
PY
fi

# Collect the shared libraries Neutrino needs from the build host. Doing this by
# hand is a trap: libGL, libGLX and libGLdispatch must come from the machine the
# AppImage runs on, because they are the entry point into that machine's
# graphics driver, while libGLEW and libglut have to be bundled. linuxdeploy
# applies the upstream exclude list, so that distinction is maintained
# elsewhere rather than in a list here that would quietly rot.
#
# LD_LIBRARY_PATH is what lets it resolve our own ffmpeg libraries against each
# other; without it the dependency walk stops at libavutil.
# The upstream exclude list is tuned for the average desktop application and
# assumes the host provides these two. Measured against a clean Debian 13 that
# had nothing installed but the graphics driver: without them the binary does
# not reach main(). Anything added here has to be a library that is *not* part
# of the host's graphics or C library stack -- bundling one of those is what the
# exclude list exists to prevent.
APPIMAGE_FORCE_LIBS=(
  libfreetype.so.6  # font rendering; every menu and every OSD string needs it
  libcom_err.so.2   # reached through libgssapi_krb5 -> libcurl
)

# Libraries that have to come from the machine the package runs on, never from
# here. Two groups, for two different reasons:
#
#   the graphics and display stack   -- entry points into the machine's driver
#                                       or its display server; our copy would
#                                       talk to a driver it was not built for
#   glibc, libstdc++ and libgcc_s    -- mixing pieces of these across the
#                                       boundary breaks on any target whose
#                                       runtime is older than the build host's
#
# libgomp and libatomic are deliberately NOT here, though they ship with gcc:
# they are leaves, they talk to no driver, and nothing else in the package has
# to agree with the target's copy. Listing them would have meant deleting
# libraries that libfluidsynth and libsoxr legitimately need.
#
# linuxdeploy's exclude list covers most of this for what it discovers itself,
# but a library named explicitly with --library is deployed regardless -- so
# this list guards what gets named, and the check after packing enforces it on
# everything that ended up in the package, however it got there. libmvec,
# libanl, libutil and libthread_db are glibc members with names that no
# "libm."-style pattern catches.
# Every entry ends at a \. or _ on purpose: an unanchored "libGL" also matches
# libGLEW, which has to be bundled, and an earlier version of this list duly
# deleted it from the package.
APPIMAGE_HOST_LIBS='^(libGL\.so|libGLX\.so|libGLdispatch\.so|libEGL\.so|libGLESv[0-9]*\.so|libOpenGL\.so|libGLU\.so|libglapi\.so|libdrm\.so|libdrm_|libgbm\.so|libva\.so|libva-|libvdpau\.so|libwayland-|libX[0-9A-Za-z]*\.so|libxcb[-.]|libxshmfence\.so|ld-linux|libc\.so|libm\.so|libmvec\.|libdl\.|librt\.|libpthread\.|libresolv\.|libnsl\.|libanl\.|libutil\.|libcrypt\.|libthread_db|libBrokenLocale|libnss_|libstdc\+\+|libgcc_s)'

# $1 = ELF file, $2 = SONAME. Prints the path the loader resolves it to.
# Deliberately not "ldd | awk '\''…exit'\''": awk closing the pipe kills ldd with
# SIGPIPE, and under `set -o pipefail` that fails the whole build -- measured at
# roughly one run in thirteen. Reading ldd once into a variable has no pipe to
# break, and it resolves the right ABI by construction, which picking a line out
# of `ldconfig -p` does not.
resolve_needed() {
  local ldd_out
  ldd_out="$(ldd "$1" 2>/dev/null)" || return 1
  printf '%s\n' "${ldd_out}" | awk -v n="$2" '$1 == n && $2 == "=>" { print $3 }' | head -n1
}

if [[ -n "${APPIMAGE_DEPLOY_TOOL:-}" ]]; then
  deploy_args=()
  for lib in "${APPIMAGE_FORCE_LIBS[@]}"; do
    # `|| true`, like the other two call sites: resolve_needed returns 1 when ldd
    # itself fails, and without the guard errexit ends the build right here with
    # no output at all -- swallowing the diagnosis prepared two lines below.
    lib_path="$(resolve_needed "${APPDIR}/usr/bin/neutrino" "${lib}")" || true
    if [[ -z "${lib_path}" || ! -e "${lib_path}" ]]; then
      echo "[appimage] Cannot resolve ${lib} on this build host; the package would" >&2
      echo "[appimage] not start on a system that does not already provide it." >&2
      exit 1
    fi
    deploy_args+=(--library "${lib_path}")
  done

  # linuxdeploy walks what the executable needs. The GStreamer modules are
  # loaded with dlopen, so they are not on that path, and the upstream exclude
  # list drops several of the libraries they need -- libfontconfig, libharfbuzz,
  # libfribidi, libasound -- assuming the host provides them. A stock Debian 13
  # does not, and the result is the worst kind of failure: the module file is in
  # the package and cannot be loaded, so a file listing says everything is fine
  # while every libav decoder and the ALSA sink are gone.
  #
  # Naming them for linuxdeploy rather than copying them here is what keeps the
  # transitive closure, the rpath rewriting and the exclude list in one place,
  # instead of a hand-rolled loop that has to reimplement all three.
  if [[ -d "${APPDIR}/usr/lib/gstreamer-1.0" ]]; then
    module_libs=""
    for module in "${APPDIR}"/usr/lib/gstreamer-1.0/*.so; do
      [[ -e "${module}" ]] || continue
      needed_list="$(objdump -p "${module}" 2>/dev/null | awk '/NEEDED/ {print $2}')" || continue
      while IFS= read -r needed; do
        [[ -n "${needed}" ]] || continue
        [[ "${needed}" =~ ${APPIMAGE_HOST_LIBS} ]] && continue
        [[ -e "${APPDIR}/usr/lib/${needed}" ]] && continue
        case " ${module_libs} " in *" ${needed} "*) continue ;; esac
        needed_path="$(resolve_needed "${module}" "${needed}")" || true
        [[ -n "${needed_path}" && -e "${needed_path}" ]] || continue
        module_libs="${module_libs} ${needed}"
        deploy_args+=(--library "${needed_path}")
      done <<<"${needed_list}"
    done
    [[ -n "${module_libs}" ]] && echo "[appimage] Modules additionally need:${module_libs}"
  fi

  echo "[appimage] Collecting shared library dependencies"
  LD_LIBRARY_PATH="${APPDIR}/usr/lib:${LD_LIBRARY_PATH:-}" \
  APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGE_DEPLOY_TOOL}" \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/neutrino" \
    --desktop-file "${APPDIR}/neutrino.desktop" \
    --icon-file "${APPDIR}/neutrino.png" \
    "${deploy_args[@]}" \
    --custom-apprun "${APPRUN_SRC}"

  # linuxdeploy deploys a library named with --library, but still applies the
  # exclude list to that library's own dependencies. libpango is deployed and
  # its libharfbuzz is not, so the module ends up in the package unloadable --
  # which is the failure this whole section exists to prevent, one level deeper.
  #
  # So close the graph here, over everything bundled, until nothing new appears.
  # Paths come from ldd on the consumer, not from `ldconfig -p`: ldd resolves the
  # ABI the consumer actually needs, and picking a line out of ldconfig once put
  # an x32 library into a 64-bit package.
  complete_closure() {
    local changed=0 module needed needed_list needed_path
    while IFS= read -r module; do
      [[ -f "${module}" && ! -L "${module}" ]] || continue
      needed_list="$(objdump -p "${module}" 2>/dev/null | awk '/NEEDED/ {print $2}')" || continue
      while IFS= read -r needed; do
        [[ -n "${needed}" ]] || continue
        [[ "${needed}" =~ ${APPIMAGE_HOST_LIBS} ]] && continue
        [[ -e "${APPDIR}/usr/lib/${needed}" ]] && continue
        needed_path="$(resolve_needed "${module}" "${needed}")" || true
        [[ -n "${needed_path}" && -e "${needed_path}" ]] || continue
        cp -L --preserve=mode "${needed_path}" "${APPDIR}/usr/lib/${needed}"
        changed=1
      done <<<"${needed_list}"
    done < <(find "${APPDIR}/usr/lib" -name '*.so' -o -name '*.so.*')
    return "$(( changed == 0 ))"
  }

  closure_passes=0
  while complete_closure; do
    closure_passes=$(( closure_passes + 1 ))
    if [[ "${closure_passes}" -ge 20 ]]; then
      echo "[appimage] The dependency closure is not settling; giving up." >&2
      exit 1
    fi
  done

  # Whatever is still unresolved after that cannot be resolved on this host, and
  # shipping it would mean a module that is present and impossible to load.
  unresolved=""
  while IFS= read -r module; do
    [[ -f "${module}" && ! -L "${module}" ]] || continue
    needed_list="$(objdump -p "${module}" 2>/dev/null | awk '/NEEDED/ {print $2}')" || continue
    while IFS= read -r needed; do
      [[ -n "${needed}" ]] || continue
      [[ "${needed}" =~ ${APPIMAGE_HOST_LIBS} ]] && continue
      [[ -e "${APPDIR}/usr/lib/${needed}" ]] && continue
      case " ${unresolved} " in *" ${needed} "*) continue ;; esac
      unresolved="${unresolved} ${needed}"
    done <<<"${needed_list}"
  done < <(find "${APPDIR}/usr/lib" -name '*.so' -o -name '*.so.*')
  if [[ -n "${unresolved}" ]]; then
    echo "[appimage] Bundled libraries still need:${unresolved}" >&2
    echo "[appimage] They would be present in the package and impossible to load." >&2
    exit 1
  fi
  echo "[appimage] Dependency closure complete after ${closure_passes} pass(es)"

  # linuxdeploy applies its own exclude list to what it discovers, and that list
  # does not know about libva, libvdpau or the wayland and X11 client libraries.
  # Whatever it deployed is therefore checked against the same policy here --
  # otherwise the rule holds only for the libraries this script named itself,
  # which is how libgomp came to ship while being classified host-only.
  #
  # The exception is deliberate and narrow: libva*, libvdpau and libwayland-egl
  # are listed in the host libavcodec's DT_NEEDED, and libavcodec is what
  # libgstlibav needs, so removing them costs every avdec_* decoder. Unlike
  # libGL they degrade to software decoding when the host driver disagrees.
  # A deliberately narrower rule than APPIMAGE_HOST_LIBS, which governs what
  # this script *names* to linuxdeploy. Here the question is different: what may
  # never be in the finished package, whoever put it there. Only two groups
  # qualify -- the driver stack, where our copy would talk to a driver it was
  # not built for, and the C runtime, where mixing versions breaks start-up.
  #
  # X11 and Wayland client libraries are deliberately not in this rule. They are
  # protocol libraries, not driver entry points, and linuxdeploy's exclude list
  # already decides about them; overruling it here removed libglut's own
  # dependencies and left a package that could not start.
  #
  # libva*, libvdpau and libwayland-egl are also left alone: they arrive through
  # the host libavcodec that libgstlibav needs, and dropping them costs every
  # avdec_* decoder. Unlike libGL they degrade to software decoding.
  never_bundle='^(libGL\.so|libGLX\.so|libGLdispatch\.so|libEGL\.so|libGLESv[0-9]*\.so|libOpenGL\.so|libglapi\.so|libdrm\.so|libdrm_|libgbm\.so|ld-linux|libc\.so|libm\.so|libmvec\.|libdl\.|librt\.|libpthread\.|libresolv\.|libnsl\.|libanl\.|libutil\.|libcrypt\.|libthread_db|libBrokenLocale|libnss_|libstdc\+\+|libgcc_s)'
  policy_violations=""
  while IFS= read -r bundled; do
    name="$(basename "${bundled}")"
    [[ "${name}" =~ ${never_bundle} ]] || continue
    policy_violations="${policy_violations} ${name}"
    rm -f "${bundled}"
  done < <(find "${APPDIR}/usr/lib" -maxdepth 1 -name '*.so' -o -maxdepth 1 -name '*.so.*')
  [[ -n "${policy_violations}" ]] && echo "[appimage] Removed, must come from the target:${policy_violations}"
else
  echo "[appimage] Warning: no linuxdeploy provided, the package will only run" >&2
  echo "[appimage] on a machine that already has Neutrino's build dependencies." >&2
fi

if ! command -v "${APPIMAGE_TOOL}" >/dev/null 2>&1; then
  cat >&2 <<MSG
[appimage] Required generator '${APPIMAGE_TOOL}' is not available.
[appimage] Run scripts/ensure_appimagetool.sh to provision the pinned version.
[appimage] See docs/PACKAGING.en.md (AppImage section) for detailed instructions.
MSG
  exit 1
fi

# Prepending the pinned static runtime is what keeps the finished AppImage
# runnable on a stock Ubuntu 24.04 or Fedora 41, neither of which ships the
# libfuse.so.2 that appimagetool's built-in runtime expects.
# Only now, with every input validated and the AppDir assembled: a run that
# fails earlier used to leave the previous package deleted and no new one built.
rm -f "${OUTPUT_DIR}/${NEUTRINO_NAME}_"*-"${ARCH}.AppImage"
rm -f "${OUTPUT_DIR}/${NEUTRINO_NAME}_"*_"${ARCH}.AppImage"

runtime_args=()
if [[ -n "${APPIMAGE_RUNTIME_FILE:-}" ]]; then
  if [[ ! -f "${APPIMAGE_RUNTIME_FILE}" ]]; then
    echo "[appimage] APPIMAGE_RUNTIME_FILE does not exist: ${APPIMAGE_RUNTIME_FILE}" >&2
    exit 1
  fi
  runtime_args=(--runtime-file "${APPIMAGE_RUNTIME_FILE}")
fi

(
  cd "${OUTPUT_DIR}"
  APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGE_TOOL}" \
    ${runtime_args[@]+"${runtime_args[@]}"} \
    "$(basename "${APPDIR}")" "${APPIMAGE_NAME}"
)

echo "[appimage] Fertig. Artefakte in ${OUTPUT_DIR}"
