# Dependency handling: system packages, Python, Node, and toolchains.

DEPS_LOG ?= $(LOG_DIR)/deps.log

DVBSI_GIT_URL ?= https://git.code.sf.net/p/tuxbox-cvs/libdvbsi++
DVBSI_GIT_REF ?= master
DVBSI_VERSION ?= $(DVBSI_GIT_REF)
DVBSI_FORCE ?= 0
DVBSI_SRC_DIR := $(SOURCES_DIR)/libdvbsi++
DVBSI_BUILD_DIR := $(BUILD_DIR)/libdvbsi
DVBSI_CONFIGURE_STAMP := $(DVBSI_BUILD_DIR)/.configured
DVBSI_BUILD_STAMP := $(DVBSI_BUILD_DIR)/.built
DVBSI_INSTALL_STAMP := $(DVBSI_BUILD_DIR)/.installed
DVBSI_HOST_VERSION := $(shell pkg-config --modversion libdvbsi++ 2>/dev/null || true)
DVBSI_NEEDS_BUILD := $(shell \
	if [ "$(DVBSI_FORCE)" = "1" ]; then echo yes; \
	elif [ -z "$(DVBSI_HOST_VERSION)" ]; then echo yes; \
	elif [ -n "$(DVBSI_VERSION)" ] && [ "$(DVBSI_HOST_VERSION)" != "$(DVBSI_VERSION)" ]; then echo yes; \
	else echo no; fi)
DVBSI_PREREQ := $(if $(filter yes,$(DVBSI_NEEDS_BUILD)),$(DVBSI_INSTALL_STAMP),)

.PHONY: deps
# Deliberately sequenced in two phases instead of listing all three as
# prerequisites: with the auto-injected -j, make builds sibling prerequisites in
# parallel, so the third-party downloads started while the package installation
# that provides curl/wget was still running. On a host without curl that failed
# deterministically ("Neither curl nor wget found").
deps: ## Ensure host dependencies are available
	@$(MAKE) $(VENV_DIR)/.ready
	@$(MAKE) $(DVBSI_PREREQ) third-party
	@$(MKDIR_P) $(OUTPUT_DIR)
	@if [ -f "$(NEUTRINO_INSTALL_STAMP)" ]; then \
		$(MAKE) runtime-sync; \
	else \
		echo "[deps] runtime-sync übersprungen (Neutrino noch nicht gebaut)."; \
	fi

$(DVBSI_SRC_DIR):
	@$(MKDIR_P) $(SOURCES_DIR)
	@if [ ! -d "$@/.git" ]; then \
		echo "[deps] Cloning libdvbsi++ ($(DVBSI_GIT_REF))"; \
		git clone --depth 1 --branch $(DVBSI_GIT_REF) $(DVBSI_GIT_URL) "$@"; \
	else \
		echo "[deps] Updating libdvbsi++ ($(DVBSI_GIT_REF))"; \
		git -C "$@" fetch --depth 1 origin $(DVBSI_GIT_REF); \
		git -C "$@" checkout $(DVBSI_GIT_REF); \
		git -C "$@" reset --hard origin/$(DVBSI_GIT_REF); \
	fi

$(DVBSI_BUILD_DIR):
	@$(MKDIR_P) $@

$(DVBSI_CONFIGURE_STAMP): $(DVBSI_SRC_DIR) | $(DVBSI_BUILD_DIR) $(VENV_DIR)/.ready
ifeq ($(DVBSI_NEEDS_BUILD),yes)
	@$(MKDIR_P) $(NEUTRINO_INSTALL_DIR)
	@echo "[deps] Configuring libdvbsi++"
	@cd $(DVBSI_SRC_DIR) && ./autogen.sh >/dev/null
	@cd $(DVBSI_BUILD_DIR) && \
		$(DVBSI_SRC_DIR)/configure \
			--prefix=$(NEUTRINO_PREFIX) \
			--libdir=$(NEUTRINO_PREFIX)/lib \
			--enable-maintainer-mode \
			PKG_CONFIG_PATH=$(PKG_CONFIG_PATH)
	@touch $@
else
	@echo "[deps] Skipping libdvbsi++ build (using host version $(DVBSI_HOST_VERSION))"
	@touch $@
endif

# Hash-based rebuild detection for libdvbsi++
# The 2>/dev/null must cover cd as well: on a fresh clone sources/libdvbsi++
# does not exist yet, and because this is an immediate assignment the shell
# error was printed on *every* make invocation.
DVBSI_GIT_HASH := $(shell cd $(DVBSI_SRC_DIR) 2>/dev/null && git rev-parse HEAD 2>/dev/null)
DVBSI_BUILT_HASH := $(shell cat $(DVBSI_BUILD_DIR)/.built_hash 2>/dev/null)
DVBSI_SOURCE_CHANGED := $(shell [ -n "$(DVBSI_GIT_HASH)" ] && [ "$(DVBSI_GIT_HASH)" != "$(DVBSI_BUILT_HASH)" ] && echo yes)

$(DVBSI_BUILD_STAMP): $(DVBSI_CONFIGURE_STAMP) $(if $(DVBSI_SOURCE_CHANGED),FORCE)
ifeq ($(DVBSI_NEEDS_BUILD),yes)
	@echo "[deps] Building libdvbsi++"
	@$(MAKE) -C $(DVBSI_BUILD_DIR)
	@echo "$(DVBSI_GIT_HASH)" > $(DVBSI_BUILD_DIR)/.built_hash
	@touch $@
else
	@touch $@
endif

$(DVBSI_INSTALL_STAMP): $(DVBSI_BUILD_STAMP)
ifeq ($(DVBSI_NEEDS_BUILD),yes)
	@echo "[deps] Installing libdvbsi++ into $(NEUTRINO_INSTALL_DIR)"
	@$(MAKE) -C $(DVBSI_BUILD_DIR) install DESTDIR=$(NEUTRINO_INSTALL_DIR)
	@touch $@
else
	@touch $@
endif

$(VENV_DIR)/.ready: scripts/setup_deps.sh
	@$(MKDIR_P) $(LOG_DIR)
	@echo "[deps] Installing system and Python dependencies (log: $(DEPS_LOG))"
	@ALLOW_NON_ROOT=$(ALLOW_NON_ROOT) \
		LOG_FILE=$(DEPS_LOG) \
		VENV_DIR=$(VENV_DIR) \
		./scripts/setup_deps.sh --mode=auto
	@touch $@

.PHONY: deps-update-internal
deps-update-internal: scripts/setup_deps.sh ## Update already installed dependencies
	@ALLOW_NON_ROOT=$(ALLOW_NON_ROOT) \
		VENV_DIR=$(VENV_DIR) \
		./scripts/setup_deps.sh --mode=update

.PHONY: deps-doctor
deps-doctor: scripts/setup_deps.sh ## Print environment diagnostics without modifying the system
	@ALLOW_NON_ROOT=$(ALLOW_NON_ROOT) \
		VENV_DIR=$(VENV_DIR) \
		./scripts/setup_deps.sh --mode=doctor

.PHONY: deps-clean
deps-clean:
	@$(RM_RF) $(DVBSI_BUILD_DIR)

.PHONY: deps-distclean
deps-distclean:
	@$(RM_RF) $(VENV_DIR) $(DVBSI_BUILD_DIR)
	@if [ -d "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/include/dvbsi++" ]; then $(RM_RF) "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/include/dvbsi++"; fi
	@if [ -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.a" ]; then rm -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.a"; fi
	@if [ -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.so" ]; then rm -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.so"; fi
	@if [ -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.so.1" ]; then rm -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.so.1"; fi
	@if [ -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.so.1.0.0" ]; then rm -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/libdvbsi++.so.1.0.0"; fi
	@if [ -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/pkgconfig/libdvbsi++.pc" ]; then rm -f "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/pkgconfig/libdvbsi++.pc"; fi
