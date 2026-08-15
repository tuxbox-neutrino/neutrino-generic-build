# Host tools staging: create a symlinked toolchain under ./hosttools and prepend to PATH.

HOSTTOOLS_DIR ?= $(ROOT_DIR)/hosttools

# Core tools we expect from the host. Extend as needed (build, test, packaging).
HOSTTOOLS_BINARIES ?= gcc g++ pkg-config cmake ninja make python3 tesseract fbgrab Xvfb xvfb-run evtest git rsync

.PHONY: hosttools hosttools-clean
hosttools: ## Stage a symlinked host toolchain under ./hosttools and prepend it to PATH
	@mkdir -p "$(HOSTTOOLS_DIR)"
	@set -e; \
	for bin in $(HOSTTOOLS_BINARIES); do \
		if command -v "$$bin" >/dev/null 2>&1; then \
			target="$(HOSTTOOLS_DIR)/$$bin"; \
			src="$$(command -v "$$bin")"; \
			if [ -L "$$target" ] || [ ! -e "$$target" ]; then \
				ln -sf "$$src" "$$target"; \
			fi; \
		else \
			echo "[hosttools] Warning: $$bin not found on host"; \
		fi; \
	done

hosttools-clean:
	@rm -rf "$(HOSTTOOLS_DIR)"
