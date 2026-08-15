# HowTo: Add a New Build Target

This document describes how to add new build targets to the modular neutrino-make build system.

## Build System Overview

neutrino-make uses a modular Makefile system with clear separation:

```
make/
├── main.mk           # Main entry point, bootstrap, run targets
├── env.mk            # Environment variables and defaults
├── toolchain.mk      # Compiler and toolchain configuration
├── deps.mk           # Dependency management (Python venv, etc.)
├── third_party.mk    # Third-party coordination
├── third_party/      # Individual third-party builds
│   ├── luajit.mk
│   ├── lua.mk
│   ├── ffmpeg.mk
│   └── ...
├── neutrino.mk       # Neutrino core build
├── plugins.mk        # Plugin build coordination
├── tests.mk          # Test execution
└── package.mk        # Packaging targets
```

### Core Principles

1. **Stamp Files**: Build steps are tracked via `.stamp` files
2. **Idempotency**: Targets can be called multiple times without rebuilding
3. **Phony Declarations**: All convenience targets are `.PHONY`
4. **Environment Variables**: Configuration via variables from `env.mk`
5. **Help Text**: All important targets have `## Description` comments

## 1. Add Simple Build Target

### Example: New Helper Function

```makefile
# In make/main.mk or make/utils.mk

.PHONY: check-environment
check-environment: ## Check build environment for completeness
	@echo "[check-environment] Checking system packages..."
	@command -v gcc >/dev/null 2>&1 || { echo "ERROR: gcc not found"; exit 1; }
	@command -v g++ >/dev/null 2>&1 || { echo "ERROR: g++ not found"; exit 1; }
	@command -v pkg-config >/dev/null 2>&1 || { echo "ERROR: pkg-config not found"; exit 1; }
	@echo "[check-environment] OK - All required tools present"
```

**Important elements:**
- `.PHONY:` declaration, as no file is created
- `## Comment` for `make help` integration
- `@echo` for user feedback (@ suppresses command output)
- Error handling with `|| { echo ...; exit 1; }`

## 2. Add Third-Party Dependency

### Step 1: Create New File

Create `make/third_party/my-lib.mk`:

```makefile
# Third-party library: my-lib
# Only built if system version is missing or too old

MY_LIB_VERSION ?= 1.2.3
MY_LIB_URL := https://example.com/releases/my-lib-$(MY_LIB_VERSION).tar.gz
MY_LIB_ARCHIVE := $(ARCHIVE_DIR)/my-lib-$(MY_LIB_VERSION).tar.gz
MY_LIB_SRC_DIR := $(SOURCES_DIR)/my-lib-$(MY_LIB_VERSION)
MY_LIB_BUILD_DIR := $(BUILD_DIR)/my-lib
MY_LIB_STAMP := $(MY_LIB_SRC_DIR)/.installed

# Check system version
MY_LIB_SYSTEM_VERSION := $(shell pkg-config --modversion my-lib 2>/dev/null || echo "0.0.0")
MY_LIB_NEEDS_BUILD := $(shell \
	if [ "$(MY_LIB_SYSTEM_VERSION)" = "0.0.0" ]; then \
		echo "yes"; \
	elif [ "$$(printf '%s\n' "$(MY_LIB_VERSION)" "$(MY_LIB_SYSTEM_VERSION)" | sort -V | head -n1)" != "$(MY_LIB_VERSION)" ]; then \
		echo "yes"; \
	else \
		echo "no"; \
	fi)

# Build target with force option
ifeq ($(MY_LIB_FORCE),1)
MY_LIB_NEEDS_BUILD := yes
endif

.PHONY: deps-my-lib
deps-my-lib:
ifeq ($(MY_LIB_NEEDS_BUILD),yes)
	@echo "[third-party] Building my-lib $(MY_LIB_VERSION) (system: $(MY_LIB_SYSTEM_VERSION))"
	@$(MAKE) $(MY_LIB_STAMP)
else
	@echo "[third-party] Using system my-lib $(MY_LIB_SYSTEM_VERSION)"
endif

# Download
$(MY_LIB_ARCHIVE):
	@echo "[third-party] Downloading my-lib $(MY_LIB_VERSION)"
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@wget -O "$@.tmp" "$(MY_LIB_URL)" && mv "$@.tmp" "$@"

# Extract
$(MY_LIB_SRC_DIR)/.unpacked: $(MY_LIB_ARCHIVE)
	@echo "[third-party] Extracting my-lib"
	@$(MKDIR_P) $(SOURCES_DIR)
	@tar -xzf "$(MY_LIB_ARCHIVE)" -C "$(SOURCES_DIR)"
	@touch $@

# Configure
$(MY_LIB_SRC_DIR)/.configured: $(MY_LIB_SRC_DIR)/.unpacked
	$(call ENFORCE_GCC_VERSION)
	@echo "[third-party] Configuring my-lib"
	@$(MKDIR_P) $(MY_LIB_BUILD_DIR)
	@cd $(MY_LIB_BUILD_DIR) && \
		$(MY_LIB_SRC_DIR)/configure \
			--prefix=$(NEUTRINO_PREFIX) \
			--enable-shared \
			--disable-static \
			CC="$(CC)" \
			CXX="$(CXX)" \
			CFLAGS="$(CFLAGS)" \
			CXXFLAGS="$(CXXFLAGS)" \
			LDFLAGS="$(LDFLAGS)"
	@touch $@

# Build
$(MY_LIB_SRC_DIR)/.built: $(MY_LIB_SRC_DIR)/.configured
	@echo "[third-party] Building my-lib"
	@$(MAKE) -C $(MY_LIB_BUILD_DIR) -j$(shell nproc)
	@touch $@

# Install
$(MY_LIB_STAMP): $(MY_LIB_SRC_DIR)/.built
	@echo "[third-party] Installing my-lib to sysroot"
	@$(MAKE) -C $(MY_LIB_BUILD_DIR) DESTDIR="$(NEUTRINO_INSTALL_DIR)" install
	@touch $@

# Force build target
.PHONY: deps-my-lib-force my-lib-force
deps-my-lib-force my-lib-force: ## Build my-lib locally (always, ignores host version)
	@$(MAKE) MY_LIB_FORCE=1 deps-my-lib

# Version-specific target
.PHONY: deps-my-lib-% my-lib-%
deps-my-lib-% my-lib-%: ## Build my-lib <version> locally (always, ignores host version)
	@$(MAKE) MY_LIB_FORCE=1 MY_LIB_VERSION=$* deps-my-lib

# Clean target
.PHONY: clean-my-lib
clean-my-lib:
	@echo "[third-party] Cleaning my-lib"
	@rm -rf $(MY_LIB_BUILD_DIR)
	@rm -f $(MY_LIB_SRC_DIR)/.configured $(MY_LIB_SRC_DIR)/.built $(MY_LIB_STAMP)
```

### Step 2: Add to Third-Party Coordination

In `make/third_party.mk`:

```makefile
# Add my-lib to third-party targets
include make/third_party/my-lib.mk

# Add to THIRD_PARTY_TARGETS (if present)
THIRD_PARTY_TARGETS += deps-my-lib
```

### Step 3: Integrate into Bootstrap Sequence (optional)

If the library is required for Neutrino core, in `make/main.mk`:

```makefile
.PHONY: bootstrap
bootstrap: ## Complete build from scratch
	@echo "==> Bootstrap: Phase 1 - Dependencies"
	@$(MAKE) deps
	@$(MAKE) runtime-sync
	@$(MAKE) deps-my-lib    # <-- Insert here
	@echo "==> Bootstrap: Phase 2 - Lua toolchain"
	@$(MAKE) lua-deps
	# ... rest
```

## 3. Understanding Stamp File Pattern

### Why Stamp Files?

Stamp files prevent unnecessary rebuilds and track build status:

```makefile
# Bad example (always rebuilds):
.PHONY: build-foo
build-foo:
	./configure && make && make install

# Good example (only builds when needed):
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.unpacked
	./configure
	@touch $@

$(FOO_SRC_DIR)/.built: $(FOO_SRC_DIR)/.configured
	make
	@touch $@

$(FOO_STAMP): $(FOO_SRC_DIR)/.built
	make install
	@touch $@
```

### Typical Stamp File Chain

```
.unpacked  → .patched  → .configured  → .built  → .installed
```

**Example with patches:**

```makefile
# Apply patches
$(FOO_SRC_DIR)/.patched: $(FOO_SRC_DIR)/.unpacked
	@echo "[third-party] Patching foo"
	@if [ -d files/foo/patches ]; then \
		for p in files/foo/patches/*.patch; do \
			echo "  Applying $$(basename $$p)"; \
			patch -d $(FOO_SRC_DIR) -p1 < $$p; \
		done; \
	fi
	@touch $@

# Configuration depends on patching
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.patched
	./configure ...
	@touch $@
```

## 4. Add GCC Version Enforcement

For all C/C++ builds, GCC version checking **must** be done:

```makefile
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.unpacked
	$(call ENFORCE_GCC_VERSION)    # <-- Always before ./configure
	@echo "[third-party] Configuring foo"
	@cd $(FOO_BUILD_DIR) && \
		$(FOO_SRC_DIR)/configure \
			CC="$(CC)" \
			CXX="$(CXX)" \
			...
	@touch $@
```

**Why?** Prevents ABI incompatibility between libraries built with different GCC versions.

## 5. Add Help Text

All user-facing targets need help text:

```makefile
.PHONY: my-target
my-target: ## Short description (max 60 characters)
	# ... implementation
```

The `## comment` is automatically parsed by `make help` and displayed:

```bash
$ make help
...
  my-target         : Short description (max 60 characters)
...
```

**Best practices:**
- Description in imperative ("Build", "Install", "Clean")
- Parameters in `<angle brackets>` (e.g., `Build foo <version>`)
- Document optional flags

## 6. Add Test Target

### Example: New Test Type

In `make/tests.mk`:

```makefile
.PHONY: test-my-lib
test-my-lib: deps-my-lib ## Test my-lib installation
	@echo "[test] Checking my-lib installation"
	@pkg-config --exists my-lib || { echo "ERROR: my-lib.pc not found"; exit 1; }
	@pkg-config --modversion my-lib
	@echo "[test] my-lib OK"

# Add to main test target
.PHONY: test
test: test-build test-gui test-web test-my-lib ## Run all tests
	@echo "[test] All tests completed"
```

## 7. Add Package Target

### Example: New Package Format

In `make/package.mk`:

```makefile
.PHONY: package-flatpak
package-flatpak: bootstrap ## Create Flatpak package
	@echo "[package] Building Flatpak"
	@$(MKDIR_P) $(OUTPUT_DIR)/flatpak
	@flatpak-builder \
		--force-clean \
		--repo=$(OUTPUT_DIR)/flatpak/repo \
		$(OUTPUT_DIR)/flatpak/build \
		packaging/flatpak/de.tuxbox.neutrino.yml
	@echo "[package] Flatpak created: $(OUTPUT_DIR)/flatpak/repo"
```

## 8. Add Convenience Aliases

Short aliases for frequently used targets:

```makefile
# In make/main.mk

.PHONY: b
b: bootstrap ## Alias for bootstrap

.PHONY: r
r: run ## Alias for run

.PHONY: c
c: clean ## Alias for clean

.PHONY: t
t: test ## Alias for test
```

## 9. Define Dependency Chains

### Example: Multi-Stage Build

```makefile
# Stage 1: Prepare
.PHONY: prepare-foo
prepare-foo:
	@echo "[foo] Preparing..."
	@$(MKDIR_P) $(FOO_BUILD_DIR)

# Stage 2: Configure (depends on stage 1)
.PHONY: configure-foo
configure-foo: prepare-foo deps-my-lib
	@echo "[foo] Configuring..."
	./configure --with-my-lib

# Stage 3: Build (depends on stage 2)
.PHONY: build-foo
build-foo: configure-foo
	@echo "[foo] Building..."
	make -C $(FOO_BUILD_DIR)

# Stage 4: Install (depends on stage 3)
.PHONY: install-foo
install-foo: build-foo
	@echo "[foo] Installing..."
	make -C $(FOO_BUILD_DIR) DESTDIR="$(NEUTRINO_INSTALL_DIR)" install

# Main target (runs all stages)
.PHONY: foo
foo: install-foo ## Build and install foo
```

## 10. Error Handling and Robustness

### Example: Robust Download Function

```makefile
$(FOO_ARCHIVE):
	@echo "[third-party] Downloading foo $(FOO_VERSION)"
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@for i in 1 2 3; do \
		if wget -O "$@.tmp" "$(FOO_URL)"; then \
			mv "$@.tmp" "$@"; \
			break; \
		else \
			echo "[third-party] Download attempt $$i failed, retrying..."; \
			sleep 2; \
		fi; \
	done
	@if [ ! -f "$@" ]; then \
		echo "[third-party] ERROR: Download failed after 3 attempts"; \
		exit 1; \
	fi
```

### Example: Directory Existence Checks

```makefile
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.unpacked
	@if [ ! -f "$(FOO_SRC_DIR)/configure" ]; then \
		echo "[third-party] ERROR: configure script not found"; \
		exit 1; \
	fi
	@echo "[third-party] Configuring foo"
	./configure ...
	@touch $@
```

### Example: Command Existence Checks

```makefile
.PHONY: check-cmake
check-cmake:
	@command -v cmake >/dev/null 2>&1 || { \
		echo "ERROR: cmake not found. Install with: sudo apt install cmake"; \
		exit 1; \
	}

$(FOO_SRC_DIR)/.configured: check-cmake $(FOO_SRC_DIR)/.unpacked
	cmake ...
```

## 11. Use Environment Variables

### Configurable Variables

In `make/env.mk`:

```makefile
# Add new variable
FOO_ENABLE_FEATURE_X ?= 1
FOO_PREFIX ?= $(NEUTRINO_PREFIX)
FOO_CONFIG_FLAGS ?=

# Export for sub-makes
export FOO_ENABLE_FEATURE_X FOO_PREFIX FOO_CONFIG_FLAGS
```

In `Makefile.local.sample`:

```makefile
#FOO_ENABLE_FEATURE_X := 0
#  Disable feature X in foo (default: 1)

#FOO_CONFIG_FLAGS := --with-ssl --with-zlib
#  Additional flags for foo's ./configure
```

### Use Variable in Target

```makefile
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.unpacked
	@echo "[third-party] Configuring foo (FEATURE_X=$(FOO_ENABLE_FEATURE_X))"
	@cd $(FOO_BUILD_DIR) && \
		$(FOO_SRC_DIR)/configure \
			--prefix=$(FOO_PREFIX) \
			$(if $(filter 1,$(FOO_ENABLE_FEATURE_X)),--enable-feature-x,--disable-feature-x) \
			$(FOO_CONFIG_FLAGS)
	@touch $@
```

## 12. Control Parallel Builds

### Force Sequential Build

For problematic builds (e.g., FFmpeg):

```makefile
$(FOO_SRC_DIR)/.built: $(FOO_SRC_DIR)/.configured
	@echo "[third-party] Building foo (sequential)"
	@$(MAKE) -C $(FOO_BUILD_DIR) -j1    # <-- Force single job
	@touch $@
```

### Parallel Build with Limit

```makefile
$(FOO_SRC_DIR)/.built: $(FOO_SRC_DIR)/.configured
	@echo "[third-party] Building foo (parallel)"
	@$(MAKE) -C $(FOO_BUILD_DIR) -j$(shell nproc)    # <-- Use all cores
	@touch $@
```

## 13. Complete Example

### Add New Tool "myapp"

**File:** `make/myapp.mk`

```makefile
# MyApp - Example application build

MYAPP_VERSION ?= 2.1.0
MYAPP_URL := https://github.com/user/myapp/archive/v$(MYAPP_VERSION).tar.gz
MYAPP_ARCHIVE := $(ARCHIVE_DIR)/myapp-$(MYAPP_VERSION).tar.gz
MYAPP_SRC_DIR := $(SOURCES_DIR)/myapp-$(MYAPP_VERSION)
MYAPP_BUILD_DIR := $(BUILD_DIR)/myapp
MYAPP_STAMP := $(MYAPP_SRC_DIR)/.installed

.PHONY: myapp
myapp: ## Build and install myapp
	@$(MAKE) $(MYAPP_STAMP)

$(MYAPP_ARCHIVE):
	@echo "[myapp] Downloading v$(MYAPP_VERSION)"
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@wget -O "$@.tmp" "$(MYAPP_URL)" && mv "$@.tmp" "$@"

$(MYAPP_SRC_DIR)/.unpacked: $(MYAPP_ARCHIVE)
	@echo "[myapp] Extracting"
	@$(MKDIR_P) $(SOURCES_DIR)
	@tar -xzf "$(MYAPP_ARCHIVE)" -C "$(SOURCES_DIR)"
	@touch $@

$(MYAPP_SRC_DIR)/.configured: $(MYAPP_SRC_DIR)/.unpacked
	$(call ENFORCE_GCC_VERSION)
	@echo "[myapp] Configuring"
	@$(MKDIR_P) $(MYAPP_BUILD_DIR)
	@cd $(MYAPP_BUILD_DIR) && \
		cmake $(MYAPP_SRC_DIR) \
			-DCMAKE_INSTALL_PREFIX=$(NEUTRINO_PREFIX) \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_COMPILER="$(CC)" \
			-DCMAKE_CXX_COMPILER="$(CXX)"
	@touch $@

$(MYAPP_SRC_DIR)/.built: $(MYAPP_SRC_DIR)/.configured
	@echo "[myapp] Building"
	@$(MAKE) -C $(MYAPP_BUILD_DIR) -j$(shell nproc)
	@touch $@

$(MYAPP_STAMP): $(MYAPP_SRC_DIR)/.built
	@echo "[myapp] Installing to sysroot"
	@$(MAKE) -C $(MYAPP_BUILD_DIR) DESTDIR="$(NEUTRINO_INSTALL_DIR)" install
	@touch $@

.PHONY: clean-myapp
clean-myapp: ## Clean myapp build artifacts
	@echo "[myapp] Cleaning"
	@rm -rf $(MYAPP_BUILD_DIR)
	@rm -f $(MYAPP_SRC_DIR)/.configured $(MYAPP_SRC_DIR)/.built $(MYAPP_STAMP)
```

**Integration in `make/main.mk`:**

```makefile
include make/myapp.mk

.PHONY: bootstrap
bootstrap: ## Complete build
	# ...
	@$(MAKE) myapp
	# ...
```

## Best Practices Summary

1. ✅ **Use stamp files** for build steps
2. ✅ **Check GCC version** for C/C++ builds
3. ✅ **Add help text** with `## comment`
4. ✅ **Declare phony targets** with `.PHONY:`
5. ✅ **Error handling** with `|| { echo ...; exit 1; }`
6. ✅ **Use variables from env.mk** instead of hard-coding
7. ✅ **Provide clean targets** for all builds
8. ✅ **Add test targets** where appropriate
9. ✅ **Define dependency chains correctly**
10. ✅ **Robust downloads** with retries

## Troubleshooting

### Problem: Target not executed

```bash
# Check if target exists
make -n my-target

# Check if .PHONY is declared
grep "\.PHONY.*my-target" make/*.mk
```

### Problem: Stamp file not created

```bash
# Check if @touch $@ is at the end
grep -A 5 "my-target:" make/*.mk | grep touch

# Check manually
ls -la $(SOURCES_DIR)/foo/.installed
```

### Problem: Dependencies ignored

```bash
# Show dependencies
make -p | grep -A 3 "^my-target:"

# Dry-run with debug
make -n -d my-target
```

## Further Resources

- Existing makefiles as templates: `make/third_party/*.mk`
- Environment variables: [make/env.mk](../make/env.mk)
- Toolchain setup: [make/toolchain.mk](../make/toolchain.mk)
- Bootstrap flow: [make/main.mk](../make/main.mk)
- Plugin system: [HOWTO_ADD_PLUGIN.en.md](HOWTO_ADD_PLUGIN.en.md)
