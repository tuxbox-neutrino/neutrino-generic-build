# Path primitives.
#
# This module exists so that `Makefile.local` can be read exactly once, early,
# and still refer to the repository layout. Everything else (env.mk,
# toolchain.mk, third_party/*.mk) is included afterwards and declares its
# defaults with `?=`, so a value set in Makefile.local wins and every derived
# value is computed from it.
#
# Reading Makefile.local twice would not be a valid alternative: it is not
# idempotent. A `:=` line expands against whatever is defined at that moment,
# and a `+=` line would take effect twice.
#
# ROOT_DIR is the anchor and is assigned with `:=` on purpose -- it is the
# directory make was started from. The remaining paths derive from it lazily,
# so overriding ROOT_DIR in Makefile.local still moves all of them.

ROOT_DIR := $(realpath $(CURDIR))
SOURCES_DIR ?= $(ROOT_DIR)/sources
BUILD_DIR ?= $(ROOT_DIR)/build
OUTPUT_DIR ?= $(ROOT_DIR)/artifacts
CACHE_DIR ?= $(ROOT_DIR)/.cache
ARCHIVE_DIR ?= $(ROOT_DIR)/archive
LOG_DIR ?= $(ROOT_DIR)/logs
VENV_DIR ?= $(ROOT_DIR)/.venv

MKDIR_P ?= mkdir -p
RM_RF ?= rm -rf
