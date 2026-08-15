# Placeholder rules for building and installing native plugins.

PLUGINS_DIR ?= $(ROOT_DIR)/plugins
PLUGINS_BUILD_DIR ?= $(BUILD_DIR)/plugins
PLUGINS_INSTALL_DIR ?= $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib/neutrino/plugins
PLUGIN_INSTALL_NAMES :=
PLUGIN_INSTALL_RULES :=
PLUGIN_INSTALL_ALIAS_PAIRS :=
PLUGIN_CLEAN_DEFAULTS :=
PLUGIN_CLEAN_HOOKS :=
PLUGIN_RESERVED_NAMES := mnt
PLUGIN_MODULES := $(wildcard $(ROOT_DIR)/make/plugins/plugin-*.mk)

SYSROOT := $(NEUTRINO_INSTALL_DIR)

PLUGIN_ENV_VARS = \
	CC CXX AR RANLIB STRIP PKG_CONFIG PKG_CONFIG_SYSROOT_DIR \
	PKG_CONFIG_PATH PKG_CONFIG_LIBDIR \
	SYSROOT NEUTRINO_SRC_DIR NEUTRINO_BUILD_DIR NEUTRINO_INSTALL_DIR NEUTRINO_PREFIX \
	NEUTRINO_RUNTIME_PREFIX_ABS \
	STB_HAL_INCLUDE_DIR STB_HAL_LIBRARY_DIR \
	N_PREFIX N_SYSCONFDIR N_LOCALSTATEDIR N_CONFIG_DIR N_CONTROLDIR \
	N_CONTROLDIR_VAR N_DATADIR N_DATADIR_VAR N_FLAGDIR N_FONTDIR \
	N_FONTDIR_VAR N_GAMES_DIR N_HOSTED_HTTPDDIR N_ICONS_DIR \
	N_ICONS_DIR_VAR N_LIBDIR N_LOCALEDIR N_LOCALEDIR_VAR N_LOGODIR \
	N_LOGODIR_VAR N_PLUGIN_DIR N_PLUGIN_DIR_VAR N_PLUGIN_DIR_MNT \
	N_LUAPLUGIN_DIR N_LUAPLUGIN_DIR_VAR N_PRIVATE_HTTPDDIR \
	N_PUBLIC_HTTPDDIR N_THEMESDIR N_THEMESDIR_VAR N_WEBRADIO_DIR \
	N_WEBRADIO_DIR_VAR N_WEBTV_DIR N_WEBTV_DIR_VAR N_ZAPITDIR \
	N_LCD4L_ICONSDIR N_LCD4L_ICONSDIR_VAR \
	PROGRAM_PREFIX PROGRAM_SUFFIX PROGRAM_TRANSFORM_NAME PROGRAM_NAME

PLUGIN_ENV_ARGS := $(foreach v,$(PLUGIN_ENV_VARS),$(if $($(v)),$(v)="$($(v))",))

include $(PLUGIN_MODULES)

.PHONY: plugins
plugins:
	@if [ ! -f "$(NEUTRINO_INSTALL_STAMP)" ]; then \
		echo "[plugins] Core not built yet – running 'make neutrino'"; \
		$(MAKE) neutrino; \
	fi
	@if [ -d "$(PLUGINS_DIR)" ]; then \
		$(MKDIR_P) "$(PLUGINS_BUILD_DIR)" "$(PLUGINS_INSTALL_DIR)"; \
		echo "[plugins] Building custom plugins"; \
		$(MAKE) -C $(PLUGINS_DIR) \
			$(PLUGIN_ENV_ARGS) \
			PKG_CONFIG_SYSROOT_DIR=$(PLUGIN_PKG_CONFIG_SYSROOT_DIR) \
			PKG_CONFIG_PATH=$(PLUGIN_PKG_CONFIG_PATH) \
			BUILD_DIR=$(PLUGINS_BUILD_DIR) \
			DESTDIR=$(NEUTRINO_INSTALL_DIR) \
			PREFIX=$(NEUTRINO_PREFIX) \
			install; \
	else \
		echo "[plugins] No custom plugin directory detected, skipping"; \
	fi

.PHONY: plugins-clean
plugins-clean:
	@if [ -z "$(strip $(PLUGIN_CLEAN_DEFAULTS))" ]; then \
		echo "[plugins-clean] Keine registrierten Plugins zum Bereinigen."; \
		exit 0; \
	fi
	@echo "[plugins-clean] Removing staged copies for: $(PLUGIN_CLEAN_DEFAULTS)"
	@for p in $(PLUGIN_CLEAN_DEFAULTS); do \
		$(MAKE) CLEAN_PLUGIN_ALLOW_MISSING=1 clean-plugin-$$p; \
	done

.PHONY: list-plugin-targets
list-plugin-targets:
	@echo "[plugin-install] Verfügbare Plugin-Ziele:"
	@for p in $(PLUGIN_INSTALL_NAMES); do echo "  $$p"; done

.PHONY: plugin-install-%
plugin-install-%:
	@name="$*"; \
	canon=""; \
	for pair in $(PLUGIN_INSTALL_ALIAS_PAIRS); do \
		alias="$${pair%%:*}"; \
		candidate="$${pair#*:}"; \
		if [ "$$name" = "$$alias" ]; then \
			canon="$$candidate"; \
			break; \
		fi; \
	done; \
	if [ -z "$$canon" ]; then \
		for n in $(PLUGIN_INSTALL_NAMES); do \
			if [ "$$name" = "$$n" ]; then \
				canon="$$n"; \
				break; \
			fi; \
		done; \
	fi; \
	if [ -z "$$canon" ]; then \
		echo "[plugin-install] Unbekannter Plugin-Name '$$name'."; \
		echo "[plugin-install] Bekannte Namen:"; \
		for p in $(PLUGIN_INSTALL_NAMES); do echo "  $$p"; done; \
		echo "[plugin-install] Tipp: 'make list-plugin-targets' zeigt die Liste."; \
		exit 1; \
	fi; \
	rule=""; \
	for pair in $(PLUGIN_INSTALL_RULES); do \
		candidate="$${pair%%:*}"; \
		target="$${pair#*:}"; \
		if [ "$$candidate" = "$$canon" ]; then \
			rule="$$target"; \
			break; \
		fi; \
	done; \
	if [ -z "$$rule" ]; then \
		echo "[plugin-install] Keine Regel für '$$canon' gefunden."; \
		exit 1; \
	fi; \
	$(MAKE) -C $(PLUGINS_DIR) \
		$(PLUGIN_ENV_ARGS) \
		PKG_CONFIG_SYSROOT_DIR=$(PLUGIN_PKG_CONFIG_SYSROOT_DIR) \
		PKG_CONFIG_PATH=$(PLUGIN_PKG_CONFIG_PATH) \
		DESTDIR=$(NEUTRINO_INSTALL_DIR) \
		PREFIX=$(NEUTRINO_PREFIX) \
		PROGRAM_PREFIX=$(if $(strip $(PLUGIN_PROGRAM_PREFIX)),$(PLUGIN_PROGRAM_PREFIX),$(PROGRAM_PREFIX)) \
		PROGRAM_SUFFIX=$(if $(strip $(PLUGIN_PROGRAM_SUFFIX)),$(PLUGIN_PROGRAM_SUFFIX),$(PROGRAM_SUFFIX)) \
		PROGRAM_TRANSFORM_NAME=$(if $(strip $(PLUGIN_PROGRAM_TRANSFORM_NAME)),$(PLUGIN_PROGRAM_TRANSFORM_NAME),$(PROGRAM_TRANSFORM_NAME)) \
		PROGRAM_NAME=$(if $(strip $(PLUGIN_PROGRAM_NAME)),$(PLUGIN_PROGRAM_NAME),$(PROGRAM_NAME)) \
		$$rule

.PHONY: clean-plugin-%
clean-plugin-%:
	@plugin_raw="$*"; \
	if [ -z "$$plugin_raw" ]; then \
		echo "[clean-plugin] Missing plugin name"; \
		exit 1; \
	fi; \
	canon="$$plugin_raw"; \
	for pair in $(PLUGIN_INSTALL_ALIAS_PAIRS); do \
		alias="$${pair%%:*}"; \
		candidate="$${pair#*:}"; \
		if [ "$$plugin_raw" = "$$alias" ]; then \
			canon="$$candidate"; \
			break; \
		fi; \
	done; \
	for n in $(PLUGIN_INSTALL_NAMES); do \
		if [ "$$canon" = "$$n" ]; then \
			break; \
		fi; \
	done; \
	reserved_plugins="$(PLUGIN_RESERVED_NAMES)"; \
	for r in $$reserved_plugins; do \
		if [ "$$canon" = "$$r" ]; then \
			echo "[clean-plugin] '$$canon' ist reserviert und wird nicht bereinigt."; \
			exit 1; \
		fi; \
	done; \
	found=0; \
	remove_from_dir() { \
		local dir="$$1"; \
		local touched=0; \
		if [ -d "$$dir/$$plugin" ]; then \
			touched=1; \
		fi; \
		if [ -f "$$dir/$$plugin.lua" ] || [ -f "$$dir/$$plugin.cfg" ] || [ -f "$$dir/$${plugin}_hint.png" ]; then \
			touched=1; \
		fi; \
		if [ "$$touched" -eq 1 ]; then \
			found=1; \
			echo "[clean-plugin] Removing $$plugin from $$dir"; \
			rm -rf \
				"$$dir/$$plugin" \
				"$$dir/$$plugin.lua" \
				"$$dir/$$plugin.cfg" \
				"$$dir/$${plugin}_hint.png"; \
		fi; \
	}; \
	for target in \
		"$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/share/tuxbox/neutrino/plugins" \
		"$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/share/tuxbox/neutrino/luaplugins" \
		"$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/share/tuxbox/neutrino/plugins" \
		"$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/share/tuxbox/neutrino/luaplugins" \
		"$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/var/tuxbox/plugins" \
		"$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/var/tuxbox/luaplugins"; do \
		plugin="$$canon"; \
		remove_from_dir "$$target"; \
	done; \
	hook=""; \
	for pair in $(PLUGIN_CLEAN_HOOKS); do \
		candidate="$${pair%%:*}"; \
		target="$${pair#*:}"; \
		if [ "$$candidate" = "$$canon" ]; then \
			hook="$$target"; \
			break; \
		fi; \
	done; \
	if [ -n "$$hook" ]; then \
		$(MAKE) $$hook; \
		found=1; \
	fi; \
	if [ "$$found" -eq 0 ]; then \
		echo "[clean-plugin] Keine Einträge für '$$plugin' gefunden."; \
		echo "[clean-plugin] Tipp: 'make list-cleanable-plugins' zeigt vorhandene Plugins."; \
		if [ "$(CLEAN_PLUGIN_ALLOW_MISSING)" = "1" ]; then \
			exit 0; \
		fi; \
		exit 1; \
	fi

.PHONY: plugin-clean-%
plugin-clean-%: clean-plugin-%
	@:

.PHONY: list-cleanable-plugins
list-cleanable-plugins:
	@paths="\
$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/share/tuxbox/neutrino/plugins \
$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/share/tuxbox/neutrino/luaplugins \
$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/share/tuxbox/neutrino/plugins \
$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/share/tuxbox/neutrino/luaplugins \
$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/var/tuxbox/plugins \
$(NEUTRINO_RUNTIME_PREFIX_ABS)/usr/var/tuxbox/luaplugins"; \
	reserved_plugins="$(PLUGIN_RESERVED_NAMES)"; \
	names=$$( \
		for dir in $$paths; do \
			if [ -d "$$dir" ]; then \
				find "$$dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n'; \
				find "$$dir" -maxdepth 1 -mindepth 1 -type f \( -name '*.lua' -o -name '*.cfg' \) -printf '%f\n' | sed -e 's/\.lua$$//' -e 's/\.cfg$$//'; \
			fi; \
		done | sort -u \
	); \
	if [ -z "$$names" ]; then \
		echo "[list-cleanable-plugins] Keine Plugins in den bekannten Pfaden gefunden."; \
	else \
		echo "[list-cleanable-plugins] Verfügbare Plugin-Namen:"; \
		for n in $$names; do \
			skip=0; \
			for r in $$reserved_plugins; do \
				if [ "$$n" = "$$r" ]; then \
					skip=1; \
					break; \
				fi; \
			done; \
			if [ "$$skip" -eq 1 ]; then \
				continue; \
			fi; \
			printf '  %s\n' "$$n"; \
		done; \
	fi

.PHONY: clean-plugins
clean-plugins: plugins-clean

.PHONY: plugins-distclean
plugins-distclean:
	@$(RM_RF) $(PLUGINS_BUILD_DIR)
	@echo "[plugins-distclean] Skipping source tree cleanup to avoid wiping in-development plugins."

.PHONY: plugin-%
plugin-%:
	@name="$*"; \
	case "$$name" in *make/plugins*) exit 0;; esac; \
	# strip accidental path components to avoid double prefixes
	name="$${name##*/}"; \
	if [ "$$name" = "neutrino-mediathek" ] && [ ! -d "$(PLUGINS_DIR)/$$name" ]; then \
		$(MKDIR_P) "$(PLUGINS_BUILD_DIR)" "$(PLUGINS_INSTALL_DIR)"; \
		echo "[plugins] Building $$name via plugins/Makefile (sources at $(ROOT_DIR)/sources/neutrino-mediathek)"; \
		$(MAKE) -C $(PLUGINS_DIR) \
			$(PLUGIN_ENV_ARGS) \
			PKG_CONFIG_SYSROOT_DIR=$(PLUGIN_PKG_CONFIG_SYSROOT_DIR) \
			PKG_CONFIG_PATH=$(PLUGIN_PKG_CONFIG_PATH) \
			DESTDIR=$(NEUTRINO_INSTALL_DIR) \
			PREFIX=$(NEUTRINO_PREFIX) \
			PROGRAM_PREFIX=$(if $(strip $(PLUGIN_PROGRAM_PREFIX)),$(PLUGIN_PROGRAM_PREFIX),$(PROGRAM_PREFIX)) \
			PROGRAM_SUFFIX=$(if $(strip $(PLUGIN_PROGRAM_SUFFIX)),$(PLUGIN_PROGRAM_SUFFIX),$(PROGRAM_SUFFIX)) \
			PROGRAM_TRANSFORM_NAME=$(if $(strip $(PLUGIN_PROGRAM_TRANSFORM_NAME)),$(PLUGIN_PROGRAM_TRANSFORM_NAME),$(PROGRAM_TRANSFORM_NAME)) \
			PROGRAM_NAME=$(if $(strip $(PLUGIN_PROGRAM_NAME)),$(PLUGIN_PROGRAM_NAME),$(PROGRAM_NAME)) \
			neutrino-mediathek-install; \
		exit $$?; \
	fi; \
	if [ ! -d "$(PLUGINS_DIR)/$$name" ]; then \
		echo "[plugins] Directory '$(PLUGINS_DIR)/$$name' not found"; \
		exit 1; \
	fi; \
	$(MKDIR_P) "$(PLUGINS_BUILD_DIR)" "$(PLUGINS_INSTALL_DIR)"; \
	echo "[plugins] Building $$name"; \
	$(MAKE) -C $(PLUGINS_DIR)/$$name \
		$(PLUGIN_ENV_ARGS) \
		PKG_CONFIG_SYSROOT_DIR=$(PLUGIN_PKG_CONFIG_SYSROOT_DIR) \
		PKG_CONFIG_PATH=$(PLUGIN_PKG_CONFIG_PATH) \
		DESTDIR=$(NEUTRINO_INSTALL_DIR) \
		PREFIX=$(NEUTRINO_PREFIX) \
		PROGRAM_PREFIX=$(if $(strip $(PLUGIN_PROGRAM_PREFIX)),$(PLUGIN_PROGRAM_PREFIX),$(PROGRAM_PREFIX)) \
		PROGRAM_SUFFIX=$(if $(strip $(PLUGIN_PROGRAM_SUFFIX)),$(PLUGIN_PROGRAM_SUFFIX),$(PROGRAM_SUFFIX)) \
		PROGRAM_TRANSFORM_NAME=$(if $(strip $(PLUGIN_PROGRAM_TRANSFORM_NAME)),$(PLUGIN_PROGRAM_TRANSFORM_NAME),$(PROGRAM_TRANSFORM_NAME)) \
		PROGRAM_NAME=$(if $(strip $(PLUGIN_PROGRAM_NAME)),$(PLUGIN_PROGRAM_NAME),$(PROGRAM_NAME)) \
		install
