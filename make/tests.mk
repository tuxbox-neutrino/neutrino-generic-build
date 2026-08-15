# Headless GUI and web smoke testing helpers.

TEST_ARTIFACT_DIR ?= $(OUTPUT_DIR)/tests
GUI_TEST_DIR ?= $(ROOT_DIR)/tests/gui
WEB_TEST_DIR ?= $(ROOT_DIR)/tests/web
SHELL_TEST_DIR ?= $(ROOT_DIR)/tests/shell
PLAYWRIGHT_BIN ?= npx

# Sequential on purpose. As a plain prerequisite list these three ran under the
# auto-injected -j, so the GUI and web suites drove the same Neutrino instance at
# the same time: Playwright changed the OSD while the GUI suite was asserting on
# it, and test-gui failed at random while both suites passed on their own.
# Prerequisites express dependency, not order -- the same trap the dependency
# phases hit. Separate $(MAKE) calls are what actually enforces a sequence.
.PHONY: tests-all
tests-all:
	@$(MAKE) tests-shell
	@$(MAKE) tests-gui
	@$(MAKE) tests-web

.PHONY: tests-shell
tests-shell:
	@[ -d "$(SHELL_TEST_DIR)" ] || { echo "[test-shell] No shell tests present, skipping"; exit 0; }
	@echo "[test-shell] Running POSIX shell unit tests"
	@rc=0; for t in "$(SHELL_TEST_DIR)"/test_*.sh; do \
		[ -f "$$t" ] || continue; \
		echo "[test-shell] $$t"; \
		sh "$$t" || rc=1; \
	done; \
	exit $$rc

.PHONY: tests-gui
tests-gui:
	@$(MKDIR_P) $(TEST_ARTIFACT_DIR)/gui
	@[ -d "$(GUI_TEST_DIR)" ] || { echo "[test-gui] No GUI tests present, skipping"; exit 0; }
	@if ! "$(PYTHON)" -m pytest --version >/dev/null 2>&1; then \
		echo "[test-gui] pytest missing. Run 'make deps' before executing GUI tests." >&2; \
		exit 1; \
	fi
	@echo "[test-gui] Running pytest-based GUI suite"
	@ARTIFACT_DIR=$(TEST_ARTIFACT_DIR)/gui \
		ALLOW_NON_ROOT=$(ALLOW_NON_ROOT) \
		$(PYTHON) -m pytest "$(GUI_TEST_DIR)" --maxfail=1 --disable-warnings -q

.PHONY: tests-web
tests-web:
	@$(MKDIR_P) $(TEST_ARTIFACT_DIR)/web
	@[ -d "$(WEB_TEST_DIR)" ] || { echo "[test-web] No web tests present, skipping"; exit 0; }
	@if ! command -v $(NPM) >/dev/null 2>&1; then \
		echo "[test-web] npm missing. Run 'make deps' or install Node."; \
		echo "[test-web] Skipping web tests."; \
		true; \
	else \
		if [ -f "$(WEB_TEST_DIR)/package.json" ]; then \
			cd "$(WEB_TEST_DIR)" && $(NPM) install --no-progress; \
		fi; \
		if command -v $(PLAYWRIGHT_BIN) >/dev/null 2>&1; then \
			echo "[test-web] Running Playwright smoke tests"; \
			cd "$(WEB_TEST_DIR)" && $(PLAYWRIGHT_BIN) playwright test --config=playwright.config.ts --output="$(TEST_ARTIFACT_DIR)/web"; \
		else \
			echo "[test-web] Playwright executable missing (install via npm), skipping"; \
		fi; \
	fi

.PHONY: tests-hw
tests-hw:
	@ALLOW_NON_ROOT=$(ALLOW_NON_ROOT) ./scripts/detect_devs.sh --verbose

.PHONY: tests-clean
tests-clean:
	@$(RM_RF) $(TEST_ARTIFACT_DIR)
