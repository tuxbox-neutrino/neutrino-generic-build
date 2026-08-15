# Contributing

Danke für Ihren Beitrag / Thank you for contributing!

1. **Branching**: Use feature branches based on `dx` and open PRs against `dx`. Do not force-push shared branches.
   `dx` is the development branch even though `master` is the repository default —
   `master` only carries the landing page and the historical standalone Makefile.
   See `SECURITY.md` for the full branch model.
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
4. **CI**: GitHub Actions gates every push and pull request to `dx` with the shell unit tests and the dependency preflight on Debian 12/13, Fedora 41, and Ubuntu 22.04/24.04. A full source build (Debian 12, Fedora 41, and Ubuntu 24.04) additionally runs for release tags.
   The workflow also declares a nightly `schedule` and `workflow_dispatch`, but
   neither can fire while the workflow file lives on `dx`: GitHub triggers both
   only from the default branch. Moving the workflow to `master` is part of the
   release-pipeline work and has not landed yet.
   Run `make test` locally as well and state the result in the pull request.
5. **Code style**: Prefer portable POSIX shell, C/C++ code follows upstream Neutrino guidelines, Python uses `black` defaults.
6. **Documentation**: Update the German *and* English docs when user-facing behaviour changes.

Security issues? See `SECURITY.md`.
