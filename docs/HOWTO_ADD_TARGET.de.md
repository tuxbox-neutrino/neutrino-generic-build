# HowTo: Neues Build-Target hinzufügen

Dieses Dokument beschreibt, wie Sie neue Build-Targets zum modularen neutrino-make Build-System hinzufügen.

## Überblick über das Build-System

neutrino-make verwendet ein modulares Makefile-System mit klarer Trennung:

```
make/
├── main.mk           # Haupteinstiegspunkt, Bootstrap, Run-Targets
├── env.mk            # Umgebungsvariablen und Defaults
├── toolchain.mk      # Compiler und Toolchain-Konfiguration
├── deps.mk           # Abhängigkeits-Management (Python venv, etc.)
├── third_party.mk    # Third-Party-Koordination
├── third_party/      # Einzelne Third-Party-Builds
│   ├── luajit.mk
│   ├── lua.mk
│   ├── ffmpeg.mk
│   └── ...
├── neutrino.mk       # Neutrino Core Build
├── plugins.mk        # Plugin-Build-Koordination
├── tests.mk          # Test-Ausführung
└── package.mk        # Packaging-Targets
```

### Grundprinzipien

1. **Stamp-Files**: Build-Schritte werden durch `.stamp`-Dateien getrackt
2. **Idempotenz**: Targets können mehrfach aufgerufen werden, ohne neu zu bauen
3. **Phony-Deklarationen**: Alle Convenience-Targets sind `.PHONY`
4. **Umgebungsvariablen**: Konfiguration erfolgt über Variablen aus `env.mk`
5. **Help-Text**: Alle wichtigen Targets haben `## Beschreibung` Kommentare

## 1. Einfaches Build-Target hinzufügen

### Beispiel: Neue Hilfsfunktion

```makefile
# In make/main.mk oder make/utils.mk

.PHONY: check-environment
check-environment: ## Prüfe Build-Umgebung auf Vollständigkeit
	@echo "[check-environment] Prüfe System-Pakete..."
	@command -v gcc >/dev/null 2>&1 || { echo "ERROR: gcc nicht gefunden"; exit 1; }
	@command -v g++ >/dev/null 2>&1 || { echo "ERROR: g++ nicht gefunden"; exit 1; }
	@command -v pkg-config >/dev/null 2>&1 || { echo "ERROR: pkg-config nicht gefunden"; exit 1; }
	@echo "[check-environment] OK - Alle erforderlichen Tools vorhanden"
```

**Wichtige Elemente:**
- `.PHONY:` Deklaration, da kein File erzeugt wird
- `## Kommentar` für `make help` Integration
- `@echo` für Benutzer-Feedback (@ unterdrückt Befehlsausgabe)
- Fehlerbehandlung mit `|| { echo ...; exit 1; }`

## 2. Third-Party-Dependency hinzufügen

### Schritt 1: Neue Datei anlegen

Erstellen Sie `make/third_party/meine-lib.mk`:

```makefile
# Third-party library: meine-lib
# Wird nur gebaut wenn System-Version fehlt oder zu alt ist

MEINE_LIB_VERSION ?= 1.2.3
MEINE_LIB_URL := https://example.com/releases/meine-lib-$(MEINE_LIB_VERSION).tar.gz
MEINE_LIB_ARCHIVE := $(ARCHIVE_DIR)/meine-lib-$(MEINE_LIB_VERSION).tar.gz
MEINE_LIB_SRC_DIR := $(SOURCES_DIR)/meine-lib-$(MEINE_LIB_VERSION)
MEINE_LIB_BUILD_DIR := $(BUILD_DIR)/meine-lib
MEINE_LIB_STAMP := $(MEINE_LIB_SRC_DIR)/.installed

# System-Version prüfen
MEINE_LIB_SYSTEM_VERSION := $(shell pkg-config --modversion meine-lib 2>/dev/null || echo "0.0.0")
MEINE_LIB_NEEDS_BUILD := $(shell \
	if [ "$(MEINE_LIB_SYSTEM_VERSION)" = "0.0.0" ]; then \
		echo "yes"; \
	elif [ "$$(printf '%s\n' "$(MEINE_LIB_VERSION)" "$(MEINE_LIB_SYSTEM_VERSION)" | sort -V | head -n1)" != "$(MEINE_LIB_VERSION)" ]; then \
		echo "yes"; \
	else \
		echo "no"; \
	fi)

# Build-Target mit Force-Option
ifeq ($(MEINE_LIB_FORCE),1)
MEINE_LIB_NEEDS_BUILD := yes
endif

.PHONY: deps-meine-lib
deps-meine-lib:
ifeq ($(MEINE_LIB_NEEDS_BUILD),yes)
	@echo "[third-party] Building meine-lib $(MEINE_LIB_VERSION) (system: $(MEINE_LIB_SYSTEM_VERSION))"
	@$(MAKE) $(MEINE_LIB_STAMP)
else
	@echo "[third-party] Using system meine-lib $(MEINE_LIB_SYSTEM_VERSION)"
endif

# Download
$(MEINE_LIB_ARCHIVE):
	@echo "[third-party] Downloading meine-lib $(MEINE_LIB_VERSION)"
	@$(MKDIR_P) $(ARCHIVE_DIR)
	@wget -O "$@.tmp" "$(MEINE_LIB_URL)" && mv "$@.tmp" "$@"

# Entpacken
$(MEINE_LIB_SRC_DIR)/.unpacked: $(MEINE_LIB_ARCHIVE)
	@echo "[third-party] Extracting meine-lib"
	@$(MKDIR_P) $(SOURCES_DIR)
	@tar -xzf "$(MEINE_LIB_ARCHIVE)" -C "$(SOURCES_DIR)"
	@touch $@

# Konfigurieren
$(MEINE_LIB_SRC_DIR)/.configured: $(MEINE_LIB_SRC_DIR)/.unpacked
	$(call ENFORCE_GCC_VERSION)
	@echo "[third-party] Configuring meine-lib"
	@$(MKDIR_P) $(MEINE_LIB_BUILD_DIR)
	@cd $(MEINE_LIB_BUILD_DIR) && \
		$(MEINE_LIB_SRC_DIR)/configure \
			--prefix=$(NEUTRINO_PREFIX) \
			--enable-shared \
			--disable-static \
			CC="$(CC)" \
			CXX="$(CXX)" \
			CFLAGS="$(CFLAGS)" \
			CXXFLAGS="$(CXXFLAGS)" \
			LDFLAGS="$(LDFLAGS)"
	@touch $@

# Bauen
$(MEINE_LIB_SRC_DIR)/.built: $(MEINE_LIB_SRC_DIR)/.configured
	@echo "[third-party] Building meine-lib"
	@$(MAKE) -C $(MEINE_LIB_BUILD_DIR) -j$(shell nproc)
	@touch $@

# Installieren
$(MEINE_LIB_STAMP): $(MEINE_LIB_SRC_DIR)/.built
	@echo "[third-party] Installing meine-lib to sysroot"
	@$(MAKE) -C $(MEINE_LIB_BUILD_DIR) DESTDIR="$(NEUTRINO_INSTALL_DIR)" install
	@touch $@

# Force-Build-Target
.PHONY: deps-meine-lib-force meine-lib-force
deps-meine-lib-force meine-lib-force: ## Build meine-lib lokal (immer, ignoriert Host-Version)
	@$(MAKE) MEINE_LIB_FORCE=1 deps-meine-lib

# Versionsspezifisches Target
.PHONY: deps-meine-lib-% meine-lib-%
deps-meine-lib-% meine-lib-%: ## Build meine-lib <version> lokal (immer, ignoriert Host-Version)
	@$(MAKE) MEINE_LIB_FORCE=1 MEINE_LIB_VERSION=$* deps-meine-lib

# Clean-Target
.PHONY: clean-meine-lib
clean-meine-lib:
	@echo "[third-party] Cleaning meine-lib"
	@rm -rf $(MEINE_LIB_BUILD_DIR)
	@rm -f $(MEINE_LIB_SRC_DIR)/.configured $(MEINE_LIB_SRC_DIR)/.built $(MEINE_LIB_STAMP)
```

### Schritt 2: In Third-Party-Koordination einfügen

In `make/third_party.mk`:

```makefile
# Füge meine-lib zu Third-Party-Targets hinzu
include make/third_party/meine-lib.mk

# Füge zu THIRD_PARTY_TARGETS hinzu (falls vorhanden)
THIRD_PARTY_TARGETS += deps-meine-lib
```

### Schritt 3: In Bootstrap-Sequence integrieren (optional)

Falls die Library für Neutrino-Core erforderlich ist, in `make/main.mk`:

```makefile
.PHONY: bootstrap
bootstrap: ## Vollständiger Build von Grund auf
	@echo "==> Bootstrap: Phase 1 - Dependencies"
	@$(MAKE) deps
	@$(MAKE) runtime-sync
	@$(MAKE) deps-meine-lib    # <-- Hier einfügen
	@echo "==> Bootstrap: Phase 2 - Lua toolchain"
	@$(MAKE) lua-deps
	# ... rest
```

## 3. Stamp-File-Pattern verstehen

### Warum Stamp-Files?

Stamp-Files verhindern unnötige Rebuilds und tracken Build-Status:

```makefile
# Schlechtes Beispiel (baut immer neu):
.PHONY: build-foo
build-foo:
	./configure && make && make install

# Gutes Beispiel (baut nur wenn nötig):
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

### Typische Stamp-File-Kette

```
.unpacked  → .patched  → .configured  → .built  → .installed
```

**Beispiel mit Patches:**

```makefile
# Patches anwenden
$(FOO_SRC_DIR)/.patched: $(FOO_SRC_DIR)/.unpacked
	@echo "[third-party] Patching foo"
	@if [ -d files/foo/patches ]; then \
		for p in files/foo/patches/*.patch; do \
			echo "  Applying $$(basename $$p)"; \
			patch -d $(FOO_SRC_DIR) -p1 < $$p; \
		done; \
	fi
	@touch $@

# Konfiguration hängt von Patching ab
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.patched
	./configure ...
	@touch $@
```

## 4. GCC-Version-Enforcement hinzufügen

Für alle C/C++-Builds **muss** GCC-Version-Checking erfolgen:

```makefile
$(FOO_SRC_DIR)/.configured: $(FOO_SRC_DIR)/.unpacked
	$(call ENFORCE_GCC_VERSION)    # <-- Immer vor ./configure
	@echo "[third-party] Configuring foo"
	@cd $(FOO_BUILD_DIR) && \
		$(FOO_SRC_DIR)/configure \
			CC="$(CC)" \
			CXX="$(CXX)" \
			...
	@touch $@
```

**Warum?** Verhindert ABI-Inkompatibilität zwischen Libraries, die mit verschiedenen GCC-Versionen gebaut wurden.

## 5. Help-Text hinzufügen

Alle User-facing Targets benötigen Help-Text:

```makefile
.PHONY: mein-target
mein-target: ## Kurze Beschreibung (max. 60 Zeichen)
	# ... Implementation
```

Der `## Kommentar` wird automatisch von `make help` geparst und angezeigt:

```bash
$ make help
...
  mein-target       : Kurze Beschreibung (max. 60 Zeichen)
...
```

**Best Practices:**
- Beschreibung in Imperativ ("Build", "Install", "Clean")
- Parameter in `<spitze klammern>` (z.B. `Build foo <version>`)
- Optionale Flags dokumentieren

## 6. Test-Target hinzufügen

### Beispiel: Neuer Test-Typ

In `make/tests.mk`:

```makefile
.PHONY: test-meine-lib
test-meine-lib: deps-meine-lib ## Test meine-lib Installation
	@echo "[test] Checking meine-lib installation"
	@pkg-config --exists meine-lib || { echo "ERROR: meine-lib.pc not found"; exit 1; }
	@pkg-config --modversion meine-lib
	@echo "[test] meine-lib OK"

# Zu Haupt-Test-Target hinzufügen
.PHONY: test
test: test-build test-gui test-web test-meine-lib ## Alle Tests ausführen
	@echo "[test] All tests completed"
```

## 7. Package-Target hinzufügen

### Beispiel: Neues Package-Format

In `make/package.mk`:

```makefile
.PHONY: package-flatpak
package-flatpak: bootstrap ## Erstelle Flatpak-Paket
	@echo "[package] Building Flatpak"
	@$(MKDIR_P) $(OUTPUT_DIR)/flatpak
	@flatpak-builder \
		--force-clean \
		--repo=$(OUTPUT_DIR)/flatpak/repo \
		$(OUTPUT_DIR)/flatpak/build \
		packaging/flatpak/de.tuxbox.neutrino.yml
	@echo "[package] Flatpak created: $(OUTPUT_DIR)/flatpak/repo"
```

## 8. Convenience-Aliases hinzufügen

Kurze Aliases für häufig verwendete Targets:

```makefile
# In make/main.mk

.PHONY: b
b: bootstrap ## Alias für bootstrap

.PHONY: r
r: run ## Alias für run

.PHONY: c
c: clean ## Alias für clean

.PHONY: t
t: test ## Alias für test
```

## 9. Abhängigkeits-Ketten definieren

### Beispiel: Multi-Stage-Build

```makefile
# Stage 1: Prepare
.PHONY: prepare-foo
prepare-foo:
	@echo "[foo] Preparing..."
	@$(MKDIR_P) $(FOO_BUILD_DIR)

# Stage 2: Configure (hängt von Stage 1 ab)
.PHONY: configure-foo
configure-foo: prepare-foo deps-meine-lib
	@echo "[foo] Configuring..."
	./configure --with-meine-lib

# Stage 3: Build (hängt von Stage 2 ab)
.PHONY: build-foo
build-foo: configure-foo
	@echo "[foo] Building..."
	make -C $(FOO_BUILD_DIR)

# Stage 4: Install (hängt von Stage 3 ab)
.PHONY: install-foo
install-foo: build-foo
	@echo "[foo] Installing..."
	make -C $(FOO_BUILD_DIR) DESTDIR="$(NEUTRINO_INSTALL_DIR)" install

# Haupt-Target (führt alle Stages aus)
.PHONY: foo
foo: install-foo ## Build und installiere foo
```

## 10. Fehlerbehandlung und Robustheit

### Beispiel: Robuste Download-Funktion

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

### Beispiel: Directory-Existence-Checks

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

### Beispiel: Command-Existence-Checks

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

## 11. Umgebungsvariablen verwenden

### Konfigurierbare Variablen

In `make/env.mk`:

```makefile
# Neue Variable hinzufügen
FOO_ENABLE_FEATURE_X ?= 1
FOO_PREFIX ?= $(NEUTRINO_PREFIX)
FOO_CONFIG_FLAGS ?=

# Exportieren für Sub-Makes
export FOO_ENABLE_FEATURE_X FOO_PREFIX FOO_CONFIG_FLAGS
```

In `Makefile.local.sample`:

```makefile
#FOO_ENABLE_FEATURE_X := 0
#  Deaktiviere Feature X in foo (Standard: 1)

#FOO_CONFIG_FLAGS := --with-ssl --with-zlib
#  Zusätzliche Flags für foo's ./configure
```

### Variable in Target verwenden

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

## 12. Parallele Builds kontrollieren

### Sequenziellen Build erzwingen

Für problematische Builds (z.B. FFmpeg):

```makefile
$(FOO_SRC_DIR)/.built: $(FOO_SRC_DIR)/.configured
	@echo "[third-party] Building foo (sequential)"
	@$(MAKE) -C $(FOO_BUILD_DIR) -j1    # <-- Force single job
	@touch $@
```

### Parallelen Build mit Limit

```makefile
$(FOO_SRC_DIR)/.built: $(FOO_SRC_DIR)/.configured
	@echo "[third-party] Building foo (parallel)"
	@$(MAKE) -C $(FOO_BUILD_DIR) -j$(shell nproc)    # <-- Use all cores
	@touch $@
```

## 13. Vollständiges Beispiel

### Neues Tool "myapp" hinzufügen

**Datei:** `make/myapp.mk`

```makefile
# MyApp - Example application build

MYAPP_VERSION ?= 2.1.0
MYAPP_URL := https://github.com/user/myapp/archive/v$(MYAPP_VERSION).tar.gz
MYAPP_ARCHIVE := $(ARCHIVE_DIR)/myapp-$(MYAPP_VERSION).tar.gz
MYAPP_SRC_DIR := $(SOURCES_DIR)/myapp-$(MYAPP_VERSION)
MYAPP_BUILD_DIR := $(BUILD_DIR)/myapp
MYAPP_STAMP := $(MYAPP_SRC_DIR)/.installed

.PHONY: myapp
myapp: ## Build und installiere myapp
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
bootstrap: ## Vollständiger Build
	# ...
	@$(MAKE) myapp
	# ...
```

## Best Practices Zusammenfassung

1. ✅ **Stamp-Files verwenden** für Build-Schritte
2. ✅ **GCC-Version prüfen** bei C/C++-Builds
3. ✅ **Help-Text hinzufügen** mit `## Kommentar`
4. ✅ **Phony-Targets deklarieren** mit `.PHONY:`
5. ✅ **Fehlerbehandlung** mit `|| { echo ...; exit 1; }`
6. ✅ **Variablen aus env.mk nutzen** statt Hard-Coding
7. ✅ **Clean-Targets bereitstellen** für alle Builds
8. ✅ **Test-Targets hinzufügen** wo sinnvoll
9. ✅ **Dependency-Chains korrekt definieren**
10. ✅ **Robuste Downloads** mit Retries

## Troubleshooting

### Problem: Target wird nicht ausgeführt

```bash
# Prüfen, ob Target existiert
make -n mein-target

# Prüfen, ob .PHONY deklariert ist
grep "\.PHONY.*mein-target" make/*.mk
```

### Problem: Stamp-File wird nicht erstellt

```bash
# Prüfen, ob @touch $@ am Ende steht
grep -A 5 "mein-target:" make/*.mk | grep touch

# Manuell prüfen
ls -la $(SOURCES_DIR)/foo/.installed
```

### Problem: Dependencies werden ignoriert

```bash
# Abhängigkeiten anzeigen
make -p | grep -A 3 "^mein-target:"

# Dry-run mit Debug
make -n -d mein-target
```

## Weitere Ressourcen

- Bestehende Makefiles als Vorlagen: `make/third_party/*.mk`
- Umgebungsvariablen: [make/env.mk](../make/env.mk)
- Toolchain-Setup: [make/toolchain.mk](../make/toolchain.mk)
- Bootstrap-Flow: [make/main.mk](../make/main.mk)
- Plugin-System: [HOWTO_ADD_PLUGIN.de.md](HOWTO_ADD_PLUGIN.de.md)
