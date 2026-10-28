# SDL3 (window, OpenGL ES context, input and audio of libstb-hal's generic
# backend). Distributions that ship SDL3 3.2 or later are used as they are;
# where it is missing (Debian 12, Ubuntu 22.04 and 24.04) it is built here and
# installed into the staged prefix, like ffmpeg.

SDL3_MIN_VERSION ?= 3.2.0
SDL3_VERSION ?= 3.4.14
SDL3_FORCE ?= 0
SDL3_CMAKE_FLAGS ?=
# PKG_CONFIG_PATH already lists the staged prefix, so an SDL3 built here by an
# earlier pass counts as present as well.
SDL3_FOUND := $(shell pkg-config --atleast-version=$(SDL3_MIN_VERSION) sdl3 2>/dev/null && echo yes)
SDL3_NEEDS_BUILD := $(if $(filter 1,$(SDL3_FORCE)),yes,$(if $(SDL3_FOUND),no,yes))

ifeq ($(SDL3_NEEDS_BUILD),yes)
SDL3_ARCHIVE := $(ARCHIVE_DIR)/SDL3-$(SDL3_VERSION).tar.gz
SDL3_URL := https://github.com/libsdl-org/SDL/releases/download/release-$(SDL3_VERSION)/SDL3-$(SDL3_VERSION).tar.gz
SDL3_SRC_DIR := $(SOURCES_DIR)/SDL3-$(SDL3_VERSION)
SDL3_BUILD_DIR := $(SDL3_SRC_DIR)/build
SDL3_UNPACK_STAMP := $(SDL3_SRC_DIR)/.unpacked
SDL3_BUILD_STAMP := $(SDL3_BUILD_DIR)/.built
SDL3_INSTALL_STAMP := $(SDL3_BUILD_DIR)/.installed
# Registered after the stamp exists, see ffmpeg.mk: THIRD_PARTY_HOSTDEPS is a
# simple variable, and libstb-hal's configure stamp depends on it.
THIRD_PARTY_HOSTDEPS += $(SDL3_INSTALL_STAMP)

.PHONY: deps-sdl3 sdl3
deps-sdl3 sdl3: $(SDL3_INSTALL_STAMP)

$(SDL3_ARCHIVE):
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@echo "[third-party] Downloading SDL3 $(SDL3_VERSION)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o $@ "$(SDL3_URL)" || { rm -f $@; exit 1; }; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O $@ "$(SDL3_URL)" || { rm -f $@; exit 1; }; \
	else \
		echo "Neither curl nor wget found; install one to download SDL3." >&2; \
		exit 1; \
	fi

$(SDL3_UNPACK_STAMP): $(SDL3_ARCHIVE)
	@$(MKDIR_P) $(SOURCES_DIR)
	@echo "[third-party] Unpacking SDL3 $(SDL3_VERSION)"
	@tar -xf $< -C $(SOURCES_DIR)
	@touch $@

# The video, input and audio backends SDL builds are the ones whose headers
# it finds; setup_deps.sh installs those of X11, Wayland, KMS, ALSA and
# PulseAudio. Tests, examples and the static library are not needed.
$(SDL3_BUILD_STAMP): $(SDL3_UNPACK_STAMP)
	$(call ENFORCE_GCC_VERSION)
	@echo "[third-party] Building SDL3 $(SDL3_VERSION)"
	@rm -rf $(SDL3_BUILD_DIR)
	@CC="$(CC)" CXX="$(CXX)" CFLAGS="$(CFLAGS)" CXXFLAGS="$(CXXFLAGS)" LDFLAGS="$(LDFLAGS)" \
		cmake -S $(SDL3_SRC_DIR) -B $(SDL3_BUILD_DIR) -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=$(NEUTRINO_PREFIX) \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DSDL_SHARED=ON \
		-DSDL_STATIC=OFF \
		-DSDL_TEST_LIBRARY=OFF \
		-DSDL_TESTS=OFF \
		-DSDL_EXAMPLES=OFF \
		$(SDL3_CMAKE_FLAGS)
	@cmake --build $(SDL3_BUILD_DIR)
	@touch $@

$(SDL3_INSTALL_STAMP): $(SDL3_BUILD_STAMP)
	@echo "[third-party] Installing SDL3 into $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)"
	@DESTDIR=$(NEUTRINO_INSTALL_DIR) cmake --install $(SDL3_BUILD_DIR)
	@touch $@
else
.PHONY: deps-sdl3 sdl3
deps-sdl3 sdl3:
	@echo "[third-party] Using SDL3 $$(pkg-config --modversion sdl3), no local build needed."
endif

.PHONY: deps-sdl3-force sdl3-force
deps-sdl3-force sdl3-force: ## Build SDL3 locally even when the host has it
	@$(MAKE) SDL3_FORCE=1 deps-sdl3
