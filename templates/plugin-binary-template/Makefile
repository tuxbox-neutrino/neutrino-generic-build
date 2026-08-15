# Makefile for Neutrino Native Binary Plugin
# This builds a shared library (.so) loaded by Neutrino

PLUGIN_NAME = my-binary-plugin

# Compiler settings (can be overridden by neutrino-make)
CC ?= gcc
CXX ?= g++
PKG_CONFIG ?= pkg-config

# Directories
PREFIX ?= /usr
DESTDIR ?=

# Compiler flags
CXXFLAGS += -fPIC -Wall -Wextra -std=c++11
CXXFLAGS += -O2 -g

# Try to use pkg-config for neutrino (adjust as needed)
# If pkg-config doesn't work, set paths manually
NEUTRINO_CFLAGS := $(shell $(PKG_CONFIG) --cflags neutrino 2>/dev/null || echo "-I$(PREFIX)/include")
NEUTRINO_LIBS := $(shell $(PKG_CONFIG) --libs neutrino 2>/dev/null || echo "")

CXXFLAGS += $(NEUTRINO_CFLAGS)

# Linker flags
LDFLAGS += -shared
LDFLAGS += $(NEUTRINO_LIBS)

# Source files
SOURCES = $(PLUGIN_NAME).cpp
OBJECTS = $(SOURCES:.cpp=.o)
TARGET = $(PLUGIN_NAME).so

# Build rules
.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJECTS)
	@echo "  [LD]  $@"
	@$(CXX) $(LDFLAGS) -o $@ $^

%.o: %.cpp
	@echo "  [CXX] $<"
	@$(CXX) $(CXXFLAGS) -c -o $@ $<

install: $(TARGET)
	@echo "  [INSTALL] $(TARGET) -> $(DESTDIR)$(PREFIX)/lib/tuxbox/neutrino/plugins/"
	@install -D -m 755 $(TARGET) $(DESTDIR)$(PREFIX)/lib/tuxbox/neutrino/plugins/$(TARGET)

clean:
	@echo "  [CLEAN]"
	@rm -f $(OBJECTS) $(TARGET)

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build plugin (default)"
	@echo "  install  - Install plugin to $(PREFIX)/lib/tuxbox/neutrino/plugins/"
	@echo "  clean    - Remove build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX   - Installation prefix (default: /usr)"
	@echo "  DESTDIR  - Staging directory (default: empty)"
	@echo "  CC       - C compiler"
	@echo "  CXX      - C++ compiler"
