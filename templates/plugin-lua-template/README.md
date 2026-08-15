# My Plugin (Lua Template)

Short description of your plugin goes here.

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

### Via neutrino-make

```bash
# Copy this template to lua/my-plugin/
cp -r templates/plugin-lua-template /path/to/neutrino-make/lua/my-plugin

# Create plugin registration file
cat > /path/to/neutrino-make/make/plugins/plugin-my-plugin.mk <<'EOF'
PLUGIN_INSTALL_NAMES += my-plugin
PLUGIN_INSTALL_RULES += my-plugin:my-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += my-plugin:my-plugin
PLUGIN_CLEAN_DEFAULTS += my-plugin
EOF

# Add install rule to plugins/Makefile
cat >> /path/to/neutrino-make/plugins/Makefile <<'EOF'

.PHONY: my-plugin-install
my-plugin-install:
	@echo "[plugin] Installing my-plugin (Lua)"
	@mkdir -p "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin"
	@cp -av "$(ROOT_DIR)/lua/my-plugin/"*.lua "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin/"
	@cp -v "$(ROOT_DIR)/lua/my-plugin/metadata.json" "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/my-plugin/"
EOF

# Build and install
make plugin-install-my-plugin
make runtime-sync
```

### Manual Installation

```bash
# Copy plugin files to Neutrino plugin directory
mkdir -p root/usr/share/tuxbox/neutrino/luaplugins/my-plugin
cp my-plugin.lua root/usr/share/tuxbox/neutrino/luaplugins/my-plugin/
cp metadata.json root/usr/share/tuxbox/neutrino/luaplugins/my-plugin/
```

## Usage

1. Start Neutrino
2. Navigate to: Menu → Plugins → My Plugin
3. Select an option from the menu

## Configuration

Optional configuration can be stored in:
```
/var/tuxbox/config/my-plugin.conf
```

Example configuration format:
```ini
# My Plugin Configuration
option1=value1
option2=value2
```

## Development

### Testing

```bash
# Build and run
make plugin-install-my-plugin
make runtime-sync
ALLOW_NON_ROOT=1 make run-now
```

### Debugging

Enable Lua debugging in Neutrino:
Settings → System → Debug → Enable Lua Debug

Check logs:
```bash
tail -f logs/neutrino.log
```

## Dependencies

This plugin requires the following Lua libraries:
- `json` - JSON parsing
- `n_gui` - Neutrino GUI helpers
- `posix` - POSIX system functions

`json` and `n_gui` come from the shared helper repository
[plugin-scripts-lua](https://github.com/tuxbox-neutrino/plugin-scripts-lua);
`make plugins` fetches it and stages the helpers into the runtime tree, so
nothing has to be installed by hand. On a set-top box they arrive as the
`lua-json` and `lua-feedparser` packages. `posix` comes from your Lua
distribution (Debian/Ubuntu: `lua-posix`).

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
