# My Binary Plugin (Native Template)

Short description of your native plugin goes here.

## Features

- Feature 1
- Feature 2
- Feature 3

## Requirements

- GCC/G++ compiler
- Neutrino development headers
- pkg-config
- make

## Installation

### Via neutrino-make

```bash
# Copy this template to plugins/my-binary-plugin/
cp -r templates/plugin-binary-template /path/to/neutrino-make/plugins/my-binary-plugin

# Create plugin registration file
cat > /path/to/neutrino-make/make/plugins/plugin-my-binary-plugin.mk <<'EOF'
PLUGIN_INSTALL_NAMES += my-binary-plugin
PLUGIN_INSTALL_RULES += my-binary-plugin:my-binary-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-binary-plugin:my-binary-plugin
PLUGIN_CLEAN_DEFAULTS += my-binary-plugin
EOF

# Add install rule to plugins/Makefile
cat >> /path/to/neutrino-make/plugins/Makefile <<'EOF'

.PHONY: my-binary-plugin-install
my-binary-plugin-install:
	@echo "[plugin] Building my-binary-plugin (native)"
	@$(MAKE) -C "$(PLUGINS_DIR)/my-binary-plugin" \
		install
EOF

# Build and install
make plugin-install-my-binary-plugin
make runtime-sync
```

### Manual Build

```bash
# Build
make

# Install
sudo make install PREFIX=/usr

# Or install to custom location
make install DESTDIR=/tmp/staging PREFIX=/usr
```

## Usage

1. Start Neutrino
2. Navigate to: Menu → Plugins → My Binary Plugin
3. Plugin will execute and display its output

## Development

### Building

```bash
# Standard build
make

# Debug build
make CXXFLAGS="-O0 -g3 -DDEBUG"

# With specific compiler
make CXX=g++-13
```

### Testing

```bash
# Test loading the plugin
ldd my-binary-plugin.so

# Run within neutrino-make environment
make plugin-install-my-binary-plugin
make runtime-sync
ALLOW_NON_ROOT=1 make run-gdb
```

### Debugging

```bash
# Build with debug symbols
make clean
make CXXFLAGS="-O0 -g3 -DDEBUG"

# Run Neutrino with GDB
ALLOW_NON_ROOT=1 make run-gdb

# In GDB, set breakpoint:
(gdb) break plugin_exec
(gdb) continue
```

## API Reference

### Plugin Entry Points

#### `plugin_exec(PluginParam* param)`
Main entry point called when user selects the plugin.

**Parameters:**
- `param`: Plugin parameter structure

**Returns:**
- Modified or same `PluginParam*` pointer

#### `plugin_init()` (optional)
Called when Neutrino loads the plugin. Use for initialization.

#### `plugin_del()` (optional)
Called when Neutrino unloads the plugin. Use for cleanup.

#### `plugin_get_name()` (optional)
Returns plugin name as string.

#### `plugin_get_version()` (optional)
Returns plugin version as string.

## File Structure

```
my-binary-plugin/
├── my-binary-plugin.cpp   # Main plugin source
├── Makefile               # Build configuration
├── metadata.json          # Plugin metadata
├── README.md              # This file
└── .gitignore            # Git ignore rules
```

## License

GPL-2.0-or-later

## Author

Your Name <your.email@example.com>

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Changelog

### 1.0.0 (YYYY-MM-DD)
- Initial release
