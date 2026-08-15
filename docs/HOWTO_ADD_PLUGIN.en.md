# HowTo: Add a New Plugin

This document describes how to add a new plugin to the neutrino-make build system.

## Overview of Plugin Types

neutrino-make supports three plugin types:

1. **Lua Plugins** (Script-based)
   - Pure Lua scripts without compilation
   - Easiest to create and maintain
   - Examples: neutrino-mediathek, webtv, logoupdater

2. **Native Binary Plugins** (Shared Libraries)
   - Compiled `.so` files loaded by Neutrino
   - Access to Neutrino API via headers
   - Examples: FritzInfoMonitor, FritzCallMonitor

3. **Standalone Binary Plugins** (Executables)
   - Independent programs with optional Neutrino wrapper
   - Custom build process (autotools, cmake, make)
   - Examples: tuxwetter, sysinfo, msgbox

## Prerequisites

- Working neutrino-make build environment
- Successfully executed `make bootstrap`
- Plugin source code (local or as Git repository)

## 1. Add Lua Plugin

### Step 1: Create Plugin Structure

```bash
mkdir -p lua/my-plugin
cd lua/my-plugin

# Main plugin file
cat > my-plugin.lua <<'EOF'
-- My first Neutrino Lua Plugin
local json = require("json")
local n_gui = require("n_gui")

function main()
    local menu = n_gui.menu.new("My Plugin", "info")
    menu:addItem{
        type = "forwarder",
        name = "Hello World",
        action = "lua",
        enabled = true,
        directkey = "",
        id = "",
        hidden = false
    }
    menu:exec()
end

return {run = main}
EOF

# Metadata file (optional but recommended)
cat > metadata.json <<'EOF'
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "My first Neutrino Lua Plugin",
  "author": "Your Name <email@example.com>",
  "license": "GPL-2.0-or-later",
  "type": "lua"
}
EOF
```

### Step 2: Register Plugin

Create a new file `make/plugins/plugin-my-plugin.mk`:

```makefile
PLUGIN_INSTALL_NAMES += my-plugin
PLUGIN_INSTALL_RULES += my-plugin:my-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-plugin:my-plugin
PLUGIN_CLEAN_DEFAULTS += my-plugin
```

**Variable explanation:**
- `PLUGIN_INSTALL_NAMES`: List of plugin names for `make plugins`
- `PLUGIN_INSTALL_RULES`: Mapping from name to install target (format: `name:target`)
- `PLUGIN_INSTALL_ALIAS_PAIRS`: Aliases for simplified calls (format: `alias:canonical-name`)
- `PLUGIN_CLEAN_DEFAULTS`: Plugins removed by `make clean-plugins`

### Step 3: Add Install Rule

In `plugins/Makefile` or a new file `plugins/my-plugin.mk`:

```makefile
.PHONY: my-plugin-install
my-plugin-install:
	@echo "[plugin] Installing my-plugin (Lua)"
	@mkdir -p "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin"
	@cp -av "$(ROOT_DIR)/lua/my-plugin/"*.lua "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin/"
	@if [ -f "$(ROOT_DIR)/lua/my-plugin/metadata.json" ]; then \
		cp -v "$(ROOT_DIR)/lua/my-plugin/metadata.json" "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin/"; \
	fi
```

### Step 4: Build and Test Plugin

```bash
# Build all plugins (including newly registered my-plugin)
make plugins

# Sync runtime
make runtime-sync

# Start Neutrino and test plugin
ALLOW_NON_ROOT=1 make run-now
```

### Using Shared Lua Libraries

If your plugin requires shared Lua libraries (e.g., `json.lua`, `n_gui.lua`):

```bash
# The libraries live in their own repository, tuxbox-neutrino/plugin-scripts-lua.
# `make plugins` clones it to sources/plugin-scripts-lua/ on first use and stages
# share/lua/5.x/ into the runtime tree -- nothing has to be fetched by hand.
```

Use in plugin:

```lua
local json = require("json")
local n_gui = require("n_gui")
-- These modules come from plugin-scripts-lua and are staged into the runtime
```

## 2. Add Native Binary Plugin (.so)

### Step 1: Create Plugin Source Code

```bash
mkdir -p plugins/my-binary-plugin
cd plugins/my-binary-plugin

# Main C++ file
cat > my-binary-plugin.cpp <<'EOF'
#include <plugin.h>
#include <neutrino.h>

extern "C" {
    PluginParam* plugin_exec(PluginParam* param) {
        // Your plugin code here
        printf("My Binary Plugin is running!\n");
        return param;
    }
}
EOF

# Makefile
cat > Makefile <<'EOF'
PLUGIN_NAME = my-binary-plugin

CC ?= gcc
CXX ?= g++
PKG_CONFIG ?= pkg-config

CXXFLAGS += -fPIC -Wall -Wextra
CXXFLAGS += $(shell $(PKG_CONFIG) --cflags neutrino)
LDFLAGS += -shared
LDFLAGS += $(shell $(PKG_CONFIG) --libs neutrino)

all: $(PLUGIN_NAME).so

$(PLUGIN_NAME).so: $(PLUGIN_NAME).cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

install: $(PLUGIN_NAME).so
	install -D -m 755 $(PLUGIN_NAME).so \
		$(DESTDIR)$(PREFIX)/lib/tuxbox/neutrino/plugins/$(PLUGIN_NAME).so

clean:
	rm -f $(PLUGIN_NAME).so

.PHONY: all install clean
EOF
```

### Step 2: Register Plugin

File `make/plugins/plugin-my-binary-plugin.mk`:

```makefile
PLUGIN_INSTALL_NAMES += my-binary-plugin
PLUGIN_INSTALL_RULES += my-binary-plugin:my-binary-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-binary-plugin:my-binary-plugin
PLUGIN_CLEAN_DEFAULTS += my-binary-plugin
```

### Step 3: Install Rule with Compiler Environment

In `plugins/Makefile`:

```makefile
.PHONY: my-binary-plugin-install
my-binary-plugin-install:
	@echo "[plugin] Building my-binary-plugin (native)"
	@if [ ! -d "$(PLUGINS_DIR)/my-binary-plugin" ]; then \
		echo "[plugin] ERROR: $(PLUGINS_DIR)/my-binary-plugin not found"; \
		exit 1; \
	fi
	@$(PLUGIN_ENV_ARGS) $(MAKE) -C "$(PLUGINS_DIR)/my-binary-plugin" install
```

**Important:** `$(PLUGIN_ENV_ARGS)` automatically exports:
- CC, CXX, CFLAGS, CXXFLAGS, LDFLAGS
- PKG_CONFIG_PATH, PKG_CONFIG_SYSROOT_DIR
- All N_* path variables
- NEUTRINO_SRC_DIR, LIBSTB_HAL_DIR

### Step 4: Test

```bash
# Build all plugins (including newly registered my-binary-plugin)
make plugins

# Sync runtime
make runtime-sync

# Start Neutrino and test plugin
ALLOW_NON_ROOT=1 make run-now
```

## 3. Add Standalone Binary Plugin

### Step 1: Integrate External Project

For projects with their own build system (autotools, cmake):

```bash
# Plugin sources as Git submodule
git submodule add https://github.com/user/my-tool.git plugins/my-tool

# Or local directory
mkdir -p plugins/my-tool
# ... copy sources ...
```

### Step 2: Create Build Wrapper

In `plugins/Makefile`:

```makefile
.PHONY: my-tool-install
my-tool-install:
	@echo "[plugin] Building my-tool (standalone)"
	@if [ ! -d "$(PLUGINS_DIR)/my-tool" ]; then \
		echo "[plugin] Auto-cloning my-tool..."; \
		git clone https://github.com/user/my-tool.git "$(PLUGINS_DIR)/my-tool"; \
	fi
	@cd "$(PLUGINS_DIR)/my-tool" && \
		if [ ! -f Makefile ]; then \
			./autogen.sh && \
			$(PLUGIN_ENV_ARGS) ./configure --prefix="$(PREFIX)"; \
		fi && \
		$(PLUGIN_ENV_ARGS) $(MAKE) && \
		$(PLUGIN_ENV_ARGS) $(MAKE) DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX)" install
```

**Auto-cloning support:** If the plugin directory is missing, it will be automatically cloned.

### Step 3: Register Plugin

File `make/plugins/plugin-my-tool.mk`:

```makefile
PLUGIN_INSTALL_NAMES += my-tool
PLUGIN_INSTALL_RULES += my-tool:my-tool-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-tool:my-tool
PLUGIN_CLEAN_DEFAULTS += my-tool
```

### Step 4: Optional - Add Neutrino Wrapper

If your tool needs a Neutrino menu entry:

```bash
mkdir -p lua/my-tool-wrapper
cat > lua/my-tool-wrapper/my-tool.lua <<'EOF'
local posix = require("posix")

function main()
    -- Call tool
    os.execute("/usr/bin/my-tool")
end

return {run = main}
EOF
```

Add the Lua wrapper as described in Section 1.

## Testing and Debugging

### Isolated Plugin Testing

```bash
# Manually install plugin (without bootstrap)
make my-plugin-install DESTDIR=$PWD/test-install PREFIX=/usr

# Check installed files
find test-install -type f

# Regular build with runtime sync and test
make plugins
make runtime-sync
ALLOW_NON_ROOT=1 make run-now
```

### Debugging Build Failures

```bash
# Verbose Make output (for all plugins)
make plugins V=1

# Build single plugin with debug information
make my-plugin-install V=1 DESTDIR=artifacts/sysroot PREFIX=/usr

# Check plugin directory contents
ls -la plugins/my-plugin/
ls -la $(PLUGINS_DIR)/my-plugin/

# Check sysroot contents
ls -la artifacts/sysroot/usr/share/tuxbox/neutrino/plugins/
ls -la artifacts/sysroot/usr/lib/tuxbox/neutrino/plugins/
```

### Runtime Debugging

```bash
# Start with GDB
ALLOW_NON_ROOT=1 make run-gdb

# With Valgrind
make run-valgrind

# Check log output
tail -f logs/neutrino.log
```

## Best Practices

### Naming Conventions

- **Lua plugins:** `plugin-lua-<name>` (repository), `<name>` (Makefile)
- **Binary plugins:** `plugin-bin-<name>` (repository), `<name>` (Makefile)
- **Makefile fragments:** `make/plugins/plugin-<name>.mk`

### Metadata

Always add a `metadata.json`:

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Short description",
  "author": "Your Name <email@example.com>",
  "license": "GPL-2.0-or-later",
  "type": "lua|native|standalone",
  "dependencies": ["json", "n_gui"],
  "neutrino_min_version": "3.2.0"
}
```

### Versioning

- Use Semantic Versioning (SemVer): `MAJOR.MINOR.PATCH`
- Git tags for releases: `v1.0.0`
- Breaking changes → increment major version

### Documentation

Create a `README.md` in the plugin directory:

```markdown
# My Plugin

Short description of the plugin.

## Installation

make plugins
make runtime-sync

## Usage

1. Start Neutrino
2. Menu → Plugins → My Plugin

## Configuration

Optional configuration files at:
/var/tuxbox/config/my-plugin.conf

## License

GPL-2.0-or-later
```

### Add Clean Target

In `plugins/Makefile`:

```makefile
.PHONY: clean-my-plugin
clean-my-plugin:
	@echo "[plugin] Cleaning my-plugin"
	@rm -rf "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin"
	@rm -rf "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/plugins/my-plugin"
	@rm -f "$(DESTDIR)$(PREFIX)/lib/tuxbox/neutrino/plugins/my-plugin.so"
	@if [ -d "$(PLUGINS_DIR)/my-plugin" ]; then \
		$(MAKE) -C "$(PLUGINS_DIR)/my-plugin" clean 2>/dev/null || true; \
	fi
```

## Troubleshooting

### Problem: Plugin not found

```bash
# Check if plugin is registered
grep -r "my-plugin" make/plugins/

# Check if install rule exists
grep -r "my-plugin-install" plugins/Makefile make/plugins/

# Show plugin names list
make list-plugin-targets
```

### Problem: Compilation fails

```bash
# Check GCC version
$(CC) --version

# Check PKG_CONFIG_PATH
echo $PKG_CONFIG_PATH
pkg-config --list-all | grep neutrino

# Check header files
ls -la artifacts/sysroot/usr/include/neutrino/
```

### Problem: Plugin doesn't run

```bash
# Check Neutrino log
tail -f logs/neutrino.log

# Debug Lua errors (for Lua plugins)
# In Neutrino: Settings → System → Debug → Enable Lua Debug

# Check shared library dependencies (for .so plugins)
ldd artifacts/sysroot/usr/lib/tuxbox/neutrino/plugins/my-plugin.so
```

### Problem: Auto-cloning fails

```bash
# Check Git URL
git ls-remote https://github.com/user/my-tool.git

# Clone manually
git clone https://github.com/user/my-tool.git plugins/my-tool

# Try rebuild
make clean-plugin-my-tool
make plugins
```

## Further Resources

- Example plugins: `plugins/Makefile` (neutrino-mediathek, FritzInfoMonitor)
- Plugin variables: `make/plugins.mk` (PLUGIN_ENV_VARS list, PLUGIN_ENV_ARGS exports)
- Lua libraries: [tuxbox-neutrino/plugin-scripts-lua](https://github.com/tuxbox-neutrino/plugin-scripts-lua) (cloned on demand into `sources/plugin-scripts-lua/`)
- Migration guide: [PLUGINS_SETUP.md](PLUGINS_SETUP.md) (German only)

## Summary

Adding a new plugin requires only 3 steps:

1. **Create plugin code** (lua/, plugins/, or external repo)
2. **Registration** (make/plugins/plugin-<name>.mk, 4 lines)
3. **Install rule** (plugins/Makefile or plugins/<name>.mk)

The build system handles:
- Environment variable passing
- Auto-cloning missing sources
- Compiler toolchain configuration
- Runtime synchronization

For questions: See `docs/PLUGINS_SETUP.md` or existing plugin examples.
