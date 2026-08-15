# Neutrino Generic Build

Build [Neutrino](https://github.com/tuxbox-neutrino/gui-neutrino) — the open-source
TV interface of the Tuxbox set-top boxes — **on an ordinary x86_64 Linux PC**, so
you can develop, test and look at it without owning a receiver.

A DVB tuner is optional. Without one, Neutrino starts in simulation mode and
everything except live TV works.

## → The build system lives on the [`dx`](../../tree/dx) branch

```bash
git clone -b dx https://github.com/tuxbox-neutrino/neutrino-generic-build.git
cd neutrino-generic-build
make deps-doctor      # check the host, changes nothing
                      # then run the install command it prints
make bootstrap        # build Neutrino (long on the first run)
make run              # start it
```

Full documentation, in English and German, is on that branch:

- **[README](../../blob/dx/README.md)** — what this is and what you need
- **[Quickstart](../../blob/dx/docs/QUICKSTART.en.md)** ([Schnellstart](../../blob/dx/docs/QUICKSTART.de.md)) — clone → build → run
- **[Project overview](../../blob/dx/docs/README.en.md)** ([Projektüberblick](../../blob/dx/docs/README.de.md)) — prerequisites, build layout, disk and time
- **[Testing](../../blob/dx/docs/TESTING.en.md)** · **[Packaging](../../blob/dx/docs/PACKAGING.en.md)** · **[Hardware notes](../../blob/dx/docs/HARDWARE.en.md)**
- **[Contributing](../../blob/dx/CONTRIBUTING.md)** — branch model, commit format, CI

Issues and pull requests belong here in this repository; pull requests target
`dx`.

## Why this branch looks empty

`master` is the repository default, which is why you are reading it — but the
work is on `dx`. What `master` still carries is the original standalone
`Makefile` from 2012–2017, kept for reference. It predates this build system and
is not maintained.

If you came here looking for the build, follow the link above.
