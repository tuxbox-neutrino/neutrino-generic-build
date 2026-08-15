# Packaging helpers for AppImage, Debian packages, and static bundles.

APPIMAGE_OUTPUT_DIR ?= $(OUTPUT_DIR)/appimage
DEB_OUTPUT_DIR ?= $(OUTPUT_DIR)/deb
STATIC_OUTPUT_DIR ?= $(OUTPUT_DIR)/static

.PHONY: package-appimage-build
package-appimage-build:
	@$(MKDIR_P) $(APPIMAGE_OUTPUT_DIR)
	@APPIMAGE_TOOL_PATH="$$(./scripts/ensure_appimagetool.sh)"; \
	if [ -z "$${APPIMAGE_TOOL_PATH}" ]; then \
		echo "[package] Failed to provision appimagetool."; \
		exit 1; \
	fi; \
	echo "[package] Generating AppImage"; \
	NEUTRINO_INSTALL_DIR=$(NEUTRINO_INSTALL_DIR) \
		APPIMAGE_OUTPUT_DIR=$(APPIMAGE_OUTPUT_DIR) \
		APPIMAGE_TOOL="$${APPIMAGE_TOOL_PATH}" \
		./scripts/gen_appimage.sh

.PHONY: package-deb-build
package-deb-build:
	@$(MKDIR_P) $(DEB_OUTPUT_DIR)
	@echo "[package] Generating Debian package"
	@NEUTRINO_INSTALL_DIR=$(NEUTRINO_INSTALL_DIR) \
		DEB_OUTPUT_DIR=$(DEB_OUTPUT_DIR) \
		./scripts/make_deb.sh

.PHONY: package-static-build
package-static-build:
	@$(MKDIR_P) $(STATIC_OUTPUT_DIR)
	@echo "[package] Generating static tarball"
	@NEUTRINO_INSTALL_DIR_STATIC=$(NEUTRINO_INSTALL_DIR_STATIC) \
		STATIC_OUTPUT_DIR=$(STATIC_OUTPUT_DIR) \
		./scripts/static_link.sh

.PHONY: package-clean
package-clean:
	@true
