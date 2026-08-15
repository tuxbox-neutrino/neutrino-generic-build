# Plugins bauen und installieren

Der Generic-PC-Build baut Plugins **nicht selbst**. Er besorgt die Quellen und
ruft dann das Makefile des jeweiligen Plugin-Repositories auf. Dieses Dokument
beschreibt diesen Vertrag und wie man ihn nutzt.

*English: this build delegates building and installing to each plugin
repository. The contract is the `install` target described below.*

## Kurzfassung

```bash
make plugins
```

Das genügt. Fehlende Plugin-Quellen werden automatisch über HTTPS geklont; ein
vorheriger `make neutrino`-Lauf wird bei Bedarf selbst angestoßen.

## Welche Plugins kennt der Build?

```bash
make list-plugin-targets      # Namen für plugin-install-<name>
make plugin-install-<name>    # ein einzelnes Plugin
```

| Plugin | Quelle | Status |
| --- | --- | --- |
| `neutrino-mediathek` | `tuxbox-neutrino/plugin-lua-neutrino-mediathek` | wird gebaut |
| `logoupdater` | `tuxbox-neutrino/plugin-lua-logoupdater` | wird gebaut |
| `FritzInfoMonitor` | — | auf dem PC bewusst übersprungen (braucht Framebuffer- und RC-Gerät der Box) |
| `FritzCallMonitor` | `tuxbox-neutrino/FritzCallMonitor` | wird gebaut |
| `tuxwetter` | `tuxbox-neutrino/plugin-tuxwetter` | wird gebaut |

## Pflicht- und optionale Plugins

Ein einzelnes defektes Plugin bricht den Lauf **nicht** ab. Am Ende steht eine
Übersicht, und nur ein Fehlschlag in `PLUGINS_REQUIRED` lässt `make plugins`
mit einem Fehlerstatus enden:

Standardmäßig sind `neutrino-mediathek`, `logoupdater`, `fritzcall` und
`tuxwetter` Pflicht; `fritzinfo` ist optional (box-only, auf dem PC bewusst
übersprungen). Die Liste lässt sich überschreiben:

```make
# Makefile.local
PLUGINS_REQUIRED := neutrino-mediathek logoupdater
```

Einmalig geht es auch direkt:

```bash
make plugins PLUGINS_REQUIRED="neutrino-mediathek logoupdater"
```

## Der Vertrag zwischen Build und Plugin-Repository

Jedes Plugin-Repository muss ein **`Makefile` mit einem `install`-Target**
mitbringen. Der Build übergibt:

| Variable | Bedeutung |
| --- | --- |
| `DESTDIR` | Staging-Wurzel (Sysroot) |
| `PREFIX` | Präfix darin, für Lua-Plugins `<prefix>/share/tuxbox/neutrino` |
| `PLUGIN_SUBDIR` | Unterverzeichnis für klassische Plugins, i. d. R. `plugins` |
| `LUAPLUGIN_SUBDIR` | Unterverzeichnis für Lua-Plugins, i. d. R. `luaplugins` |
| `CC`, `CXX`, `PKG_CONFIG`, `CPPFLAGS`, `CXXFLAGS`, `LDFLAGS` | Toolchain für native Plugins |

Erfüllt ein Repository den Vertrag nicht, meldet der Build das ausdrücklich und
nennt Repository, erwartete Datei und den Ausweg über `<PLUGIN>_GIT_REF`.

## Installationspfade

Maßgeblich sind — mit `tuxbox/`-Segment:

```
$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/plugins
$(DESTDIR)$(PREFIX)/share/tuxbox/neutrino/luaplugins
$(DESTDIR)$(PREFIX)/lib/tuxbox/neutrino/plugins
```

Nach `make runtime-sync` liegen sie zusätzlich unter `root/usr/...` und sind
damit für `make run` sichtbar.

## Nützliche Variablen

| Variable | Standard | Zweck |
| --- | --- | --- |
| `PLUGINS_DIR` | `./plugins` | Verzeichnis mit eigenen Plugin-Unterprojekten |
| `PLUGINS_REQUIRED` | `neutrino-mediathek logoupdater fritzcall tuxwetter` | Plugins, deren Fehlschlag den Build scheitern lässt |
| `NEUTRINO_MEDIATHEK_GIT_URL` / `_GIT_REF` | öffentliche URL / leer | Quelle des Mediathek-Plugins |
| `LOGOUPDATER_GIT_URL` / `_GIT_REF` | öffentliche URL / leer | Quelle des Logoupdaters |
| `FCM_GIT_URL` / `_GIT_REF` | öffentliche URL / leer | Quelle des FritzCallMonitors |
| `TUXWETTER_GIT_URL` / `_GIT_REF` | öffentliche URL / leer | Quelle des Tuxwetter-Plugins |
| `NEUTRINO_MEDIATHEK_SRC` | `./sources/neutrino-mediathek` | vorhandene Quelle statt Clone verwenden |
| `PLUGIN_SCRIPTS_LUA_GIT_URL` / `_GIT_REF` | öffentliche URL / leer | Quelle der gemeinsamen Lua-Helfer (json, feedparser, n_gui, n_helpers) |
| `NEUTRINO_LUA_HELPERS_SRC` | `./sources/plugin-scripts-lua/share/lua` | vorhandenes Helfer-Verzeichnis (mit `5.x/`) statt Clone verwenden |

Aufräumen:

```bash
make list-cleanable-plugins
make clean-plugin-<name>
make clean-plugins
```

## Einen anderen Plugin-Branch bauen

`FritzCallMonitor` und `tuxwetter` liefern das oben beschriebene `Makefile` auf
ihrem Standard-Branch (`master`); beide werden gebaut und stehen in
`PLUGINS_REQUIRED`. Wer stattdessen einen anderen Branch bauen will, setzt den
passenden `*_GIT_REF`:

```bash
make plugins TUXWETTER_GIT_REF=<branch> FCM_GIT_REF=<branch>
```

## Ein eigenes Plugin ergänzen

Siehe [HOWTO_ADD_PLUGIN.de.md](HOWTO_ADD_PLUGIN.de.md).
