# Packaging helpers for AppImage, Debian packages, and static bundles.

APPIMAGE_OUTPUT_DIR ?= $(OUTPUT_DIR)/appimage
DEB_OUTPUT_DIR ?= $(OUTPUT_DIR)/deb
STATIC_OUTPUT_DIR ?= $(OUTPUT_DIR)/static

# Neutrino learns its data directories at configure time: acinclude.m4 turns
# every --with-*dir into a string literal in config.h, so the path a build was
# configured with is the only path the binary will ever look at. A package built
# straight from the developer tree therefore searches for its icons, locales and
# webroot underneath the builder's home directory, and "make install" drops the
# 12 MB of data that belongs to them outside the packaged usr/ tree entirely.
#
# The AppImage variant is consequently a second Neutrino build, configured
# against a neutral prefix that AppRun maps back at runtime. It gets its own
# build and staging directories so that it can never overwrite the developer's
# binary: that binary would afterwards look for /opt/neutrino, and "make run"
# would come up without a user interface and no obvious reason why.
#
# Only Neutrino itself depends on this prefix. libstb-hal, libdvbsi++, ffmpeg
# and lua are configured with --prefix=/usr and staged through DESTDIR, so the
# variant seeds its sysroot from the shared one rather than rebuilding them.
APPIMAGE_RUNTIME_PREFIX ?= /opt/neutrino
APPIMAGE_BUILD_DIR ?= $(BUILD_DIR)/neutrino-appimage
APPIMAGE_SYSROOT ?= $(OUTPUT_DIR)/sysroot-appimage

# assert() and a few debug macros embed __FILE__, which is an absolute path in
# an out-of-tree build. Without this the published binary would carry the
# directory the maintainer happened to build in. It goes through CPPFLAGS and
# not CXXFLAGS on purpose: configure copies CXXFLAGS into USED_CXXFLAGS, so the
# flag would reintroduce through that string exactly the path it removes.
APPIMAGE_PREFIX_MAP ?= -ffile-prefix-map=$(ROOT_DIR)=.

.PHONY: package-appimage-stage
# The dependency stamps live under BUILD_DIR, which this target does not
# override, while NEUTRINO_INSTALL_DIR is overridden. A dependency that happens
# to be out of date would therefore be built by the packaging sub-make, land in
# the packaging sysroot, and mark the shared stamp done -- so the developer's
# sysroot would never receive it. Building the ordinary tree first means the
# stamps are always consumed where they belong.
package-appimage-stage: neutrino
	@if [ ! -d "$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/lib" ]; then \
		echo "[package] No staged dependencies in $(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX). Run 'make neutrino' first."; \
		exit 1; \
	fi
	@echo "[package] Seeding $(APPIMAGE_SYSROOT) from the shared dependency staging"
	@$(MKDIR_P) "$(APPIMAGE_SYSROOT)$(NEUTRINO_PREFIX)"
	@# Dependency artefacts only. bin/ is deliberately not seeded: it holds
	@# Neutrino's own binary, so copying it here would put the developer build --
	@# the one that looks for its data under the builder's home directory --
	@# straight into the package, and the install stamp below would happily leave
	@# it there. It also holds ~14 MB of ffmpeg and luajit command line tools that
	@# Neutrino only ever uses as libraries.
	@# --delete so a library dropped from the shared staging does not live on
	@# here and keep being packaged. share/tuxbox is excluded: that is Neutrino's
	@# own data and plugin tree, which the variant installs itself below its
	@# prefix. Seeding it would put the developer's locally built plugins into
	@# the package, complete with the paths they were built against.
	@for part in include lib share; do \
		src="$(NEUTRINO_INSTALL_DIR)$(NEUTRINO_PREFIX)/$$part"; \
		[ -d "$$src" ] || continue; \
		rsync -a --no-owner --no-group --delete --exclude='/tuxbox/' \
			"$$src/" "$(APPIMAGE_SYSROOT)$(NEUTRINO_PREFIX)/$$part/" \
			|| { echo "[package] ERROR: seeding $$part into $(APPIMAGE_SYSROOT) failed"; exit 1; }; \
	done
	@# The prefix is baked in at configure time, but the configure stamp only
	@# tracks sources -- so changing APPIMAGE_RUNTIME_PREFIX after a successful
	@# build would reinstall a binary still carrying the old prefix. Compare what
	@# the variant was actually configured with, the same way runtime-sync does
	@# for the developer build, and start over when it no longer matches.
	@config_header="$(APPIMAGE_BUILD_DIR)/config.h"; \
	expected="$(APPIMAGE_RUNTIME_PREFIX)/usr/share/tuxbox"; \
	if [ -f "$$config_header" ]; then \
		actual="$$(grep '^#define DATADIR ' "$$config_header" | awk '{print $$3}' | tr -d '"')"; \
		if [ -n "$$actual" ] && [ "$$actual" != "$$expected" ]; then \
			echo "[package] Configured for '$$actual', now building for '$$expected' -- rebuilding."; \
			$(RM_RF) "$(APPIMAGE_BUILD_DIR)" "$(APPIMAGE_SYSROOT)$(APPIMAGE_RUNTIME_PREFIX)"; \
		fi; \
	fi
	@# The install step is stamped against the build directory, not against the
	@# staging tree. Without dropping the stamp, a re-seeded or wiped sysroot
	@# would keep whatever it happens to contain and never get the variant's own
	@# binary and tools back.
	@rm -f "$(APPIMAGE_BUILD_DIR)/.installed"
	@echo "[package] Rebuilding Neutrino against $(APPIMAGE_RUNTIME_PREFIX)"
	@$(MAKE) neutrino \
		NEUTRINO_BUILD_DIR="$(APPIMAGE_BUILD_DIR)" \
		NEUTRINO_INSTALL_DIR="$(APPIMAGE_SYSROOT)" \
		NEUTRINO_RUNTIME_PREFIX="$(APPIMAGE_RUNTIME_PREFIX)" \
		NEUTRINO_STAGE_RUNTIME=0 \
		NEUTRINO_CPPFLAGS_APPEND="$(NEUTRINO_CPPFLAGS_APPEND) $(APPIMAGE_PREFIX_MAP)"

.PHONY: package-appimage-build
package-appimage-build: package-appimage-stage
	@$(MKDIR_P) $(APPIMAGE_OUTPUT_DIR)
	@APPIMAGE_TOOL_PATH="$$(./scripts/ensure_appimagetool.sh tool)"; \
	if [ -z "$${APPIMAGE_TOOL_PATH}" ]; then \
		echo "[package] Failed to provision appimagetool."; \
		exit 1; \
	fi; \
	APPIMAGE_RUNTIME_PATH="$$(./scripts/ensure_appimagetool.sh runtime)"; \
	if [ -z "$${APPIMAGE_RUNTIME_PATH}" ]; then \
		echo "[package] Failed to provision the AppImage runtime."; \
		exit 1; \
	fi; \
	APPIMAGE_DEPLOY_PATH="$$(./scripts/ensure_appimagetool.sh deploy)"; \
	if [ -z "$${APPIMAGE_DEPLOY_PATH}" ]; then \
		echo "[package] Failed to provision linuxdeploy."; \
		exit 1; \
	fi; \
	echo "[package] Generating AppImage"; \
	NEUTRINO_INSTALL_DIR=$(APPIMAGE_SYSROOT) \
		NEUTRINO_APPIMAGE_PREFIX=$(APPIMAGE_RUNTIME_PREFIX) \
		APPIMAGE_OUTPUT_DIR=$(APPIMAGE_OUTPUT_DIR) \
		APPIMAGE_TOOL="$${APPIMAGE_TOOL_PATH}" \
		APPIMAGE_RUNTIME_FILE="$${APPIMAGE_RUNTIME_PATH}" \
		APPIMAGE_DEPLOY_TOOL="$${APPIMAGE_DEPLOY_PATH}" \
		./scripts/gen_appimage.sh

.PHONY: package-appimage-verify
# Refuses a package older than the scripts that build it. Without this the
# target happily reports "all checks passed" for an artefact built before the
# change under test -- and this is the target whose whole purpose is to be
# believed.
#
# verify_appimage.sh is deliberately not in that list: it judges the package,
# it does not shape it. Demanding a rebuild after every change to the gate would
# mean a full repackage just to re-ask the question, and a newer gate over an
# unchanged artefact is the case one actually wants.
package-appimage-verify:
	@img="$$(ls -1t $(APPIMAGE_OUTPUT_DIR)/*.AppImage 2>/dev/null | sed -n 1p)"; \
	if [ -z "$$img" ]; then \
		echo "[package] No AppImage found. Run 'make package-appimage' first."; \
		exit 1; \
	fi; \
	for src in scripts/gen_appimage.sh scripts/ensure_appimagetool.sh make/package.mk; do \
		if [ "$$src" -nt "$$img" ]; then \
			echo "[package] $$img is older than $$src."; \
			echo "[package] Re-run 'make package-appimage'; verifying a stale package proves nothing."; \
			exit 1; \
		fi; \
	done; \
	APPIMAGE_OUTPUT_DIR=$(APPIMAGE_OUTPUT_DIR) \
		NEUTRINO_APPIMAGE_PREFIX=$(APPIMAGE_RUNTIME_PREFIX) \
		./scripts/verify_appimage.sh

.PHONY: package-deb-build
package-deb-build:
	@$(MKDIR_P) $(DEB_OUTPUT_DIR)
	@echo "[package] Generating Debian package"
	@NEUTRINO_INSTALL_DIR=$(NEUTRINO_INSTALL_DIR) \
		DEB_OUTPUT_DIR=$(DEB_OUTPUT_DIR) \
		./scripts/make_deb.sh

.PHONY: package-static-build
package-static-build:
	@$(MKDIR_P) $(STATIC_OUTPUT_DIR)
	@echo "[package] Generating static tarball"
	@NEUTRINO_INSTALL_DIR_STATIC=$(NEUTRINO_INSTALL_DIR_STATIC) \
		STATIC_OUTPUT_DIR=$(STATIC_OUTPUT_DIR) \
		./scripts/static_link.sh

.PHONY: package-clean
package-clean:
	@# Intermediates only. "make clean" calls this, and a finished AppImage, deb
	@# or tarball is a result, not an intermediate -- deleting those from under
	@# someone who just built a release would be a nasty surprise. Use
	@# "make package-distclean" for that.
	@$(RM_RF) $(APPIMAGE_BUILD_DIR) $(APPIMAGE_SYSROOT)

.PHONY: package-distclean
package-distclean: package-clean ## Also remove the finished packages
	@$(RM_RF) $(APPIMAGE_OUTPUT_DIR) $(DEB_OUTPUT_DIR) $(STATIC_OUTPUT_DIR)
