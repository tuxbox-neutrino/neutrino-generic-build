# My Tool (Standalone Plugin Template)

Short description of your standalone tool goes here.

## Overview

This is a standalone binary plugin that runs as an independent program. It includes:
- A C-based command-line tool (`my-tool`)
- Optional Lua wrapper for Neutrino integration (`my-tool-wrapper.lua`)

## Features

- Feature 1
- Feature 2
- Feature 3

## Requirements

### Build Requirements
- GCC compiler
- make

### Runtime Requirements
- None (standalone binary)

## Installation

### Via neutrino-make

```bash
# Copy this template to plugins/my-tool/
cp -r templates/plugin-standalone-template /path/to/neutrino-make/plugins/my-tool

# Create plugin registration file
cat > /path/to/neutrino-make/make/plugins/plugin-my-tool.mk <<'EOF'
PLUGIN_INSTALL_NAMES += my-tool
PLUGIN_INSTALL_RULES += my-tool:my-tool-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-tool:my-tool
PLUGIN_CLEAN_DEFAULTS += my-tool
EOF

# Add install rule to plugins/Makefile
cat >> /path/to/neutrino-make/plugins/Makefile <<'EOF'

.PHONY: my-tool-install
my-tool-install:
	@echo "[plugin] Building my-tool (standalone)"
	@if [ ! -d "$(PLUGINS_DIR)/my-tool" ]; then \
		echo "[plugin] ERROR: $(PLUGINS_DIR)/my-tool not found"; \
		exit 1; \
	fi
	@$(MAKE) -C "$(PLUGINS_DIR)/my-tool" \
		install
	# Install Lua wrapper
	@mkdir -p "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-tool"
	@cp -v "$(PLUGINS_DIR)/my-tool/my-tool-wrapper.lua" \
		"$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-tool/"
EOF

# Build and install
make plugin-install-my-tool
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

### Command Line

```bash
# Show help
my-tool --help

# Show version
my-tool --version

# Run with options
my-tool --verbose --output result.txt
```

### From Neutrino

1. Start Neutrino
2. Navigate to: Menu → Plugins → My Tool
3. Tool will execute and display results

## Development

### Building

```bash
# Standard build
make

# Debug build
make CFLAGS="-O0 -g3 -DDEBUG"

# With specific compiler
make CC=gcc-13
```

### Testing

```bash
# Test executable
./my-tool --help
./my-tool --version

# Test within neutrino-make
make plugin-install-my-tool
make runtime-sync
ALLOW_NON_ROOT=1 make run-now
```

### Adding Dependencies

If your tool needs external libraries:

```makefile
# In Makefile, add pkg-config support
CFLAGS += $(shell $(PKG_CONFIG) --cflags libfoo)
LDFLAGS += $(shell $(PKG_CONFIG) --libs libfoo)
```

### Converting to Autotools

For larger projects, consider using autotools:

```bash
# Create configure.ac and Makefile.am
autoreconf -i
./configure --prefix=/usr
make
make install
```

## File Structure

```
my-tool/
├── my-tool.c              # Main tool source
├── my-tool-wrapper.lua    # Neutrino wrapper (optional)
├── Makefile               # Build configuration
├── metadata.json          # Plugin metadata
├── README.md              # This file
├── .gitignore            # Git ignore rules
└── data/                 # Optional data files
```

## Configuration

Configuration can be stored in:
```
/var/tuxbox/config/my-tool.conf
```

Example configuration format:
```ini
# My Tool Configuration
option1=value1
option2=value2
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
