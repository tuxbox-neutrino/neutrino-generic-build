# HowTo: Neues Plugin hinzufügen

Dieses Dokument beschreibt, wie Sie ein neues Plugin zum neutrino-make Build-System hinzufügen.

## Überblick über Plugin-Typen

neutrino-make unterstützt drei Plugin-Typen:

1. **Lua-Plugins** (Skript-basiert)
   - Reine Lua-Skripte ohne Kompilierung
   - Am einfachsten zu erstellen und zu warten
   - Beispiele: neutrino-mediathek, webtv, logoupdater

2. **Native Binary-Plugins** (Shared Libraries)
   - Kompilierte `.so` Dateien, die von Neutrino geladen werden
   - Zugriff auf Neutrino-API via Header
   - Beispiele: FritzInfoMonitor, FritzCallMonitor

3. **Standalone Binary-Plugins** (Executables)
   - Eigenständige Programme mit optionalem Neutrino-Wrapper
   - Eigener Build-Prozess (autotools, cmake, make)
   - Beispiele: tuxwetter, sysinfo, msgbox

## Voraussetzungen

- Funktionierendes neutrino-make Build-Environment
- Erfolgreich ausgeführtes `make bootstrap`
- Plugin-Quellcode (lokal oder als Git-Repository)

## 1. Lua-Plugin hinzufügen

### Schritt 1: Plugin-Struktur anlegen

```bash
mkdir -p lua/mein-plugin
cd lua/mein-plugin

# Haupt-Plugin-Datei
cat > mein-plugin.lua <<'EOF'
-- Mein erstes Neutrino Lua Plugin
local json = require("json")
local n_gui = require("n_gui")

function main()
    local menu = n_gui.menu.new("Mein Plugin", "info")
    menu:addItem{
        type = "forwarder",
        name = "Hallo Welt",
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

# Metadata-Datei (optional, aber empfohlen)
cat > metadata.json <<'EOF'
{
  "name": "mein-plugin",
  "version": "1.0.0",
  "description": "Mein erstes Neutrino Lua Plugin",
  "author": "Dein Name <email@example.com>",
  "license": "GPL-2.0-or-later",
  "type": "lua"
}
EOF
```

### Schritt 2: Plugin-Registrierung

Erstellen Sie eine neue Datei `make/plugins/plugin-mein-plugin.mk`:

```makefile
PLUGIN_INSTALL_NAMES += mein-plugin
PLUGIN_INSTALL_RULES += mein-plugin:mein-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += mein-plugin:mein-plugin
PLUGIN_CLEAN_DEFAULTS += mein-plugin
```

**Erklärung der Variablen:**
- `PLUGIN_INSTALL_NAMES`: Liste der Plugin-Namen für `make plugins`
- `PLUGIN_INSTALL_RULES`: Mapping von Name zu Install-Target (Format: `name:target`)
- `PLUGIN_INSTALL_ALIAS_PAIRS`: Aliase für vereinfachte Aufrufe (Format: `alias:canonical-name`)
- `PLUGIN_CLEAN_DEFAULTS`: Plugins, die bei `make clean-plugins` entfernt werden

### Schritt 3: Install-Rule hinzufügen

In `plugins/Makefile` oder einer neuen Datei `plugins/mein-plugin.mk`:

```makefile
.PHONY: mein-plugin-install
mein-plugin-install:
	@echo "[plugin] Installing mein-plugin (Lua)"
	@mkdir -p "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/mein-plugin"
	@cp -av "$(ROOT_DIR)/lua/mein-plugin/"*.lua "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/mein-plugin/"
	@if [ -f "$(ROOT_DIR)/lua/mein-plugin/metadata.json" ]; then \
		cp -v "$(ROOT_DIR)/lua/mein-plugin/metadata.json" "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/mein-plugin/"; \
	fi
```

### Schritt 4: Plugin bauen und testen

```bash
# Alle Plugins bauen (inkl. neu registriertes mein-plugin)
make plugins

# Runtime synchronisieren
make runtime-sync

# Neutrino starten und Plugin testen
ALLOW_NON_ROOT=1 make run-now
```

### Shared Lua-Bibliotheken verwenden

Wenn Ihr Plugin gemeinsame Lua-Bibliotheken benötigt (z.B. `json.lua`, `n_gui.lua`):

```bash
# Die Bibliotheken liegen im eigenen Repository tuxbox-neutrino/plugin-scripts-lua.
# `make plugins` klont es beim ersten Mal nach sources/plugin-scripts-lua/ und
# stellt share/lua/5.x/ im Runtime-Baum bereit -- nichts muss von Hand geholt werden.
```

Im Plugin verwenden:

```lua
local json = require("json")
local n_gui = require("n_gui")
-- Diese Module stammen aus plugin-scripts-lua und liegen im Runtime-Baum
```

## 2. Native Binary-Plugin hinzufügen (.so)

### Schritt 1: Plugin-Quellcode anlegen

```bash
mkdir -p plugins/mein-binary-plugin
cd plugins/mein-binary-plugin

# Haupt-C++-Datei
cat > mein-binary-plugin.cpp <<'EOF'
#include <plugin.h>
#include <neutrino.h>

extern "C" {
    PluginParam* plugin_exec(PluginParam* param) {
        // Ihr Plugin-Code hier
        printf("Mein Binary Plugin läuft!\n");
        return param;
    }
}
EOF

# Makefile
cat > Makefile <<'EOF'
PLUGIN_NAME = mein-binary-plugin

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

### Schritt 2: Plugin-Registrierung

Datei `make/plugins/plugin-mein-binary-plugin.mk`:

```makefile
PLUGIN_INSTALL_NAMES += mein-binary-plugin
PLUGIN_INSTALL_RULES += mein-binary-plugin:mein-binary-plugin-install
PLUGIN_INSTALL_ALIAS_PAIRS += mein-binary-plugin:mein-binary-plugin
PLUGIN_CLEAN_DEFAULTS += mein-binary-plugin
```

### Schritt 3: Install-Rule mit Compiler-Umgebung

In `plugins/Makefile`:

```makefile
.PHONY: mein-binary-plugin-install
mein-binary-plugin-install:
	@echo "[plugin] Building mein-binary-plugin (native)"
	@if [ ! -d "$(PLUGINS_DIR)/mein-binary-plugin" ]; then \
		echo "[plugin] ERROR: $(PLUGINS_DIR)/mein-binary-plugin nicht gefunden"; \
		exit 1; \
	fi
	@$(PLUGIN_ENV_ARGS) $(MAKE) -C "$(PLUGINS_DIR)/mein-binary-plugin" install
```

**Wichtig:** `$(PLUGIN_ENV_ARGS)` exportiert automatisch:
- CC, CXX, CFLAGS, CXXFLAGS, LDFLAGS
- PKG_CONFIG_PATH, PKG_CONFIG_SYSROOT_DIR
- Alle N_* Pfadvariablen
- NEUTRINO_SRC_DIR, LIBSTB_HAL_DIR

### Schritt 4: Testen

```bash
# Alle Plugins bauen (inkl. neu registriertes mein-binary-plugin)
make plugins

# Runtime synchronisieren
make runtime-sync

# Neutrino starten und Plugin testen
ALLOW_NON_ROOT=1 make run-now
```

## 3. Standalone Binary-Plugin hinzufügen

### Schritt 1: Externes Projekt integrieren

Für Projekte mit eigenem Build-System (autotools, cmake):

```bash
# Plugin-Quellen als Git-Submodule
git submodule add https://github.com/user/mein-tool.git plugins/mein-tool

# Oder lokales Verzeichnis
mkdir -p plugins/mein-tool
# ... Quellen kopieren ...
```

### Schritt 2: Build-Wrapper erstellen

In `plugins/Makefile`:

```makefile
.PHONY: mein-tool-install
mein-tool-install:
	@echo "[plugin] Building mein-tool (standalone)"
	@if [ ! -d "$(PLUGINS_DIR)/mein-tool" ]; then \
		echo "[plugin] Auto-cloning mein-tool..."; \
		git clone https://github.com/user/mein-tool.git "$(PLUGINS_DIR)/mein-tool"; \
	fi
	@cd "$(PLUGINS_DIR)/mein-tool" && \
		if [ ! -f Makefile ]; then \
			./autogen.sh && \
			$(PLUGIN_ENV_ARGS) ./configure --prefix="$(PREFIX)"; \
		fi && \
		$(PLUGIN_ENV_ARGS) $(MAKE) && \
		$(PLUGIN_ENV_ARGS) $(MAKE) DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX)" install
```

**Auto-Cloning-Support:** Wenn das Plugin-Verzeichnis fehlt, wird es automatisch geklont.

### Schritt 3: Plugin-Registrierung

Datei `make/plugins/plugin-mein-tool.mk`:

```makefile
PLUGIN_INSTALL_NAMES += mein-tool
PLUGIN_INSTALL_RULES += mein-tool:mein-tool-install
PLUGIN_INSTALL_ALIAS_PAIRS += mein-tool:mein-tool
PLUGIN_CLEAN_DEFAULTS += mein-tool
```

### Schritt 4: Optional - Neutrino-Wrapper hinzufügen

Wenn Ihr Tool einen Neutrino-Menüeintrag benötigt:

```bash
mkdir -p lua/mein-tool-wrapper
cat > lua/mein-tool-wrapper/mein-tool.lua <<'EOF'
local posix = require("posix")

function main()
    -- Tool aufrufen
    os.execute("/usr/bin/mein-tool")
end

return {run = main}
EOF
```

Fügen Sie den Lua-Wrapper wie in Abschnitt 1 beschrieben hinzu.

## Testing und Debugging

### Isoliertes Plugin-Testing

```bash
# Plugin manuell installieren (ohne Bootstrap)
make mein-plugin-install DESTDIR=$PWD/test-install PREFIX=/usr

# Installierte Dateien prüfen
find test-install -type f

# Regulärer Build mit Runtime-Sync und Test
make plugins
make runtime-sync
ALLOW_NON_ROOT=1 make run-now
```

### Debugging bei Build-Fehlern

```bash
# Verbose Make-Output (für alle Plugins)
make plugins V=1

# Einzelnes Plugin mit Debug-Informationen bauen
make mein-plugin-install V=1 DESTDIR=artifacts/sysroot PREFIX=/usr

# Plugin-Directory-Inhalt prüfen
ls -la plugins/mein-plugin/
ls -la $(PLUGINS_DIR)/mein-plugin/

# Sysroot-Inhalt prüfen
ls -la artifacts/sysroot/usr/share/tuxbox/neutrino/plugins/
ls -la artifacts/sysroot/usr/lib/tuxbox/neutrino/plugins/
```

### Runtime-Debugging

```bash
# Mit GDB starten
ALLOW_NON_ROOT=1 make run-gdb

# Mit Valgrind
make run-valgrind

# Log-Output prüfen
tail -f logs/neutrino.log
```

## Best Practices

### Naming-Konventionen

- **Lua-Plugins:** `plugin-lua-<name>` (Repository), `<name>` (Makefile)
- **Binary-Plugins:** `plugin-bin-<name>` (Repository), `<name>` (Makefile)
- **Makefile-Fragmente:** `make/plugins/plugin-<name>.mk`

### Metadaten

Fügen Sie immer eine `metadata.json` hinzu:

```json
{
  "name": "mein-plugin",
  "version": "1.0.0",
  "description": "Kurze Beschreibung",
  "author": "Ihr Name <email@example.com>",
  "license": "GPL-2.0-or-later",
  "type": "lua|native|standalone",
  "dependencies": ["json", "n_gui"],
  "neutrino_min_version": "3.2.0"
}
```

### Versionierung

- Verwenden Sie Semantic Versioning (SemVer): `MAJOR.MINOR.PATCH`
- Git-Tags für Releases: `v1.0.0`
- Breaking Changes → Major-Version erhöhen

### Dokumentation

Erstellen Sie ein `README.md` im Plugin-Verzeichnis:

```markdown
# Mein Plugin

Kurzbeschreibung des Plugins.

## Installation

make plugins
make runtime-sync

## Verwendung

1. Neutrino starten
2. Menü → Plugins → Mein Plugin

## Konfiguration

Optionale Konfigurationsdateien unter:
/var/tuxbox/config/mein-plugin.conf

## Lizenz

GPL-2.0-or-later
```

### Clean-Target hinzufügen

In `plugins/Makefile`:

```makefile
.PHONY: clean-mein-plugin
clean-mein-plugin:
	@echo "[plugin] Cleaning mein-plugin"
	@rm -rf "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins/mein-plugin"
	@rm -rf "$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/plugins/mein-plugin"
	@rm -f "$(DESTDIR)$(PREFIX)/lib/tuxbox/neutrino/plugins/mein-plugin.so"
	@if [ -d "$(PLUGINS_DIR)/mein-plugin" ]; then \
		$(MAKE) -C "$(PLUGINS_DIR)/mein-plugin" clean 2>/dev/null || true; \
	fi
```

## Troubleshooting

### Problem: Plugin wird nicht gefunden

```bash
# Prüfen, ob Plugin registriert ist
grep -r "mein-plugin" make/plugins/

# Prüfen, ob Install-Rule existiert
grep -r "mein-plugin-install" plugins/Makefile make/plugins/

# Plugin-Namen-Liste anzeigen
make list-plugin-targets
```

### Problem: Kompilierung schlägt fehl

```bash
# GCC-Version prüfen
$(CC) --version

# PKG_CONFIG_PATH prüfen
echo $PKG_CONFIG_PATH
pkg-config --list-all | grep neutrino

# Header-Dateien prüfen
ls -la artifacts/sysroot/usr/include/neutrino/
```

### Problem: Plugin läuft nicht

```bash
# Neutrino-Log prüfen
tail -f logs/neutrino.log

# Lua-Fehler debuggen (für Lua-Plugins)
# In Neutrino: Settings → System → Debug → Lua Debug aktivieren

# Shared Library Dependencies prüfen (für .so Plugins)
ldd artifacts/sysroot/usr/lib/tuxbox/neutrino/plugins/mein-plugin.so
```

### Problem: Auto-Cloning schlägt fehl

```bash
# Git-URL prüfen
git ls-remote https://github.com/user/mein-tool.git

# Manuell klonen
git clone https://github.com/user/mein-tool.git plugins/mein-tool

# Rebuild versuchen
make clean-plugin-mein-tool
make plugins
```

## Weitere Ressourcen

- Beispiel-Plugins: `plugins/Makefile` (neutrino-mediathek, FritzInfoMonitor)
- Plugin-Variablen: `make/plugins.mk` (PLUGIN_ENV_VARS-Liste, PLUGIN_ENV_ARGS exportiert sie)
- Lua-Bibliotheken: [tuxbox-neutrino/plugin-scripts-lua](https://github.com/tuxbox-neutrino/plugin-scripts-lua) (wird bei Bedarf nach `sources/plugin-scripts-lua/` geklont)
- Migration-Guide: [PLUGINS_SETUP.md](PLUGINS_SETUP.md)

## Zusammenfassung

Ein neues Plugin hinzufügen erfordert nur 3 Schritte:

1. **Plugin-Code anlegen** (lua/, plugins/, oder externes Repo)
2. **Registrierung** (make/plugins/plugin-<name>.mk, 4 Zeilen)
3. **Install-Rule** (plugins/Makefile oder plugins/<name>.mk)

Das Build-System übernimmt:
- Umgebungsvariablen-Passing
- Auto-Cloning fehlender Quellen
- Compiler-Toolchain-Konfiguration
- Runtime-Synchronisation

Bei Fragen: Siehe `docs/PLUGINS_SETUP.md` oder bestehende Plugin-Beispiele.
