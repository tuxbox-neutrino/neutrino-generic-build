# Security Policy

## Supported branches

- `master`: The only long-lived branch, and the repository default. All work,
  all pull requests and all security fixes land here, and it is the branch this
  documentation describes.

Builds are published as GitHub releases by a `workflow_dispatch` on `master`;
no other event publishes anything. `latest` is rolling and is replaced by every
such run, so it carries no fix guarantee. Its AppImage filename names the
Neutrino commit inside, which is what a report about Neutrino needs; the build
system and libstb-hal commits are not in that name. If the problem is in the
packaging, report against an archived `build/…` release instead — its tag
carries all three. Archived releases stay put but are snapshots, not supported
versions.

There are no *tagged* releases yet, so there is nothing to back-port to. Once
they exist, back-ports will be agreed case by case.

## Reporting a vulnerability

1. Do not create public issues.
2. Report to developers@tuxbox-neutrino.org with:
   - Brief subject line with component/impact,
   - Reproduction steps, affected commit/tag, and host OS,
   - Which run target was used (`run`, `run-direct`, `run-nspawn`, `run-local`, `run-now`, `run-gdb`, `run-valgrind`, …) and whether sanitizers were active.
   - Used GCC version (`TOOLCHAIN_GCC_VERSION`)
3. Please allow up to 14 days for initial triage. We will coordinate disclosure/release directly with you.

## Runtime considerations

### Isolation levels

neutrino-make offers different isolation levels:

- **`make run` / `make run-direct`** (host wrapper, default):
  - No isolation, direct start on host
  - Uses `LD_LIBRARY_PATH` for GCC runtime (from `artifacts/toolchains/gcc-*`)
  - Sets `SIMULATE_FE=1` for tuner-less operation
  - Fastest option for development, lowest isolation

- **`make run-nspawn`** (systemd-nspawn/proot):
  - Clean isolation via systemd-nspawn or proot (if available)
  - Requires sudo or proot
  - Falls back to host wrapper if proot is missing

- **`make run-local`** (local systemd-nspawn):
  - Local systemd-nspawn container
  - Requires sudo
  - Script: `./scripts/run_neutrino_local.sh`

- **`ALLOW_NON_ROOT=1 make run-now`** (proot):
  - proot sandbox without root privileges
  - Falls back to host wrapper if proot is missing

### Security best practices

- **Check before root usage**: Review wrappers/scripts before using sudo
- **Prefer isolation**: Use `run-nspawn` or `run-local` for testing with untrusted code
- **Avoid production systems**: Do not test on production systems
- **Runtime sync**: `make runtime-sync` is automatically called by run targets
- **GCC toolchains**: Self-built GCC toolchains are stored under `artifacts/toolchains/` and included via `LD_LIBRARY_PATH`
- **Build artifacts**: `make distclean` removes all artifacts including self-built GCC toolchains; `make distclean-keep-toolchains` preserves toolchains
