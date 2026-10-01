# =============================================================================
# Web Interface Quick Install Target
# =============================================================================
#
# This target allows rapid development of the web interface without requiring
# a full neutrino rebuild.
#
# It does NOT copy from the source tree. Web interface files carry build-time
# placeholders (%(CONFIGDIR), %(PRIVATE_HTTPDDIR), ...) that only neutrino's
# install-data-hook expands; copying the raw sources into the webroot leaves
# them in place, which makes scripts/Y_Tools.sh a shell syntax error and points
# the Y_Blocks*.txt templates at paths that do not exist. So we run neutrino's
# own install into the staging tree and mirror that expanded result.
#
# Note: a file only reaches the webroot once it is listed in the matching
# data/web-ui Makefile.am (data/y-web before neutrino 96c44c676c).
#
# Usage:
#   make webui-install          - Install web interface files to sysroot and runtime
#   make webui-install-sysroot  - Install only to sysroot (no runtime sync)
#   make webui-status           - Show source, staging and runtime paths
#
# The former yweb-* names stay available as aliases (e.g. make yweb-install).
#
# After running webui-install, simply refresh your browser (F5) to see changes.
#
# Prerequisites:
#   - neutrino must have been built at least once (to create directory structure)
#   - runtime-sync should have been run at least once
#
# =============================================================================

# Source directory containing the web interface files. neutrino 96c44c676c
# renamed it from data/y-web to data/web-ui; older checkouts (NEUTRINO_BRANCH)
# still use the old name. Decide by the source tree: a build tree configured before the rename
# keeps a stale data/y-web whose Makefile points at a Makefile.am that is gone.
WEBUI_SUBDIR := $(if $(wildcard $(NEUTRINO_SRC_DIR)/data/web-ui/Makefile.am),data/web-ui,data/y-web)
WEBUI_SRC_DIR := $(NEUTRINO_SRC_DIR)/$(WEBUI_SUBDIR)

# Staging webroot produced by neutrino's "make install" with DESTDIR.
# PRIVATE_HTTPDDIR is configured as an absolute runtime path, so the staged
# copy lands under DESTDIR + that path. It is the only tree whose placeholders
# have been expanded.
WEBUI_SYSROOT_DIR := $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_RUNTIME_TUXBOX)/neutrino/httpd

# Destination in runtime (where nhttpd actually serves from)
WEBUI_RUNTIME_DIR := $(NEUTRINO_RUNTIME_PREFIX_ABS)$(N_PRIVATE_HTTPDDIR)

.PHONY: webui-install
webui-install: webui-install-sysroot webui-install-runtime
	@echo "[webui-install] Done. Refresh browser to see changes."

.PHONY: webui-install-sysroot
webui-install-sysroot:
	@# Guard and action share one shell: each recipe line gets its own, so an
	@# "exit 0" on a separate line would not skip what follows.
	@if [ ! -d "$(NEUTRINO_BUILD_DIR)/$(WEBUI_SUBDIR)" ]; then \
		echo "[webui-install] Build tree not found: $(NEUTRINO_BUILD_DIR)/$(WEBUI_SUBDIR)"; \
		echo "[webui-install] Run 'make neutrino' first."; \
	else \
		echo "[webui-install] Installing the web interface into staging (expands placeholders)..."; \
		$(MAKE) --no-print-directory -C "$(NEUTRINO_BUILD_DIR)/$(WEBUI_SUBDIR)" install \
			DESTDIR="$(NEUTRINO_INSTALL_DIR)" config_DATA= || exit 1; \
		echo "[webui-install] Staging updated: $(WEBUI_SYSROOT_DIR)"; \
	fi

.PHONY: webui-install-runtime
webui-install-runtime: webui-install-sysroot
	@if [ ! -d "$(WEBUI_SYSROOT_DIR)" ]; then \
		echo "[webui-install] Staging webroot not found, skipping runtime sync."; \
		echo "[webui-install] Run 'make neutrino' first."; \
	elif [ ! -d "$(WEBUI_RUNTIME_DIR)" ]; then \
		echo "[webui-install] Runtime directory not found, skipping runtime sync."; \
		echo "[webui-install] Run 'make runtime-sync' first to create runtime structure."; \
	else \
		echo "[webui-install] Syncing the web interface from staging to runtime..."; \
		rsync -a --no-owner --no-group "$(WEBUI_SYSROOT_DIR)/" "$(WEBUI_RUNTIME_DIR)/" || exit 1; \
		echo "[webui-install] Runtime updated: $(WEBUI_RUNTIME_DIR)"; \
	fi

.PHONY: webui-clean
webui-clean:
	@echo "[webui-clean] Removing the staging webroot..."
	@$(RM_RF) "$(WEBUI_SYSROOT_DIR)"

.PHONY: webui-status
webui-status:
	@echo ""
	@echo "Web Interface Install Status"
	@echo "============================"
	@echo "Source:        $(WEBUI_SRC_DIR)"
	@echo "Staging:       $(WEBUI_SYSROOT_DIR)"
	@echo "Runtime:       $(WEBUI_RUNTIME_DIR)"
	@echo ""
	@if [ -d "$(WEBUI_SRC_DIR)" ]; then \
		echo "Source exists: YES"; \
	else \
		echo "Source exists: NO"; \
	fi
	@if [ -d "$(WEBUI_SYSROOT_DIR)" ]; then \
		echo "Staging exists: YES"; \
	else \
		echo "Staging exists: NO (run 'make neutrino' first)"; \
	fi
	@if [ -d "$(WEBUI_RUNTIME_DIR)" ]; then \
		echo "Runtime exists: YES"; \
	else \
		echo "Runtime exists: NO (run 'make runtime-sync' first)"; \
	fi
	@echo ""

# Former yweb-* names, kept for existing habits and scripts. Plain
# prerequisites, so make runs each webui-* recipe once even when both names
# are given.
WEBUI_TARGETS := install install-sysroot install-runtime clean status
.PHONY: $(addprefix yweb-,$(WEBUI_TARGETS))
$(foreach t,$(WEBUI_TARGETS),$(eval yweb-$(t): webui-$(t)))
