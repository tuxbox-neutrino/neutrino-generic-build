#!/usr/bin/env bash
set -euo pipefail

# Tiny helper to build a host GCC toolchain into artifacts/toolchains.
# Patches in files/gcc-<version>/toolchain/*.patch are applied right after unpacking.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="15.2.0"
JOBS="$(nproc)"
PREFIX=""
PROGRAM_SUFFIX=""
LANGUAGES="c,c++"
KEEP_SOURCES=0

usage() {
  cat <<'EOF'
Usage: scripts/build_gcc.sh [--version X.Y.Z] [--jobs N] [--prefix DIR] [--program-suffix SUF] [--languages LIST] [--keep-sources]

Defaults: version=15.2.0, languages=c,c++, prefix=./artifacts/toolchains/gcc-<version>, program-suffix=-<major>, jobs=$(nproc)
Sources/build directories are cleaned only if BUILD_GCC_ALLOW_DELETE=1 is set; use --keep-sources to reuse an existing tree (patches are skipped when the stamp file exists).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"; shift 2;;
    --jobs)
      JOBS="$2"; shift 2;;
    --prefix)
      PREFIX="$2"; shift 2;;
    --program-suffix)
      PROGRAM_SUFFIX="$2"; shift 2;;
    --languages)
      LANGUAGES="$2"; shift 2;;
    --keep-sources)
      KEEP_SOURCES=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1;;
  esac
done

MAJOR="${VERSION%%.*}"
SOURCES_DIR="$ROOT_DIR/sources"
BUILD_ROOT="$ROOT_DIR/build"
ARCHIVE_DIR="$ROOT_DIR/archive"
SRC_DIR="$SOURCES_DIR/gcc-$VERSION"
BUILD_DIR="$BUILD_ROOT/gcc-$VERSION"
PREFIX="${PREFIX:-$ROOT_DIR/artifacts/toolchains/gcc-$VERSION}"
PROGRAM_SUFFIX="${PROGRAM_SUFFIX:--$MAJOR}"
PATCH_DIR="$ROOT_DIR/files/gcc-$VERSION/toolchain"
PATCH_STAMP="$SRC_DIR/.toolchain-patches-applied"
ARCHIVE="$ARCHIVE_DIR/gcc-$VERSION.tar.xz"
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-$VERSION/gcc-$VERSION.tar.xz"
EXTRA_CONFIG_ARGS=()

echo "[gcc] Version      : $VERSION"
echo "[gcc] Prefix       : $PREFIX"
echo "[gcc] Program suffix: $PROGRAM_SUFFIX"
echo "[gcc] Languages    : $LANGUAGES"
echo "[gcc] Jobs         : $JOBS"

mkdir -p "$SOURCES_DIR" "$BUILD_ROOT" "$ARCHIVE_DIR"

if [[ $KEEP_SOURCES -eq 0 ]]; then
  if [[ "${BUILD_GCC_ALLOW_DELETE:-0}" != "1" ]]; then
    echo "[gcc] Refusing to delete sources/build without BUILD_GCC_ALLOW_DELETE=1." >&2
    echo "[gcc] Set BUILD_GCC_ALLOW_DELETE=1 or pass --keep-sources." >&2
    exit 1
  fi
  echo "[gcc] Cleaning source + build directories"
  rm -rf "$SRC_DIR" "$BUILD_DIR"
else
  echo "[gcc] Reusing existing sources (if present); build directory will be rebuilt"
  rm -rf "$BUILD_DIR"
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "[gcc] Fetching tarball $ARCHIVE"
  # -f matters: without it an HTTP error page is written to $ARCHIVE and curl
  # still exits 0, so the next run reuses the poisoned file and fails in tar.
  curl -fL --retry 3 "$GCC_URL" -o "$ARCHIVE" || { rm -f "$ARCHIVE"; exit 1; }
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "[gcc] Extracting sources to $SRC_DIR"
  tar -xf "$ARCHIVE" -C "$SOURCES_DIR"
else
  echo "[gcc] Using existing sources at $SRC_DIR"
fi

if [[ -d "$PATCH_DIR" ]]; then
  if [[ $KEEP_SOURCES -eq 1 && -f "$PATCH_STAMP" ]]; then
    echo "[gcc] Patch stamp present ($PATCH_STAMP), skipping reapply (delete to force)."
  else
    echo "[gcc] Applying toolchain patches from $PATCH_DIR"
    for p in "$PATCH_DIR"/*.patch; do
      [[ -e "$p" ]] || continue
      echo "       - $(basename "$p")"
      patch -p1 -d "$SRC_DIR" < "$p"
    done
    touch "$PATCH_STAMP"
  fi
fi

# Older GCC (<=9) trips over modern kernel headers in libsanitizer; skip it there.
case "$MAJOR" in
  8|9) EXTRA_CONFIG_ARGS+=(--disable-libsanitizer) ;;
esac

mkdir -p "$BUILD_DIR" "$PREFIX"
echo "[gcc] Configuring in $BUILD_DIR"
cd "$BUILD_DIR"
"$SRC_DIR"/configure \
  --prefix="$PREFIX" \
  --program-suffix="$PROGRAM_SUFFIX" \
  --disable-multilib \
  --disable-nls \
  --enable-languages="$LANGUAGES" \
  --disable-bootstrap \
  --enable-checking=release \
  "${EXTRA_CONFIG_ARGS[@]}"

echo "[gcc] Building"
make -j"$JOBS"
echo "[gcc] Installing"
make install
echo "[gcc] Done. Binaries live in $PREFIX/bin (e.g. gcc${PROGRAM_SUFFIX})."
