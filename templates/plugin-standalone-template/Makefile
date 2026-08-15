# Simple Makefile for Standalone Plugin Tool
# For more complex projects, consider using autotools or cmake

TOOL_NAME = my-tool

# Compiler settings
CC ?= gcc
PKG_CONFIG ?= pkg-config

# Directories
PREFIX ?= /usr
DESTDIR ?=
BINDIR = $(PREFIX)/bin
DATADIR = $(PREFIX)/share/tuxbox/neutrino/luaplugins/$(TOOL_NAME)

# Compiler flags
CFLAGS += -Wall -Wextra -std=c11
CFLAGS += -O2 -g

# Linker flags
LDFLAGS +=

# Source files
SOURCES = $(TOOL_NAME).c
OBJECTS = $(SOURCES:.c=.o)
TARGET = $(TOOL_NAME)

# Build rules
.PHONY: all clean install uninstall

all: $(TARGET)

$(TARGET): $(OBJECTS)
	@echo "  [LD]  $@"
	@$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	@echo "  [CC]  $<"
	@$(CC) $(CFLAGS) -c -o $@ $<

install: $(TARGET)
	@echo "  [INSTALL] $(TARGET) -> $(DESTDIR)$(BINDIR)/"
	@install -D -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)
	@if [ -d data ]; then \
		echo "  [INSTALL] data/ -> $(DESTDIR)$(DATADIR)/"; \
		install -d $(DESTDIR)$(DATADIR); \
		cp -r data/* $(DESTDIR)$(DATADIR)/; \
	fi

uninstall:
	@echo "  [UNINSTALL] $(DESTDIR)$(BINDIR)/$(TARGET)"
	@rm -f $(DESTDIR)$(BINDIR)/$(TARGET)
	@echo "  [UNINSTALL] $(DESTDIR)$(DATADIR)/"
	@rm -rf $(DESTDIR)$(DATADIR)

clean:
	@echo "  [CLEAN]"
	@rm -f $(OBJECTS) $(TARGET)

# Help target
help:
	@echo "Available targets:"
	@echo "  all       - Build tool (default)"
	@echo "  install   - Install tool to $(PREFIX)/bin/"
	@echo "  uninstall - Remove tool from $(PREFIX)/bin/"
	@echo "  clean     - Remove build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX    - Installation prefix (default: /usr)"
	@echo "  DESTDIR   - Staging directory (default: empty)"
	@echo "  CC        - C compiler"
	@echo "  CFLAGS    - C compiler flags"
	@echo "  LDFLAGS   - Linker flags"
