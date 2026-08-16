# Packaging

## Schnellnavigation

- [Projektüberblick](README.de.md)
- [Schnellstart](QUICKSTART.de.md)
- [Test-Handbuch](TESTING.de.md)
- [Paketierungsleitfaden](PACKAGING.de.md) *(diese Seite)*
- [Hardware-Hinweise](HARDWARE.de.md)
- Need English? Switch to [PACKAGING.en.md](PACKAGING.en.md)

Diese Umgebung unterstützt drei Paketarten:

1. **AppImage (`make package-appimage`)**
   - Baut Neutrino ein zweites Mal und packt es zusammen mit seinen Daten.
   - Läuft ohne Root. Root wird für DVB- und Input-Geräte gebraucht — und für die
     Weboberfläche: sie ist auf Port 80 konfiguriert, den ein unprivilegierter
     Prozess nicht binden darf. Ohne Root weicht Neutrino auf 8080 aus und gibt
     auf, wenn auch der belegt ist; `WebsiteMain.port` in der benutzereigenen
     `nhttpd.conf` lässt sich nach dem ersten Start frei setzen.
   - Ergebnis mit `make package-appimage-verify` prüfen (siehe unten).

   **Warum ein zweiter Build.** Neutrino erfährt seine Datenverzeichnisse beim
   `configure`: `acinclude.m4` macht aus jedem `--with-*dir` ein String-Literal
   in der `config.h`. Der Pfad, gegen den gebaut wurde, ist damit der einzige,
   den das Binary jemals ansieht. Ein Paket aus dem Entwicklerbaum sucht seine
   Icons, Locales und den Webroot deshalb unterhalb des Verzeichnisses, in dem
   *du* gebaut hast — und das gibt es auf keinem anderen Rechner.

   Der AppImage-Build wird darum gegen einen neutralen Prefix konfiguriert
   (`/opt/neutrino`, änderbar über `APPIMAGE_RUNTIME_PREFIX`) und bekommt
   eigene Build- und Staging-Verzeichnisse. So kann er das Binary, das dein
   `make run` benutzt, nicht überschreiben. Abhängigkeiten, die von diesem
   Prefix nicht betroffen sind — libstb-hal, libdvbsi++, ffmpeg, lua — werden
   aus `artifacts/sysroot` übernommen statt neu gebaut.

   **Wie die Daten zur Laufzeit gefunden werden.** Das erzeugte `AppRun` blendet
   den mitgelieferten Baum in einem privaten Mount-Namespace auf
   `/opt/neutrino` ein. Auf dem Dateisystem wird nichts angelegt, und die
   Einblendung verschwindet mit dem Prozess. Zwei Mounts, weil Neutrino
   unterhalb desselben Prefix auch schreibt:

   | | Quelle | eingeblendet auf | Modus |
   |---|---|---|---|
   | Daten | das AppImage | `/opt/neutrino` als Ganzes | nur lesbar |
   | Zustand | `${XDG_DATA_HOME:-~/.local/share}/neutrino-appimage` | `/opt/neutrino/usr/var` | beschreibbar, beim ersten Start befüllt |

   Über `NEUTRINO_APPIMAGE_STATE` lassen sich mehrere Konfigurationen trennen
   oder ein Neuanfang erzwingen.

   `AppRun` braucht einen privaten Mount-Namespace und versucht drei Wege: als
   Root direkt, sonst über unprivilegierte User-Namespaces, sonst über `bwrap`
   (Paket `bubblewrap`, hilft auf Ubuntu 24.04, wo AppArmor User-Namespaces
   einschränkt). Klappt keiner, sagt es das — statt ohne Oberfläche zu starten.
   Container-Laufzeiten blockieren alle drei; Docker braucht `--privileged`,
   Root im Container allein genügt nicht.

   Diese Einblendung ist eine Überbrückung, kein Zielzustand. Sie fällt weg,
   sobald Neutrino seine Datenpfade zur Laufzeit auflöst statt sie einzubacken.

   **Werkzeuge.** `scripts/ensure_appimagetool.sh` legt drei Artefakte in
   `tools/` ab, jedes auf ein getaggtes Release gepinnt und gegen eine
   hinterlegte SHA-256 geprüft:

   | Artefakt | wofür |
   |---|---|
   | `appimagetool` | packt die AppDir |
   | `runtime` (type2-runtime) | statisch mit fuse3 gelinkt, dadurch muss auf dem Zielsystem kein `libfuse2` installiert sein |
   | `linuxdeploy` | sammelt die Bibliotheken ein und wendet dabei die Upstream-Excludelist an |

   Die Excludelist hält `libGL`, `libGLX` und `libGLdispatch` aus dem Paket
   heraus: das sind die Einstiegspunkte in den Grafiktreiber des Rechners, auf
   dem das AppImage läuft, und sie mitzuliefern zerstört genau die Systeme, für
   die sie ausgeschlossen wurden. `libGLEW` und `libglut` kommen mit, ebenso
   `libfreetype` und `libcom_err`, die die Excludelist verwirft, die Neutrino
   auf einem Standardsystem aber braucht.

   **GStreamer.** Die Wiedergabe ist der eine Teil, den kein Abhängigkeitslauf
   findet. GStreamer lädt seine Elemente per `dlopen`, und libstb-hal baut die
   Pipeline erst beim Abspielen über `gst_element_factory_make("playbin", …)` —
   ein Paket ohne diese Module startet also einwandfrei, zeigt seine Menüs und
   spielt dann nichts ab. Sie werden deshalb vollständig vom Buildhost
   übernommen (`pkg-config --variable=pluginsdir gstreamer-1.0`), zusammen mit
   den Bibliotheken, die sie brauchen — gemessen ist das der Unterschied
   zwischen 35 MB und 136 MB.
   `APPIMAGE_BUNDLE_GSTREAMER=0` baut die kleine Variante, dafür braucht das
   Zielsystem dann ein eigenes GStreamer.

   Ihre Abhängigkeiten werden berechnet, nicht angenommen. Die Upstream-
   Excludelist verwirft `libfontconfig`, `libharfbuzz`, `libfribidi` und
   `libasound` in der Annahme, der Host bringe sie mit; ein unverändertes
   Debian 13 tut das nicht. Das Ergebnis waren 19 Module, die im Paket lagen und
   sich nicht laden ließen — darunter `libgstlibav`, also sämtliche
   `avdec_*`-Decoder und die ALSA-Senke, ohne dass eine Dateiliste das gezeigt
   hätte. Die Hülle wird deshalb nach dem linuxdeploy-Lauf berechnet, wobei nur
   übersprungen wird, was zwingend vom Rechner selbst kommen muss.

   Vier Sorten Modul fliegen sofort wieder raus. `va`, `vaapi`, `vdpau` und
   `nvcodec` geben das Dekodieren an den Grafiktreiber des Hosts weiter — aus
   demselben Grund, aus dem `libGL` nicht mitkommt. `gtk`, `gtkwayland` und
   `onnx` erfüllen Zwecke, die Neutrino nicht hat, und zogen GTK 3 sowie eine
   ML-Laufzeit nach. Alles andere bleibt: welchen Demuxer ein Stream braucht,
   entscheidet sich zur Laufzeit, und eine handverlesene Liste wäre für
   irgendjemandes Medien bald falsch.

   Eine abweichende Prüfsumme lässt den Build scheitern. Das ist Absicht: sie
   bedeutet, dass sich das gepinnte Upstream-Artefakt geändert hat, und das
   gehört angesehen, bevor die Prüfsumme in
   `scripts/ensure_appimagetool.sh` nachgezogen wird.

   `APPIMAGE_TOOL` auf ein eigenes Executable setzen, um das gepinnte
   appimagetool zu umgehen, etwa zum Testen anderer Werkzeuge.

2. **Debian-Paket (`make package-deb`)**
   - Generiert eine minimalistische `DEBIAN/control`-Datei und ein `postinst`-Skript mit Root-Hinweisen.
   - Installation via `dpkg -i neutrino-generic-pc_<version>_<arch>.deb`.
   - Empfohlene Nacharbeit: Benutzer zu `video`, `input`, `plugdev` hinzufügen.

3. **Statisches Archiv (`make package-static`)**
   - Führt intern `make neutrino-static` aus und archiviert das Ergebnis.
   - Achtung: Statisch gelinkte Builds können größer sein und Probleme mit proprietären Grafiktreibern verursachen.

## Wie Artefakte versioniert werden

`scripts/version_info.sh` ist die einzige Quelle. Es meldet

```
<major>.<minor>.<micro>+git<JJJJMMTTHHMMSS>.g<commit>[~dirty]
```

also zum Beispiel `2026.8.27+git20260815065207.g13ae2fa8b8`. Die drei Zahlen
stammen aus Neutrinos `configure.ac`, das upstream automatisch gepflegt wird —
`ver_micro` ist der Commit-Abstand zum Anker-Tag. Der Zeitstempel ist das
Commit-Datum in **UTC**, der Hash auf feste zehn Zeichen gekürzt.

Jeder Bestandteil hat einen Grund:

- Der **Zeitstempel** macht die Version monoton, so dass `apt` ein neueres Paket
  auch als neuer erkennt. Ohne ihn sortierte die Version *unter* dem bereits
  Ausgelieferten, und mehrere Commits zwischen zwei `ver_micro`-Bumps wären nur
  nach ihrem Hash geordnet, also willkürlich.
- Die **feste Hash-Länge** ist es, was die Version reproduzierbar macht. Git
  leitet die automatische Kürzung aus der Objektanzahl ab — derselbe Commit
  hätte sieben Zeichen im flachen CI-Klon und zehn im Vollklon des Entwicklers.
- `~dirty` kennzeichnet einen Bau aus verändertem Baum. Die Tilde sortiert in
  Debians Ordnung *unter* dem sauberen Bau; ein Pluszeichen sortierte darüber,
  und ein gepatchtes CI-Artefakt überholte damit das Release, aus dem es stammt.

Daraus werden zwei Formen abgeleitet. Die **Paketversion** behält das `+`, weil
dpkg es so erwartet, und enthält keinen Bindestrich, damit dpkg nicht einen Teil
davon für eine Debian-Revision hält. Der **Dateiname** ersetzt das `+` durch
einen Punkt: `Neutrino_2026.8.27.git20260815065207.g13ae2fa8b8_x86_64.AppImage`.
Uploads von Release-Assets verstümmeln Sonderzeichen, und ein als Leerzeichen
gelesenes `+` lässt den Download-Link ins Leere zeigen.

Ein Quellbaum ohne `.git` — Export oder Tarball — meldet das nackte
`<major>.<minor>.<micro>`. Ein vorhandenes, aber unbrauchbares `.git` ist etwas
anderes und bricht den Bau ab: die nackte Version sortiert unter jedem echten
Paket und würde nie als Upgrade angeboten, deshalb ist stilles Raten schlechter
als Anhalten.

Das Feld `git_tag` im JSON ist reine Information und ausdrücklich **nicht**
reproduzierbar: ein flacher Klon hat keine Tags, gegen die `describe` arbeiten
könnte. Genau darum entscheidet es über keinen Namen mehr.

Eine Folge, die man kennen sollte: weil die Neutrino-Quellen mit `--depth 1`
geklont werden, zeigt `ver_git` aus `configure.ac` — die VCS-Zeile unter
*Image-Informationen* — bei einem CI-Bau einen nackten Commit-Hash, wo ein
lokaler Bau `v2026.8-32-g13ae2fa8b8` anzeigt. Tags nachzuholen behebt das nicht;
`git describe` braucht die Historie zwischen HEAD und Tag, und die hat ein
flacher Klon nicht.

## Vorbereitung

- Vor dem Paketieren mindestens einmal `make neutrino` ausführen, damit das Sysroot `artifacts/sysroot` gefüllt ist.  
  Für statische Bundles zusätzlich `make neutrino-static` starten.
- Prüfen, ob alle benötigten Tools installiert sind:
  - `chrpath` oder `patchelf` für AppImage-Builds. Der Linker trägt das
    Staging-Verzeichnis als `RUNPATH` ein; ohne eines der beiden würde das
    Paket den Rechner benennen, auf dem es gebaut wurde, und der Build bricht
    deshalb ab.
  - `docker`, wenn `make package-appimage-verify` das Paket auf einem sauberen
    System starten soll. Die Werkzeuge selbst (`appimagetool`, der Runtime und
    `linuxdeploy`) holt `scripts/ensure_appimagetool.sh`; `libfuse2` muss weder
    auf dem Build-Host noch auf dem Zielsystem installiert sein. Fehlt auf dem
    Ziel jedes `fusermount`, erscheint zuerst eine Zeile, die mit `Error:`
    beginnt, danach entpackt sich das AppImage selbst und läuft trotzdem.
  - `dpkg-deb` (Teil von `dpkg-dev`) für Debian-Pakete.
- `python3` für `scripts/version_info.sh` (wird durch `make deps` bereitgestellt).
- Die Make-Targets selbst benötigen keine Root-Rechte; Installation/Entpacken der Artefakte üblicherweise schon.
- Alle Formate in einem Rutsch bauen: `make package-appimage package-deb package-static`.
Hinweis: Die früheren Container-Workflows sind entfernt; alle Targets laufen direkt auf dem Host.

## AppImage prüfen

```bash
make package-appimage-verify
```

`ldd` auf dem Build-Rechner beweist nichts, weil dort jede Abhängigkeit
installiert ist. Genau deshalb sah das Paket lange in Ordnung aus, obwohl es
gar keine Daten enthielt. Geprüft wird darum das fertige Artefakt, und danach
wird es auf einem System gestartet, das Neutrino nie gebaut hat:

- Das Binary sucht seine Daten unterhalb des Prefix, den das Paket auch
  mitbringt — ein Entwicklerbuild kann so nicht versehentlich paketiert werden.
- Kein Pfad des Build-Rechners überlebt — weder im Binary, noch im `RUNPATH`,
  noch in irgendeiner anderen mitgelieferten Datei. Eine dokumentierte Ausnahme:
  LuaJIT wird mit `PREFIX` auf das Staging-Verzeichnis gebaut statt mit `/usr`
  plus `DESTDIR`, sein eingebackener Modulsuchpfad nennt also den Build-Rechner.
  `AppRun` setzt `LUA_PATH` und `LUA_CPATH`, damit dieser Standard nie benutzt
  wird; den String selbst loszuwerden hieße zu ändern, wie LuaJIT gebaut wird,
  und das verschöbe den Modulpfad auch für den Entwicklerbau.
- Icons, Locales, Webroot, Schriften und die Konfigurationsvorlage sind da.
- Keine Bibliothek der libGL-Familie und kein Teil der C-Laufzeit ist
  gebündelt, jede mitgelieferte Bibliothek passt zur Architektur des Binaries,
  und die Bibliotheken, die der Host nicht mitbringt, sind da. `libva`,
  `libva-drm`, `libva-x11`, `libvdpau` und `libwayland-egl` kommen mit: das
  Host-`libavcodec`, das `libgstlibav` braucht, führt sie in `DT_NEEDED`, und
  sie wegzulassen kostet jeden `avdec_*`-Decoder. Anders als `libGL` scheitern
  sie weich und fallen auf Software-Dekodierung zurück. Über X11- und
  Wayland-Client-Bibliotheken entscheidet die Upstream-Excludelist, weshalb
  einige davon mitkommen — sie sind Protokollbibliotheken, keine
  Treiber-Einstiegspunkte.
- Auf einem unveränderten `debian:13` — bevor irgendetwas installiert wird —
  sind die einzigen Bibliotheken, die das Paket nicht auflösen kann, der
  Grafik-Stack, den es bewusst nicht mitliefert. Dieser Durchlauf macht die
  Host-Anforderung weiter unten zu einer gemessenen Zahl statt zu einer
  Behauptung: eine Bibliothek, die gebündelt gehört und fehlt, fällt hier auf —
  auf dem Build-Host niemals.
- Erst danach startet es in diesem Container mit der dokumentierten
  Host-Anforderung, **parst** seine mitgelieferte Schrift aus dem
  eingeblendeten Prefix und liest sein Locale. Der Beweis muss aus einer Zeile
  kommen, die *nach* dem Öffnen der Datei gedruckt wird: Neutrino gibt
  `font file: <Pfad>` aus einer Compile-Zeit-Konstante aus, *bevor* es
  `access()` aufruft — wer auf diese Zeile prüft, lässt ein Paket mit leerem
  Datenbaum durch, und genau das ist einmal passiert.
- Es legt eine benutzereigene Konfiguration aus den mitgelieferten Vorgaben an.
- Jedes gebündelte GStreamer-Modul wird auf diesem sauberen System auf
  unaufgelöste Bibliotheken geprüft, und eine eigens gebaute Sonde bestätigt,
  dass daraus noch ein `playbin` entsteht. Die Dateien aufzuzählen beantwortet
  weder das eine noch das andere: ein Modul, dessen eigene Abhängigkeit fehlt,
  ist gleichzeitig vorhanden und nicht ladbar.

`APPIMAGE_VERIFY_CONTAINER=0` beschränkt das auf die statischen Prüfungen. Diese
statischen Prüfungen werden ihrerseits offline getestet, von
`tests/shell/test_appimage_verify.sh`: jede Assertion dort zerstört eine
Eigenschaft eines bekannt guten Pakets und verlangt, dass das Gate sie benennt —
denn eine Prüfung, die nicht fehlschlagen kann, ist der Fehler, den dieses Gate
zweimal hatte. Die andere Hälfte, die AppRun-Abbildung und die
Bibliotheks-Politik in `gen_appimage.sh`, deckt
`tests/shell/test_appimage_bridge.sh` ab. Beide laufen als Teil von
`make test-shell`.

## Was das Paket auf dem Zielsystem braucht

Das AppImage wird gegen die C-Bibliothek des Build-Hosts gebaut und läuft nicht
auf einer Maschine mit einer älteren. Gemessen auf dem aktuellen Debian-13-Build-
Host liegt die Untergrenze bei **glibc 2.39, GLIBCXX 3.4.32 und CXXABI
1.3.15**: Ubuntu 24.04 und Fedora 41 laufen, Debian 12 und Ubuntu 22.04 nicht
(`version GLIBC_2.38 not found`). Das Binary allein käme mit 2.38 aus — das
mitgelieferte `libsystemd` hebt die Grenze an. `make package-appimage-verify`
misst deshalb das gesamte Paket gegen diese Zahl und schlägt fehl, wenn ein
neuerer Build-Host sie nach oben schiebt.

Diese Grenze ist eine Eigenschaft des Build-Hosts, nicht des Codes — auf einer
älteren Basis zu bauen senkt sie für alle.

Neben der C-Bibliothek muss das Zielsystem **den OpenGL- und X11-Stack**
mitbringen: `libgl1` auf Debian und Ubuntu (zieht `libX11` mit), `mesa-libGL`
plus `libglvnd-glx` auf Fedora. Das ist die direkte Folge daraus, die
Grafikbibliotheken nicht zu bündeln — sie sprechen mit dem Treiber der Maschine,
und eine mitgelieferte Kopie ist der klassische Weg, ein AppImage genau auf den
Systemen scheitern zu lassen, für die es gedacht war. Ein unveränderter
`debian:13` bleibt deshalb mit `libGL.so.1: cannot open shared object file`
stehen, und `make package-appimage-verify` misst diese Menge bei jedem Lauf, so
dass die Liste nicht unbemerkt wachsen kann.

Darüber hinaus nichts: kein `libfuse2`, kein GStreamer, keine
Build-Abhängigkeiten von Neutrino. Fehlt auf dem Ziel jedes `fusermount`,
erscheint eine Zeile mit `Error:`, danach entpackt sich das Paket selbst und
läuft.

Die Weboberfläche des Pakets ist auf **Port 80** konfiguriert, nicht auf den
31344, den `NEUTRINO_WEB_PORT` für den Entwicklerbau setzt: die mitgelieferte
`nhttpd.conf` trägt Neutrinos eigenen Standard. Port 80 verlangt Rechte, die ein
gewöhnlicher Benutzer nicht hat — ein rootloser Lauf weicht deshalb auf 8080 aus
und bricht den Webserver ab, wenn auch der belegt ist. Für einen rootlosen
Betrieb `WebsiteMain.port` in
`~/.local/share/neutrino-appimage/tuxbox/config/nhttpd.conf` nach dem ersten
Start auf einen Port über 1024 setzen.

## Wichtige Variablen

Alle Werte lassen sich inline (`make PACKAGE_VERSION=3.30.0 package-deb`) oder dauerhaft in einer `Makefile.local` überschreiben. Standardpfade beziehen sich auf das Repository-Stammverzeichnis (`${PWD}`).

| Variable | Standard | Verwendet von | Wirkung |
| --- | --- | --- | --- |
| `APPIMAGE_TOOL` | nicht gesetzt | AppImage | Executable, das statt des gepinnten appimagetool benutzt wird. Für reproduzierbare Pakete leer lassen. |
| `APPIMAGE_OUTPUT_DIR` | `artifacts/appimage` | AppImage | Zielordner für erzeugte AppImage-Dateien. |
| `APPIMAGE_RUNTIME_PREFIX` | `/opt/neutrino` | AppImage | Prefix, gegen den das paketierte Neutrino gebaut wird und den AppRun zur Laufzeit einblendet. |
| `APPIMAGE_BUILD_DIR` | `build/neutrino-appimage` | AppImage | Build-Verzeichnis der Paketvariante, getrennt vom Entwicklerbuild. |
| `APPIMAGE_SYSROOT` | `artifacts/sysroot-appimage` | AppImage | Staging-Baum der Paketvariante. |
| `NEUTRINO_APPIMAGE_STATE` | `${XDG_DATA_HOME:-~/.local/share}/neutrino-appimage` | AppImage (Laufzeit) | Wo das fertige Paket seine Konfiguration ablegt. Wird von AppRun gelesen, nicht vom Build. |
| `APPIMAGE_VERIFY_IMAGE` | `debian:13` | Verifikation | Container-Image, in dem das Paket gestartet wird. |
| `APPIMAGE_VERIFY_CONTAINER` | `1` | Verifikation | Auf `0` setzen, um nur die statischen Prüfungen zu fahren. |
| `NEUTRINO_NAME` | `Neutrino` | AppImage | Basisname für `Neutrino_<version>_<arch>.AppImage`. |
| `PACKAGE_NAME` | `neutrino-generic-pc` | Debian | Paketname (`Package:`-Feld und Dateiname). |
| `PACKAGE_VERSION` | aus Git abgeleitet | Debian | Versionsstring; für Releases überschreiben (z. B. `PACKAGE_VERSION=3.30.0`). |
| `DEB_OUTPUT_DIR` | `artifacts/deb` | Debian | Zielordner für `.deb`-Pakete. |
| `STATIC_OUTPUT_DIR` | `artifacts/static` | Statisch | Zielordner für statische Tarballs. |
| `NEUTRINO_INSTALL_DIR` | `artifacts/sysroot` | AppImage / Debian | Sysroot, das in die Pakete/AppDir kopiert wird. |
| `NEUTRINO_INSTALL_DIR_STATIC` | `artifacts/sysroot-static` | Statisch | Installationsbaum aus `make neutrino-static`. |
| `NEUTRINO_PREFIX` | `/usr` | Alle | Prefix für Binary und Bibliotheken im Paket. Nicht der Datenprefix — das ist `APPIMAGE_RUNTIME_PREFIX`. |

Tipp für automatisierte Releases:

```bash
make PACKAGE_VERSION=3.30.0 \
     PACKAGE_NAME=neutrino-generic-pc \
     NEUTRINO_NAME="Neutrino Desktop" \
     package-appimage package-deb
```

## Lizenzhinweise

- Behalten Sie Lizenzdateien der eingebetteten Bibliotheken bei (GPL, LGPL, MIT etc.).
- Für AppImage/Static können zusätzliche `LICENSES/`-Ordner sinnvoll sein.

## Typische Stolpersteine

- **`appimagetool not found`**: `scripts/ensure_appimagetool.sh` ausführen (wird durch `make package-appimage` automatisch gestartet) oder Binary von https://appimage.github.io/AppImageKit/ herunterladen und im `PATH` ablegen.
- **`dpkg-deb` fehlt**: Paket `dpkg-dev` nachinstallieren.
- **Statische Builds scheitern**: Prüfen, ob alle Abhängigkeiten `--enable-static` unterstützen (ggf. auf musl wechseln).

Weitere Hintergrundinfos befinden sich in `docs/README.de.md`.

## Installation & Start der Artefakte

- **AppImage** (z. B. `Neutrino_0a129a0-x86_64.AppImage`)
  1. AppImage auf das Zielsystem kopieren.
  2. Ausführbar machen: `chmod +x Neutrino_<version>-<arch>.AppImage`.
  3. Start (Root empfohlen): `sudo ./Neutrino_<version>-<arch>.AppImage`. `ALLOW_NON_ROOT=1` nur nutzen, wenn fehlende Gerätefunktion akzeptabel ist.

- **Debian-Paket** (z. B. `neutrino-generic-pc_3.25.0+git0a129a0_amd64.deb`)
  1. Installation per `sudo apt install ./neutrino-generic-pc_<version>_<arch>.deb`.
  2. Binary liegt anschließend unter `/usr/bin/neutrino`; Start über `sudo neutrino` (oder via Service/Unit). Das Postinst-Skript weist nochmals auf Root-/Geräteanforderungen hin.
