# Licensing

This repository is distributed under the **GNU General Public License, version 2
or (at your option) any later version** (`GPL-2.0-or-later`). The full text is in
[`../LICENSE`](../LICENSE).

That choice follows the software this build system exists to build: `COPYING` in
both [neutrino](https://github.com/tuxbox-neutrino/neutrino) and
[libstb-hal](https://github.com/tuxbox-neutrino/libstb-hal) is GPL version 2, and
their source headers grant the "or any later version" option.

## What is covered

Everything in this repository: the `Makefile`, the modules under `make/`, the
shell scripts under `scripts/`, the tests under `tests/`, plus `templates/`,
`files/`, `skel-root/`, `.github/` and the documentation under `docs/`.

That is the whole of it. This repository contains no third-party source code.

## What is *not* covered

Neutrino, libstb-hal, FFmpeg, LuaJIT, libdvbsi++, the shared Lua helper libraries
and every plugin are **not** part of this repository. The build fetches each of
them from its own upstream repository at the moment it is asked to build it, into
`sources/` — a directory that is deliberately not tracked here.

Each of those projects carries its own license in its own source tree, and that
license is what governs it. Nothing in this repository relicenses them, and
building them locally does not change their terms.

If you redistribute a *result* of this build — an AppImage, a Debian package, a
static bundle — you are redistributing those projects too, and their licenses
apply to what you ship. That is the usual GPL obligation: pass on the source, or
a written offer for it, along with the binaries.
