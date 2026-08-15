# Standard Lua (default)

ifeq ($(NEUTRINO_LUA_FLAVOR),lua)
LUA_VERSION ?= 5.4.6
LUA_SOURCE_URL ?= https://www.lua.org/ftp/lua-$(LUA_VERSION).tar.gz
LUA_FORCE ?= 0
LUA_HOST_VERSION := $(shell pkg-config --modversion lua 2>/dev/null || pkg-config --modversion lua5.4 2>/dev/null || pkg-config --modversion lua5.3 2>/dev/null || true)
LUA_NEEDS_BUILD := $(shell \
	if [ "$(LUA_FORCE)" = "1" ]; then echo yes; \
	elif [ -z "$(LUA_HOST_VERSION)" ]; then echo yes; \
	elif [ "$(LUA_HOST_VERSION)" != "$(LUA_VERSION)" ]; then echo yes; \
	else echo no; fi)
LUA_ARCHIVE := $(ARCHIVE_DIR)/lua-$(LUA_VERSION).tar.gz
LUA_SRC_DIR := $(SOURCES_DIR)/lua-$(LUA_VERSION)
LUA_BUILD_DIR := $(LUA_SRC_DIR)
LUA_UNPACK_STAMP := $(LUA_SRC_DIR)/.unpacked
LUA_DEP_STAMP := $(LUA_SRC_DIR)/.installed

ifeq ($(LUA_NEEDS_BUILD),yes)
THIRD_PARTY_TARGETS += $(LUA_DEP_STAMP)

$(LUA_ARCHIVE):
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@echo "[third-party] Downloading Lua $(LUA_VERSION)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o $@ "$(LUA_SOURCE_URL)" || { rm -f $@; exit 1; }; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O $@ "$(LUA_SOURCE_URL)" || { rm -f $@; exit 1; }; \
	else \
		echo "Neither curl nor wget found; install one to download Lua." >&2; \
		exit 1; \
	fi

$(LUA_UNPACK_STAMP): $(LUA_ARCHIVE)
	@$(MKDIR_P) $(SOURCES_DIR)
	@echo "[third-party] Unpacking Lua $(LUA_VERSION)"
	@tar -xf $< -C $(SOURCES_DIR)
	@touch $@

$(LUA_DEP_STAMP): $(LUA_UNPACK_STAMP)
	$(call ENFORCE_GCC_VERSION)
	@$(MKDIR_P) $(LUA_INSTALL_PREFIX) $(LUA_PKGCONFIG_DIR)
	@echo "[third-party] Building Lua $(LUA_VERSION)"
	@$(MAKE) -C $(LUA_BUILD_DIR) MAKEFLAGS= clean >/dev/null 2>&1 || true
	@$(MAKE) -C $(LUA_BUILD_DIR) MAKEFLAGS= \
		CC="$(CC)" \
		MYCFLAGS="$(CFLAGS) -fPIC" MYLDFLAGS="$(LDFLAGS)" \
		linux
	@echo "[third-party] Installing Lua into $(LUA_INSTALL_PREFIX)"
	@$(MAKE) -C $(LUA_BUILD_DIR) MAKEFLAGS= \
		TO_LIB="liblua.a" \
		INSTALL_TOP="$(LUA_INSTALL_PREFIX)" \
		install
	@printf 'prefix=%s\nexec_prefix=$${prefix}\nlibdir=$${exec_prefix}/lib\nincludedir=$${prefix}/include\n\nName: Lua\nDescription: Embedded scripting language\nVersion: %s\nLibs: -L$${libdir} -llua -lm -ldl\nCflags: -I$${includedir}\n' \
		"$(LUA_INSTALL_PREFIX)" "$(LUA_VERSION)" > "$(LUA_PKGCONFIG_DIR)/lua.pc"
	@touch $@
else
LUA_DEP_STAMP :=
endif
endif
