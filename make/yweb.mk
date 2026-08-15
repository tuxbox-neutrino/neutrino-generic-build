# =============================================================================
# yWeb Quick Install Target
# =============================================================================
#
# This target allows rapid development of the yWeb interface without requiring
# a full neutrino rebuild.
#
# It does NOT copy from the source tree. yWeb files carry build-time
# placeholders (%(CONFIGDIR), %(PRIVATE_HTTPDDIR), ...) that only neutrino's
# install-data-hook expands; copying the raw sources into the webroot leaves
# them in place, which makes scripts/Y_Tools.sh a shell syntax error and points
# the Y_Blocks*.txt templates at paths that do not exist. So we run neutrino's
# own install into the staging tree and mirror that expanded result.
#
# Note: a file only reaches the webroot once it is listed in the matching
# data/y-web Makefile.am.
#
# Usage:
#   make yweb-install          - Install yWeb files to sysroot and runtime
#   make yweb-install-sysroot  - Install only to sysroot (no runtime sync)
#
# After running yweb-install, simply refresh your browser (F5) to see changes.
#
# Prerequisites:
#   - neutrino must have been built at least once (to create directory structure)
#   - runtime-sync should have been run at least once
#
# =============================================================================

# Source directory containing yWeb files
YWEB_SRC_DIR := $(NEUTRINO_SRC_DIR)/data/y-web

# Staging webroot produced by neutrino's "make install" with DESTDIR.
# PRIVATE_HTTPDDIR is configured as an absolute runtime path, so the staged
# copy lands under DESTDIR + that path. It is the only tree whose placeholders
# have been expanded.
YWEB_SYSROOT_DIR := $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_RUNTIME_TUXBOX)/neutrino/httpd

# Destination in runtime (where nhttpd actually serves from)
YWEB_RUNTIME_DIR := $(NEUTRINO_RUNTIME_PREFIX_ABS)$(N_PRIVATE_HTTPDDIR)

.PHONY: yweb-install
yweb-install: yweb-install-sysroot yweb-install-runtime
	@echo "[yweb-install] Done. Refresh browser to see changes."

.PHONY: yweb-install-sysroot
yweb-install-sysroot:
	@# Guard and action share one shell: each recipe line gets its own, so an
	@# "exit 0" on a separate line would not skip what follows.
	@if [ ! -d "$(NEUTRINO_BUILD_DIR)/data/y-web" ]; then \
		echo "[yweb-install] Build tree not found: $(NEUTRINO_BUILD_DIR)/data/y-web"; \
		echo "[yweb-install] Run 'make neutrino' first."; \
	else \
		echo "[yweb-install] Installing yWeb into staging (expands placeholders)..."; \
		$(MAKE) --no-print-directory -C "$(NEUTRINO_BUILD_DIR)/data/y-web" install \
			DESTDIR="$(NEUTRINO_INSTALL_DIR)" config_DATA= || exit 1; \
		echo "[yweb-install] Staging updated: $(YWEB_SYSROOT_DIR)"; \
	fi

.PHONY: yweb-install-runtime
yweb-install-runtime: yweb-install-sysroot
	@if [ ! -d "$(YWEB_SYSROOT_DIR)" ]; then \
		echo "[yweb-install] Staging webroot not found, skipping runtime sync."; \
		echo "[yweb-install] Run 'make neutrino' first."; \
	elif [ ! -d "$(YWEB_RUNTIME_DIR)" ]; then \
		echo "[yweb-install] Runtime directory not found, skipping runtime sync."; \
		echo "[yweb-install] Run 'make runtime-sync' first to create runtime structure."; \
	else \
		echo "[yweb-install] Syncing yWeb from staging to runtime..."; \
		rsync -a --no-owner --no-group "$(YWEB_SYSROOT_DIR)/" "$(YWEB_RUNTIME_DIR)/" || exit 1; \
		echo "[yweb-install] Runtime updated: $(YWEB_RUNTIME_DIR)"; \
	fi

.PHONY: yweb-clean
yweb-clean:
	@echo "[yweb-clean] Removing the staging webroot..."
	@$(RM_RF) "$(YWEB_SYSROOT_DIR)"

.PHONY: yweb-status
yweb-status:
	@echo ""
	@echo "yWeb Install Status"
	@echo "==================="
	@echo "Source:        $(YWEB_SRC_DIR)"
	@echo "Staging:       $(YWEB_SYSROOT_DIR)"
	@echo "Runtime:       $(YWEB_RUNTIME_DIR)"
	@echo ""
	@if [ -d "$(YWEB_SRC_DIR)" ]; then \
		echo "Source exists: YES"; \
	else \
		echo "Source exists: NO"; \
	fi
	@if [ -d "$(YWEB_SYSROOT_DIR)" ]; then \
		echo "Staging exists: YES"; \
	else \
		echo "Staging exists: NO (run 'make neutrino' first)"; \
	fi
	@if [ -d "$(YWEB_RUNTIME_DIR)" ]; then \
		echo "Runtime exists: YES"; \
	else \
		echo "Runtime exists: NO (run 'make runtime-sync' first)"; \
	fi
	@echo ""
