# Contributing

Danke für Ihren Beitrag / Thank you for contributing!

1. **Branching**: Use feature branches based on `master` and open PRs against
   `master`. Do not force-push shared branches. `master` is the only long-lived
   branch: it is the repository default, and it carries the build system itself.
   See `SECURITY.md` for the branch model.
2. **Commits**: Subject format is `<type> (<scope>): <summary>` — note the space
   **before** the parenthesis, e.g. `fix (deps): pin the luajit source ref`.
   Type is lowercase and one of `feat`, `fix`, `refactor`, `docs`, `build`, `ci`,
   `test`, `chore`; the scope names the touched area (`make`, `toolchain`, `deps`,
   `plugins`, `yweb`, `package`, `shell`, `readme`, …). A type without a scope
   (`docs: fix a typo`) is fine, a scope without a type is not. Imperative mood,
   no trailing period, subject ≤ 72 characters. Anything beyond a one-line
   correction needs a body: one blank line after the subject, wrapped at 72
   characters, saying **why** before **what**.
   **Commit messages are English**, subject and body — the surrounding Tuxbox
   history is uniformly English. German is welcome in issues and pull request
   discussions.
3. **Testing**: Run `make test` (plus relevant `package-*` targets) before submitting PRs. Provide notes on root usage in the PR description.
4. **CI**: GitHub Actions gates every push and pull request to `master` with the shell unit tests and the dependency preflight on Debian 12/13, Fedora 41, and Ubuntu 22.04/24.04. A full source build (Debian 12, Fedora 41, and Ubuntu 24.04) additionally runs for release tags.
   The AppImage is built on demand through `workflow_dispatch` — from the
   Actions tab or `gh workflow run CI` — because it takes over an hour and is
   not wanted on every push. There is deliberately no nightly build; one worth
   having would watch the Neutrino and libstb-hal sources rather than the clock.
   Run `make test` locally as well and state the result in the pull request.
5. **Code style**: Prefer portable POSIX shell, C/C++ code follows upstream Neutrino guidelines, Python uses `black` defaults.
6. **Documentation**: Update the German *and* English docs when user-facing behaviour changes.

Security issues? See `SECURITY.md`.
