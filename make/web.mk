# Web interface build orchestration (Playwright/TypeScript front-end).

WEB_SRC_DIR ?= $(ROOT_DIR)/web
WEB_BUILD_DIR ?= $(BUILD_DIR)/web
WEB_INSTALL_DIR ?= $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/share/neutrino/web
WEB_BUILD_OUTPUT ?= dist

.PHONY: web
web: $(NEUTRINO_INSTALL_STAMP)
	@if [ -f "$(WEB_SRC_DIR)/package.json" ]; then \
		echo "[web] Installing npm dependencies"; \
		if [ -f "$(WEB_SRC_DIR)/package-lock.json" ]; then \
			cd "$(WEB_SRC_DIR)" && $(NPM) ci --no-progress; \
		else \
			cd "$(WEB_SRC_DIR)" && $(NPM) install --no-progress; \
		fi; \
		$(MKDIR_P) "$(WEB_BUILD_DIR)"; \
		echo "[web] Building web assets"; \
		cd "$(WEB_SRC_DIR)" && $(NPM) run build; \
		$(MKDIR_P) "$(WEB_INSTALL_DIR)"; \
		if [ -d "$(WEB_SRC_DIR)/$(WEB_BUILD_OUTPUT)" ]; then \
			cp -a "$(WEB_SRC_DIR)/$(WEB_BUILD_OUTPUT)/." "$(WEB_INSTALL_DIR)/"; \
		elif [ -d "$(WEB_BUILD_DIR)" ]; then \
			cp -a "$(WEB_BUILD_DIR)/." "$(WEB_INSTALL_DIR)/"; \
		else \
			echo "[web] Build output missing (expected $(WEB_BUILD_OUTPUT) or $(WEB_BUILD_DIR))" >&2; \
			exit 1; \
		fi; \
	else \
		echo "[web] No web interface sources detected, skipping"; \
	fi

.PHONY: web-clean
web-clean:
	@$(RM_RF) $(WEB_BUILD_DIR)

.PHONY: web-distclean
web-distclean:
	@$(RM_RF) $(WEB_BUILD_DIR) $(WEB_INSTALL_DIR)
