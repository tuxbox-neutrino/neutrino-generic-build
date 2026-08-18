# Common environment configuration shared across modular makefiles.
#
# This file holds only the `?=` DEFAULTS (the overridable inputs). It is
# included after make/paths.mk and BEFORE Makefile.local, so a value set in
# Makefile.local can both override any default here and reference one (e.g.
# `N_PLUGIN_DIR := $(N_PREFIX)/oem/plugins`). The `:=` values derived from these
# inputs live in make/env-derive.mk, which is included AFTER Makefile.local so
# an override (NEUTRINO_INSTALL_DIR, N_PREFIX, ...) actually reaches them.

# Renamed from gui-neutrino. The old URL still redirects, but only until
# something else claims that name under the organisation -- then the clone would
# quietly pull a different repository. So the current name, not the redirect.
NEUTRINO_GIT_URL ?= https://github.com/tuxbox-neutrino/neutrino.git
NEUTRINO_BRANCH ?= master
NEUTRINO_SRC_DIR ?= $(SOURCES_DIR)/neutrino
NEUTRINO_BUILD_DIR ?= $(BUILD_DIR)/neutrino
NEUTRINO_INSTALL_DIR ?= $(OUTPUT_DIR)/sysroot
NEUTRINO_PREFIX ?= /usr
NEUTRINO_RUNTIME_PREFIX ?= $(ROOT_DIR)/root
NEUTRINO_LUA_FLAVOR ?= luajit
NEUTRINO_WEB_PORT ?= 31344
NEUTRINO_WEB_HOST ?= 0.0.0.0

# Whether the install step also mirrors the staged tree into
# NEUTRINO_RUNTIME_PREFIX so that "make run" finds it. That mirror is a
# developer convenience and writes to an absolute host path, so any build that
# bakes a foreign prefix into the binary (the AppImage variant below) has to
# switch it off -- otherwise the install would try to populate /opt/neutrino on
# the build machine and fail without root.
NEUTRINO_STAGE_RUNTIME ?= 1

# On the box Neutrino signals its follow-up action (poweroff/reboot/restart)
# through the process exit status; that trips "set -e" and make on the PC. Ask
# Neutrino for POSIX exit codes here (clean shutdown => 0) and read the action
# from the action file instead. The action file lives inside the build tree
# rather than /tmp so it cannot collide with a running box; concurrent runs of
# different variants are already prevented by run-neutrino.sh's single-instance
# guard (it is exported, so the value is fixed to the base build dir here).
NEUTRINO_EXIT_CODES ?= posix
NEUTRINO_EXIT_ACTION_FILE ?= $(NEUTRINO_BUILD_DIR)/neutrino.exit-action

LIBSTB_HAL_DIR ?= $(SOURCES_DIR)/libstb-hal
LIBSTB_HAL_BUILD_DIR ?= $(BUILD_DIR)/libstb-hal
LIBSTB_HAL_CONFIGURE_FLAGS ?=

ALLOW_NON_ROOT ?= 0
RUN_NEUTRINO_DISPLAY ?= $(if $(DISPLAY),$(DISPLAY),:99) # prefer host DISPLAY, fallback to headless :99
NEUTRINO_HEADLESS_BACKEND ?= xvfb
NEUTRINO_CONFIGURE_FLAGS ?=
NEUTRINO_BASE_CFLAGS ?= -funsigned-char -rdynamic -DPEDANTIC_VALGRIND_SETUP -DDYNAMIC_LUAPOSIX -D__KERNEL_STRICT_NAMES -D__STDC_FORMAT_MACROS -D__STDC_CONSTANT_MACROS -DASSUME_MDEV -DTEST_MENU
NEUTRINO_WARN_OPTS ?= -Wall -Wextra -Wsign-compare -Wno-psabi -Wunused-parameter -Wredundant-decls -Wunused-function -Wdeprecated-declarations -Wuninitialized -Wmaybe-uninitialized -Warray-bounds -Wformat-security -Wshadow -Wno-cast-function-type -Wno-redundant-decls
NEUTRINO_WARN_OPTS_CXX ?= -Wno-class-memaccess
NEUTRINO_CFLAGS_APPEND ?=
NEUTRINO_CXXFLAGS_APPEND ?=
# Compiler options that must not end up in Neutrino's recorded build flags.
# Neutrino's configure copies CXXFLAGS verbatim into USED_CXXFLAGS, which the
# GUI shows and which therefore ships inside the binary; CPPFLAGS is not
# recorded, so options that only matter to the build belong here.
NEUTRINO_CPPFLAGS_APPEND ?=
NEUTRINO_GDB_AUTORUN ?= 1
NEUTRINO_GDB_COMMANDS ?=

N_PREFIX ?= $(NEUTRINO_PREFIX)
N_SYSCONFDIR ?= $(N_PREFIX)/etc
N_LOCALSTATEDIR ?= $(N_PREFIX)/var
N_CONFIG_DIR ?= $(N_SYSCONFDIR)/neutrino/config
N_CONTROLDIR ?= $(N_PREFIX)/share/tuxbox/neutrino/control
N_CONTROLDIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/control
N_DATADIR ?= $(N_PREFIX)/share/tuxbox
N_DATADIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox
N_FLAGDIR ?= $(N_LOCALSTATEDIR)/etc
N_FONTDIR ?= $(N_PREFIX)/share/fonts
N_FONTDIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/fonts
N_GAMES_DIR ?= $(N_SYSCONFDIR)/neutrino/plugins
N_HOSTED_HTTPDDIR ?= /mnt/hosted
N_ICONS_DIR ?= $(N_PREFIX)/share/tuxbox/neutrino/icons
N_ICONS_DIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/icons
N_LIBDIR ?= $(N_PREFIX)/lib/tuxbox
N_LOCALEDIR ?= $(N_PREFIX)/share/tuxbox/neutrino/locale
N_LOCALEDIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/locale
N_LOGODIR ?= $(N_PREFIX)/share/tuxbox/neutrino/icons/logo
N_LOGODIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/icons/logo
# Must match what Neutrino's configure actually uses (see the --with-plugindir
# / --with-luaplugindir flags in make/neutrino.mk, i.e. share/tuxbox/neutrino/*)
# and the paths plugins/Makefile installs into. These values are exported as the
# install contract for plugin builds; the missing "tuxbox/" segment (and the lua
# path pointing at the C plugin dir) meant a plugin honouring the contract would
# have installed where Neutrino never looks.
N_PLUGIN_DIR ?= $(N_PREFIX)/share/tuxbox/neutrino/plugins
N_PLUGIN_DIR_MNT ?= /mnt/plugins
N_PLUGIN_DIR_VAR ?= $(N_SYSCONFDIR)/neutrino/plugins
N_LUAPLUGIN_DIR ?= $(N_PREFIX)/share/tuxbox/neutrino/luaplugins
N_LUAPLUGIN_DIR_VAR ?= $(N_PLUGIN_DIR_VAR)
N_PRIVATE_HTTPDDIR ?= $(N_PREFIX)/share/tuxbox/neutrino/httpd
N_PUBLIC_HTTPDDIR ?= $(N_LOCALSTATEDIR)/tuxbox/httpd
N_THEMESDIR ?= $(N_PREFIX)/share/tuxbox/neutrino/themes
N_THEMESDIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/themes
N_WEBRADIO_DIR ?= $(N_PREFIX)/share/tuxbox/neutrino/plugins/webradio
N_WEBRADIO_DIR_VAR ?= $(N_SYSCONFDIR)/neutrino/plugins/webradio
N_WEBTV_DIR ?= $(N_PREFIX)/share/tuxbox/neutrino/webtv
N_WEBTV_DIR_VAR ?= $(N_SYSCONFDIR)/neutrino/webtv
N_ZAPITDIR ?= $(N_CONFIG_DIR)/zapit
N_LCD4L_ICONSDIR ?= $(N_PREFIX)/share/tuxbox/neutrino/lcd/icons
N_LCD4L_ICONSDIR_VAR ?= $(N_LOCALSTATEDIR)/tuxbox/lcd/icons

PLUGIN_PKG_CONFIG_SYSROOT_DIR ?=
# Deferred on purpose: PKG_CONFIG_PATH is derived in env-derive.mk (after
# Makefile.local), and `?=` keeps this recursive so it picks up that value.
PLUGIN_PKG_CONFIG_PATH ?= $(PKG_CONFIG_PATH)
PLUGIN_PROGRAM_PREFIX ?=
PLUGIN_PROGRAM_SUFFIX ?=
PLUGIN_PROGRAM_TRANSFORM_NAME ?=
PLUGIN_PROGRAM_NAME ?=

# PYTHON/PIP are intentionally not defaulted here. env-derive.mk resolves them
# after Makefile.local using $(origin ...), so an explicit `PYTHON := python3`
# there can opt out of the project venv -- a plain `?=` default would make that
# indistinguishable from "unset".
NODE ?= node
NPM ?= npm
GDB ?= gdb
VALGRIND ?= valgrind
