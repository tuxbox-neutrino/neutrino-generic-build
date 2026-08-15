# LuaJIT (optional)

ifeq ($(NEUTRINO_LUA_FLAVOR),luajit)
LUAJIT_VERSION ?= 2.1.0-beta3
# Upstream deleted all release tags, so .../refs/tags/v2.1.0-beta3.tar.gz now
# answers 404. Pin a commit on the v2.1 branch instead: it is reproducible and
# stays valid regardless of upstream tagging policy.
LUAJIT_SOURCE_REF ?= 346ab587cb235b4ef0b5777b4cd29009808d0cc0
LUAJIT_SOURCE_URL ?= https://github.com/LuaJIT/LuaJIT/archive/$(LUAJIT_SOURCE_REF).tar.gz
LUAJIT_FORCE ?= 0
LUAJIT_HOST_VERSION := $(shell pkg-config --modversion luajit 2>/dev/null || true)
LUAJIT_HOST_SERIES := $(shell pkg-config --modversion luajit 2>/dev/null | cut -d. -f1,2)
# Any host LuaJIT from the 2.1 series is ABI-compatible for our purposes.
# Demanding an exact string match forced a source build on every distro whose
# package version differs by so much as a suffix.
# Expressed with make functions on purpose: a shell `case` cannot be used inside
# $(shell ...) because its ")" terminates the make expression.
# $(strip ...) is required: the line continuation would otherwise leave leading
# whitespace, and the "ifeq ($(LUAJIT_NEEDS_BUILD),yes)" below would never match.
LUAJIT_NEEDS_BUILD := $(strip $(if $(filter 1,$(LUAJIT_FORCE)),yes,\
	$(if $(LUAJIT_HOST_VERSION),$(if $(filter 2.1,$(LUAJIT_HOST_SERIES)),no,yes),yes)))
# Keyed on the source ref, not the version: the previous non-`-f` curl wrote a
# 404 page to LuaJIT-$(LUAJIT_VERSION).tar.gz on any host that tried the old
# URL. Reusing that name would let make treat the poisoned archive as present
# and never re-download it, so the repair would surface as a tar error instead.
LUAJIT_ARCHIVE := $(ARCHIVE_DIR)/LuaJIT-$(LUAJIT_SOURCE_REF).tar.gz
LUAJIT_SRC_DIR := $(SOURCES_DIR)/LuaJIT-$(LUAJIT_SOURCE_REF)
LUAJIT_BUILD_DIR := $(LUAJIT_SRC_DIR)
LUAJIT_UNPACK_STAMP := $(LUAJIT_SRC_DIR)/.unpacked
LUA_DEP_STAMP := $(LUAJIT_SRC_DIR)/.installed

ifeq ($(LUAJIT_NEEDS_BUILD),yes)
THIRD_PARTY_TARGETS += $(LUA_DEP_STAMP)

$(LUAJIT_ARCHIVE):
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@echo "[third-party] Downloading LuaJIT $(LUAJIT_VERSION)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o $@ "$(LUAJIT_SOURCE_URL)" || { rm -f $@; exit 1; }; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O $@ "$(LUAJIT_SOURCE_URL)" || { rm -f $@; exit 1; }; \
	else \
		echo "Neither curl nor wget found; install one to download LuaJIT." >&2; \
		exit 1; \
	fi

$(LUAJIT_UNPACK_STAMP): $(LUAJIT_ARCHIVE)
	@$(MKDIR_P) $(LUAJIT_SRC_DIR)
	@echo "[third-party] Unpacking LuaJIT $(LUAJIT_VERSION)"
	@tar -xf $< -C $(LUAJIT_SRC_DIR) --strip-components=1
	@touch $@

$(LUA_DEP_STAMP): $(LUAJIT_UNPACK_STAMP)
	$(call ENFORCE_GCC_VERSION)
	@$(MKDIR_P) $(LUA_INSTALL_PREFIX) $(LUA_PKGCONFIG_DIR)
	@echo "[third-party] Building LuaJIT $(LUAJIT_VERSION)"
	@$(MAKE) -C $(LUAJIT_BUILD_DIR) MAKEFLAGS= clean >/dev/null 2>&1 || true
	@$(MAKE) -C $(LUAJIT_BUILD_DIR) MAKEFLAGS= \
		CC="$(CC)" XCFLAGS="$(CFLAGS) -fPIC" \
		TARGET_LDFLAGS="$(LDFLAGS)" \
		PREFIX="$(LUA_INSTALL_PREFIX)"
	@echo "[third-party] Installing LuaJIT into $(LUA_INSTALL_PREFIX)"
	@$(MAKE) -C $(LUAJIT_BUILD_DIR) MAKEFLAGS= PREFIX="$(LUA_INSTALL_PREFIX)" install
	@sed \
		-e "s|@PREFIX@|$(LUA_INSTALL_PREFIX)|g" \
		-e "s|@MULTILIB@||g" \
		"$(LUAJIT_BUILD_DIR)/etc/luajit.pc" > "$(LUA_PKGCONFIG_DIR)/luajit.pc"
	@luajit_bin="$$(cd "$(LUA_INSTALL_PREFIX)/bin" && ls -1 luajit-* 2>/dev/null | head -1)"; \
		if [ -n "$$luajit_bin" ]; then \
			ln -sf "$$luajit_bin" "$(LUA_INSTALL_PREFIX)/bin/luajit"; \
		fi
	@for hdr in lua.h luaconf.h lauxlib.h lualib.h lua.hpp luajit.h; do \
		ln -sf "luajit-2.1/$$hdr" "$(LUA_INSTALL_PREFIX)/include/$$hdr"; \
	done
	@ln -sf libluajit-5.1.a "$(LUA_INSTALL_PREFIX)/lib/liblua.a"
	@ln -sf libluajit-5.1.so "$(LUA_INSTALL_PREFIX)/lib/liblua.so"
	@printf 'prefix=%s\nexec_prefix=$${prefix}\nlibdir=$${exec_prefix}/lib\nincludedir=$${prefix}/include\n\nName: Lua\nDescription: LuaJIT (Lua 5.1 compatible)\nVersion: %s\nLibs: -L$${libdir} -lluajit-5.1\nCflags: -I$${includedir}\n' \
		"$(LUA_INSTALL_PREFIX)" "$(LUAJIT_VERSION)" > "$(LUA_PKGCONFIG_DIR)/lua.pc"
	@touch $@
else
LUA_DEP_STAMP :=
endif
endif
