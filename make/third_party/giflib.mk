# giflib (for tuxwetter)

PKG_CONFIG ?= pkg-config

GIFLIB_VERSION ?= 5.2.1
GIFLIB_FORCE ?= 0
GIFLIB_ARCHIVE := $(ARCHIVE_DIR)/giflib-$(GIFLIB_VERSION).tar.gz
GIFLIB_SRC_DIR := $(SOURCES_DIR)/giflib-$(GIFLIB_VERSION)
GIFLIB_BUILD_STAMP := $(GIFLIB_SRC_DIR)/.built
GIFLIB_INSTALL_STAMP := $(GIFLIB_SRC_DIR)/.installed
GIFLIB_SYSROOT_PKGCONFIG_DIR := $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/pkgconfig
GIFLIB_SYSROOT_VERSION := $(shell PKG_CONFIG_SYSROOT_DIR=$(NEUTRINO_INSTALL_DIR) PKG_CONFIG_LIBDIR=$(GIFLIB_SYSROOT_PKGCONFIG_DIR) $(PKG_CONFIG) --modversion gif 2>/dev/null || true)
GIFLIB_HOST_VERSION := $(shell $(PKG_CONFIG) --modversion gif 2>/dev/null || true)
GIFLIB_NEEDS_BUILD := yes
ifeq ($(GIFLIB_FORCE),1)
GIFLIB_NEEDS_BUILD := yes
else ifeq ($(GIFLIB_SYSROOT_VERSION),$(GIFLIB_VERSION))
GIFLIB_NEEDS_BUILD := no
endif

ifeq ($(GIFLIB_NEEDS_BUILD),yes)
THIRD_PARTY_TARGETS += $(GIFLIB_INSTALL_STAMP)
GIFLIB_URL := https://downloads.sourceforge.net/project/giflib/giflib-5.x/giflib-$(GIFLIB_VERSION).tar.gz

$(GIFLIB_ARCHIVE):
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@echo "[third-party] Downloading giflib $(GIFLIB_VERSION)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o $@ "$(GIFLIB_URL)" || { rm -f $@; exit 1; }; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O $@ "$(GIFLIB_URL)" || { rm -f $@; exit 1; }; \
	else \
		echo "Neither curl nor wget found; install one to download giflib." >&2; \
		exit 1; \
	fi

$(GIFLIB_SRC_DIR): $(GIFLIB_ARCHIVE)
	@$(MKDIR_P) $(SOURCES_DIR)
	@echo "[third-party] Unpacking giflib $(GIFLIB_VERSION)"
	@tar -xf $< -C $(SOURCES_DIR)

$(GIFLIB_BUILD_STAMP): $(GIFLIB_SRC_DIR)
	$(call ENFORCE_GCC_VERSION)
	@echo "[third-party] Building giflib"
	@MAKEFLAGS= MFLAGS= $(MAKE) -C $(GIFLIB_SRC_DIR) CC="$(CC)" CXX="$(CXX)" AR="$(AR)" RANLIB="$(RANLIB)" \
		CFLAGS="$(CFLAGS) -fPIC" LDFLAGS="$(LDFLAGS)"
	@touch $@

$(GIFLIB_INSTALL_STAMP): $(GIFLIB_BUILD_STAMP)
	@echo "[third-party] Installing giflib into $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)"
	@MAKEFLAGS= MFLAGS= $(MAKE) -C $(GIFLIB_SRC_DIR) install \
		CC="$(CC)" CFLAGS="$(CFLAGS) -fPIC" \
		PREFIX=$(NEUTRINO_PREFIX) DESTDIR=$(NEUTRINO_INSTALL_DIR)
	@touch $@

.PHONY: deps-giflib giflib
deps-giflib giflib: $(GIFLIB_INSTALL_STAMP)
endif

ifeq ($(GIFLIB_NEEDS_BUILD),no)
.PHONY: deps-giflib giflib
deps-giflib giflib:
	@echo "[third-party] Using sysroot giflib $(GIFLIB_SYSROOT_VERSION) – kein lokaler Build nötig."
endif
