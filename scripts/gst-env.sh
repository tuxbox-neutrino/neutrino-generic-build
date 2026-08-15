#!/usr/bin/env bash
# GStreamer environment detection for neutrino run scripts.
#
# Source this file, then use:
#   GST_DETECTED_PLUGIN_DIRS  - array of host plugin directories
#   GST_DETECTED_SCANNER      - path to gst-plugin-scanner (or empty)
#   GST_DETECTED_SCANNER_DIR  - directory containing the scanner (for bind-mounting)
#   join_colon()              - join arguments with ':' (from shell-util.sh)

# shellcheck source=shell-util.sh
source "$(dirname "${BASH_SOURCE[0]}")/shell-util.sh"

_gst_multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null \
                  || gcc -dumpmachine 2>/dev/null \
                  || true)"

GST_DETECTED_PLUGIN_DIRS=()

if [[ -d /usr/lib/gstreamer-1.0 ]]; then
  GST_DETECTED_PLUGIN_DIRS+=("/usr/lib/gstreamer-1.0")
fi
if [[ -n "${_gst_multiarch}" && -d "/usr/lib/${_gst_multiarch}/gstreamer-1.0" ]]; then
  GST_DETECTED_PLUGIN_DIRS+=("/usr/lib/${_gst_multiarch}/gstreamer-1.0")
fi

# Fallback: pkg-config
if [[ ${#GST_DETECTED_PLUGIN_DIRS[@]} -eq 0 ]]; then
  _gst_pkgdir="$(pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || true)"
  if [[ -n "${_gst_pkgdir}" && -d "${_gst_pkgdir}" ]]; then
    GST_DETECTED_PLUGIN_DIRS+=("${_gst_pkgdir}")
  fi
fi

GST_DETECTED_SCANNER=""
GST_DETECTED_SCANNER_DIR=""

if [[ -n "${_gst_multiarch}" \
      && -x "/usr/lib/${_gst_multiarch}/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner" ]]; then
  GST_DETECTED_SCANNER="/usr/lib/${_gst_multiarch}/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
  GST_DETECTED_SCANNER_DIR="/usr/lib/${_gst_multiarch}/gstreamer1.0"
elif [[ -x /usr/lib/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner ]]; then
  GST_DETECTED_SCANNER="/usr/lib/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
  GST_DETECTED_SCANNER_DIR="/usr/lib/gstreamer1.0"
fi
