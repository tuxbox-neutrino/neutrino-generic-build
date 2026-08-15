# Neutrino Plugin Templates

This directory contains templates for creating new Neutrino plugins.

## Available Templates

### 1. Lua Plugin Template (`plugin-lua-template/`)

**Use for:** Script-based plugins without compilation

**Contains:**
- `my-plugin.lua` - Example Lua plugin with menu system
- `metadata.json` - Plugin metadata
- `README.md` - Documentation template
- `.gitignore` - Git ignore rules

**Best for:**
- Simple GUI extensions
- Menu systems
- Data processing scripts
- Quick prototypes

**Example use cases:**
- Media library browsers
- Settings managers
- Information displays
- Simple tools

### 2. Native Binary Plugin Template (`plugin-binary-template/`)

**Use for:** Compiled shared library plugins (.so)

**Contains:**
- `my-binary-plugin.cpp` - Example C++ plugin
- `Makefile` - Build configuration
- `metadata.json` - Plugin metadata
- `README.md` - Documentation template
- `.gitignore` - Git ignore rules

**Best for:**
- Performance-critical code
- Direct Neutrino API access
- Hardware interfacing
- Complex GUI components

**Example use cases:**
- Hardware control plugins
- Performance-intensive processing
- Native library integration
- System-level operations

### 3. Standalone Binary Plugin Template (`plugin-standalone-template/`)

**Use for:** Independent executables with optional Neutrino wrapper

**Contains:**
- `my-tool.c` - Example C tool
- `my-tool-wrapper.lua` - Neutrino menu wrapper
- `Makefile` - Build configuration
- `metadata.json` - Plugin metadata
- `README.md` - Documentation template
- `.gitignore` - Git ignore rules

**Best for:**
- External tools integration
- Command-line utilities
- Existing applications
- Independent programs

**Example use cases:**
- System utilities
- Media converters
- Network tools
- File managers

## Quick Start

### 1. Choose Your Template

Select the appropriate template based on your needs:

- **Lua** for simple scripts
- **Binary** for compiled plugins with Neutrino API
- **Standalone** for independent tools

### 2. Copy Template

```bash
# For Lua plugin
cp -r templates/plugin-lua-template /path/to/neutrino-make/lua/my-plugin

# For Binary plugin
cp -r templates/plugin-binary-template /path/to/neutrino-make/plugins/my-plugin

# For Standalone plugin
cp -r templates/plugin-standalone-template /path/to/neutrino-make/plugins/my-tool
```

### 3. Customize Template

1. Rename files (replace `my-plugin` or `my-tool` with your name)
2. Edit source code
3. Update `metadata.json`
4. Update `README.md`

### 4. Register Plugin

Create `make/plugins/plugin-<name>.mk`:

```makefile
PLUGIN_INSTALL_NAMES += my-plugin
PLUGIN_INSTALL_RULES += my-plugin:my-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-plugin:my-plugin
PLUGIN_CLEAN_DEFAULTS += my-plugin
```

### 5. Add Install Rule

Add to `plugins/Makefile` (example for Lua):

```makefile
.PHONY: my-plugin-install
my-plugin-install:
	@echo "[plugin] Installing my-plugin (Lua)"
	@mkdir -p "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin"
	@cp -av "$(ROOT_DIR)/lua/my-plugin/"*.lua "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin/"
	@cp -v "$(ROOT_DIR)/lua/my-plugin/metadata.json" "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin/"
```

### 6. Build and Test

```bash
make plugin-install-my-plugin
make runtime-sync
ALLOW_NON_ROOT=1 make run-now
```

## Template Structure

Each template includes:

### metadata.json

Plugin metadata for Neutrino and package managers:

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "Short description",
  "author": "Your Name <email>",
  "license": "GPL-2.0-or-later",
  "type": "lua|native|standalone"
}
```

### README.md

Documentation template with sections:
- Features
- Installation
- Usage
- Development
- Configuration
- License

### .gitignore

Standard ignore rules for:
- Build artifacts
- Temporary files
- IDE files
- OS-specific files

## Customization Tips

### Lua Plugins

1. Use `require()` for shared libraries:
   - `json` - JSON parsing
   - `n_gui` - Neutrino GUI helpers
   - `posix` - POSIX functions

2. Follow Neutrino API conventions:
   - Use `neutrino.ShowMsg()` for messages
   - Use `n_gui.menu` for menus
   - Handle errors gracefully

### Binary Plugins

1. Include Neutrino headers correctly
2. Export functions with `extern "C"`
3. Use pkg-config for dependencies
4. Add proper error handling

### Standalone Plugins

1. Follow Unix conventions (exit codes, signals)
2. Support `--help` and `--version`
3. Use standard paths for configuration
4. Provide Lua wrapper for Neutrino integration

## Testing Templates

### Test Lua Template

```bash
# Copy template
cp -r templates/plugin-lua-template lua/test-lua-plugin

# Register it: make/plugins/plugin-test-lua-plugin.mk plus the install rule in
# plugins/Makefile, exactly as the template's own README shows. `make plugins`
# will NOT pick it up on its own -- that aggregate walks the fixed PLUGINS_ALL
# list; a newly registered plugin is driven through plugin-install-<name>.

# Build and install
make plugin-install-test-lua-plugin

# Check installation
find artifacts/sysroot/usr/share/tuxbox/neutrino/luaplugins/test-lua-plugin/
```

### Test Binary Template

```bash
# Copy template
cp -r templates/plugin-binary-template plugins/test-binary-plugin

# Register it: make/plugins/plugin-test-binary-plugin.mk plus the
# test-binary-plugin-install rule in plugins/Makefile

# Build and install
make plugin-install-test-binary-plugin

# Check library
ldd artifacts/sysroot/usr/lib/tuxbox/neutrino/plugins/test-binary-plugin.so
```

### Test Standalone Template

```bash
# Copy template
cp -r templates/plugin-standalone-template plugins/test-tool

# Register it: make/plugins/plugin-test-tool.mk plus the
# test-tool-install rule in plugins/Makefile

# Build and install
make plugin-install-test-tool

# Test executable
./artifacts/sysroot/usr/bin/test-tool --help
```

## Documentation

For detailed guides, see:

- [HOWTO_ADD_PLUGIN.de.md](../docs/HOWTO_ADD_PLUGIN.de.md) (German)
- [HOWTO_ADD_PLUGIN.en.md](../docs/HOWTO_ADD_PLUGIN.en.md) (English)
- [HOWTO_ADD_TARGET.de.md](../docs/HOWTO_ADD_TARGET.de.md) (German)
- [HOWTO_ADD_TARGET.en.md](../docs/HOWTO_ADD_TARGET.en.md) (English)

## Contributing

If you create a new plugin template or improve existing ones:

1. Follow existing template structure
2. Include comprehensive README
3. Add metadata.json
4. Test template with clean build
5. Submit pull request

## License

These templates are released under GPL-2.0-or-later, same as neutrino-make.

You are free to use, modify, and distribute them.
