# Optional: ffmpeg build (installed into the staged prefix)

PREFERRED_FFMPEG_VERSION ?= 5.1.4
FFMPEG_VERSION ?= $(PREFERRED_FFMPEG_VERSION)
FFMPEG_FORCE ?= 0
FFMPEG_USE_SYSTEM ?= 0
FFMPEG_CONFIGURE_FLAGS ?=
FFMPEG_PREFIX := $(NEUTRINO_PREFIX)
FFMPEG_DESTDIR := $(NEUTRINO_INSTALL_DIR)
FFMPEG_INSTALL_ROOT := $(FFMPEG_DESTDIR)$(FFMPEG_PREFIX)
FFMPEG_PKGCONFIG := $(FFMPEG_DESTDIR)$(FFMPEG_PREFIX)/lib/pkgconfig
FFMPEG_HOST_VERSION := $(shell pkg-config --modversion libavcodec 2>/dev/null || true)
FFMPEG_NEEDS_BUILD := $(shell \
	if [ "$(FFMPEG_FORCE)" = "1" ]; then echo yes; \
	elif [ "$(FFMPEG_USE_SYSTEM)" = "1" ]; then \
		if [ -z "$(FFMPEG_HOST_VERSION)" ]; then echo yes; \
		elif [ "$(FFMPEG_HOST_VERSION)" != "$(FFMPEG_VERSION)" ]; then echo yes; \
		else echo no; fi; \
	else echo yes; fi)

ifeq ($(FFMPEG_NEEDS_BUILD),yes)
THIRD_PARTY_HOSTDEPS += $(FFMPEG_INSTALL_STAMP)
THIRD_PARTY_HOSTDEPS_TARGETS += ffmpeg
FFMPEG_ARCHIVE := $(ARCHIVE_DIR)/ffmpeg-$(FFMPEG_VERSION).tar.gz
FFMPEG_SRC_DIR := $(SOURCES_DIR)/ffmpeg-$(FFMPEG_VERSION)
FFMPEG_BUILD_DIR := $(FFMPEG_SRC_DIR)/build
FFMPEG_UNPACK_STAMP := $(FFMPEG_SRC_DIR)/.unpacked
FFMPEG_CONFIGURE_STAMP := $(FFMPEG_BUILD_DIR)/.configured
FFMPEG_BUILD_STAMP := $(FFMPEG_BUILD_DIR)/.built
FFMPEG_INSTALL_STAMP := $(FFMPEG_BUILD_DIR)/.installed

.PHONY: deps-ffmpeg ffmpeg
deps-ffmpeg: $(FFMPEG_INSTALL_STAMP)
ffmpeg: deps-ffmpeg

$(FFMPEG_ARCHIVE):
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@echo "[third-party] Downloading ffmpeg $(FFMPEG_VERSION)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o $@ "https://www.ffmpeg.org/releases/ffmpeg-$(FFMPEG_VERSION).tar.gz" || { rm -f $@; exit 1; }; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O $@ "https://www.ffmpeg.org/releases/ffmpeg-$(FFMPEG_VERSION).tar.gz" || { rm -f $@; exit 1; }; \
	else \
		echo "Neither curl nor wget found; install one to download ffmpeg." >&2; \
		exit 1; \
	fi

$(FFMPEG_UNPACK_STAMP): $(FFMPEG_ARCHIVE)
	@$(MKDIR_P) $(SOURCES_DIR)
	@echo "[third-party] Unpacking ffmpeg $(FFMPEG_VERSION)"
	@tar -xf $< -C $(SOURCES_DIR)
	@touch $@

$(FFMPEG_BUILD_DIR):
	@$(MKDIR_P) $@

$(FFMPEG_CONFIGURE_STAMP): $(FFMPEG_UNPACK_STAMP) | $(FFMPEG_BUILD_DIR)
	$(call ENFORCE_GCC_VERSION)
	@cd $(FFMPEG_BUILD_DIR) && \
		CC="$(CC)" CXX="$(CXX)" \
		../configure \
			--prefix=$(FFMPEG_PREFIX) \
			--enable-shared \
			--disable-static \
			--disable-debug \
			--disable-doc \
			--enable-pic \
			$(FFMPEG_CONFIGURE_FLAGS)
	@touch $@

$(FFMPEG_BUILD_STAMP): $(FFMPEG_CONFIGURE_STAMP)
	@echo "[third-party] Building ffmpeg (using -j1 to avoid race conditions)"
	@stale_ffmpeg_objs=$$(find $(FFMPEG_BUILD_DIR) -type f -name '*.o' -size 0 -print); \
	if [ -n "$$stale_ffmpeg_objs" ]; then \
		echo "[third-party] Removing zero-byte ffmpeg objects from interrupted build"; \
		printf '%s\n' "$$stale_ffmpeg_objs" | while IFS= read -r stale_obj; do \
			rm -f "$$stale_obj" "$${stale_obj%.o}.d"; \
		done; \
	fi
	@$(MAKE) -C $(FFMPEG_BUILD_DIR) -j1
	@touch $@

$(FFMPEG_INSTALL_STAMP): $(FFMPEG_BUILD_STAMP)
	@echo "[third-party] Removing previous ffmpeg install from $(FFMPEG_INSTALL_ROOT)"
	@rm -rf \
		$(FFMPEG_INSTALL_ROOT)/include/libav* \
		$(FFMPEG_INSTALL_ROOT)/include/libsw* \
		$(FFMPEG_INSTALL_ROOT)/include/libpostproc* \
		$(FFMPEG_INSTALL_ROOT)/lib/libav* \
		$(FFMPEG_INSTALL_ROOT)/lib/libsw* \
		$(FFMPEG_INSTALL_ROOT)/lib/libpostproc* \
		$(FFMPEG_INSTALL_ROOT)/lib/pkgconfig/libav* \
		$(FFMPEG_INSTALL_ROOT)/lib/pkgconfig/libsw* \
		$(FFMPEG_INSTALL_ROOT)/lib/pkgconfig/libpostproc* \
		$(FFMPEG_INSTALL_ROOT)/bin/ff* \
		$(FFMPEG_INSTALL_ROOT)/share/ffmpeg || true
	@echo "[third-party] Installing ffmpeg into $(FFMPEG_DESTDIR)$(FFMPEG_PREFIX)"
	@$(MAKE) -C $(FFMPEG_BUILD_DIR) install DESTDIR=$(FFMPEG_DESTDIR)
	@touch $@
endif

.PHONY: deps-ffmpeg-force ffmpeg-force
deps-ffmpeg-force ffmpeg-force:
	@$(MAKE) FFMPEG_FORCE=1 deps-ffmpeg

.PHONY: deps-ffmpeg-% ffmpeg-%
deps-ffmpeg-% ffmpeg-%: ## Build ffmpeg <version> locally (always, ignores host version)
	@$(MAKE) FFMPEG_FORCE=1 FFMPEG_VERSION=$* deps-ffmpeg

.PHONY: deps-ffmpeg5 ffmpeg5
deps-ffmpeg5 ffmpeg5: ## Build ffmpeg 5.1.4 locally (always, ignores host version)
	@$(MAKE) deps-ffmpeg-5.1.4
