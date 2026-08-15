# Lua plugin packaging helpers.

LUA_SRC_DIR ?= $(ROOT_DIR)/lua
LUA_INSTALL_DIR ?= $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/share/neutrino/lua

.PHONY: lua
lua: $(NEUTRINO_INSTALL_STAMP)
	@if [ -d "$(LUA_SRC_DIR)" ]; then \
		echo "[lua] Installing Lua scripts into $(LUA_INSTALL_DIR)"; \
		$(MKDIR_P) "$(LUA_INSTALL_DIR)"; \
		cp -a "$(LUA_SRC_DIR)/." "$(LUA_INSTALL_DIR)/"; \
	else \
		echo "[lua] No Lua sources detected, skipping"; \
	fi

.PHONY: lua-clean
lua-clean:
	@true

.PHONY: lua-distclean
lua-distclean:
	@true
