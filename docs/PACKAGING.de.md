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
   spielt dann nichts ab. Werden sie mitgeliefert, kommen sie vollständig vom
   Buildhost (`pkg-config --variable=pluginsdir gstreamer-1.0`), zusammen mit
   den Bibliotheken, die sie brauchen — gemessen ist das der Unterschied
   zwischen 35 MB und 136 MB.

   Ob sie mitkommen, hängt am Build und nicht an einem eigenen Schalter:
   `APPIMAGE_BUNDLE_GSTREAMER` steht nur dann auf `1`, wenn
   `LIBSTB_HAL_CONFIGURE_FLAGS` GStreamer einschaltet, und zwar so gelesen, wie
   configure es liest: `--enable-gstreamer` und `--enable-gstreamer=yes` schalten
   ein, `=no` und `--disable-gstreamer` aus, und die letzte Option gewinnt
   (`make/env-derive.mk`, genutzt von `make/package.mk` und `make/neutrino.mk`).
   Diese Flags sind standardmäßig leer, und `libstb-hal/configure.ac` hat
   `enable_gstreamer=no` als Voreinstellung — ein
   **frischer Checkout baut also ein Neutrino ganz ohne GStreamer-Wiedergabe**,
   nicht bloß ein Paket ohne die Module. Ein GStreamer auf dem Zielsystem
   ändert daran nichts, weil nichts es aufriefe. Erst mit
   `LIBSTB_HAL_CONFIGURE_FLAGS=--enable-gstreamer` wird die Wiedergabe
   einkompiliert, und dann kommen die Module auch mit.

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
stammen aus Neutrinos `configure.ac`, das upstream automatisch gepflegt wird.
Der Zeitstempel ist das Commit-Datum in **UTC**, der Hash auf feste zehn Zeichen
gekürzt.

Jeder Bestandteil hat einen Grund:

- Die **Reihenfolge** ergibt sich zuerst aus den drei Zahlen, erst danach aus
  dem Zeitstempel. `ver_micro` wird upstream in einem eigenen Commit erhöht
  (`build (ci): bump configure.ac version`) und steht zwischen zwei solchen
  Bumps still. Es ist also **nicht** der Commit-Abstand zum Anker-Tag, sondern
  bleibt hinter ihm zurück — gemessen `ver_micro=27` bei den Abständen 27 bis
  31, und 32 beim Abstand 32, weil dort der nächste Bump liegt. Bei einem
  neuen Versionsstrang fängt `ver_micro` wieder bei 0 an
  (`2026.7.53` → `2026.8.0`), dabei steigt aber `ver_minor`: was nie zurückfällt,
  ist die **dreiteilige Basis**, und darauf beruht die Ordnung. Innerhalb einer
  Basis ordnet allein das Commit-Datum.
- Weiter reicht die Zusage nicht, und zwar auf zwei verschiedene Arten. Zwei
  Commits **in derselben Sekunde** sind gar nicht geordnet: dpkg fällt auf den
  Hash zurück, also auf Zufall. Ein **zurückdatiertes** Commit-Datum ist
  geordnet, nur falsch herum — dpkg vergleicht die Zeitstempel und stellt das
  jüngere Commit unter sein Elternteil. Eine echte Zählung gäbe es nur mit der
  vollen Historie, und die hat ein `--depth 1`-Klon nicht.
- Die **feste Hash-Länge** ist es, was die Version reproduzierbar macht. Git
  leitet die automatische Kürzung aus der Objektanzahl ab — derselbe Commit
  hätte sieben Zeichen im flachen CI-Klon und zehn im Vollklon des Entwicklers.
  `--short=10` genügt dafür nicht, denn das ist nur eine Untergrenze: Git
  verlängert sie, sobald zehn Zeichen mehrdeutig sind. Deshalb wird die volle
  Objekt-ID geschnitten.
- `~dirty` kennzeichnet einen Bau aus verändertem Baum. Die Tilde sortiert in
  Debians Ordnung *unter* dem sauberen Bau; ein Pluszeichen sortierte darüber,
  und ein gepatchtes CI-Artefakt überholte damit das Release, aus dem es stammt.
  Die Zahlen liest das Skript dabei aus dem Commit, nicht aus dem Arbeitsbaum —
  sonst höbe ein geändertes `configure.ac` die Version an und das gepatchte
  Artefakt überholte das Release trotz `~dirty`.
- `--assume-unchanged` und `--skip-worktree` sagen git, es solle eine Datei nicht
  mehr ansehen. Die Prüfung sieht trotzdem hin: ein Baum, dessen Patch sich
  hinter einem der beiden Bits versteckt, ist weiterhin `~dirty` — sonst trüge
  der Bau den Namen des Releases, von dem er weggepatcht wurde. Ignoriert bleibt
  einzig eine Datei, die `--skip-worktree` absichtlich nicht vorhält: genau das
  erzeugt ein Sparse-Checkout, und ein Sparse-Checkout darf einem Vollklon
  desselben Commits nicht widersprechen. Eine hinter `--assume-unchanged`
  *gelöschte* Datei ist dagegen eine Änderung wie jede andere, denn dieses Bit
  verspricht nur, dass eine vorhandene Datei sich nicht ändert.

Daraus werden zwei Formen abgeleitet. Die **Paketversion** behält das `+`, weil
dpkg es so erwartet, und enthält keinen Bindestrich, damit dpkg nicht einen Teil
davon für eine Debian-Revision hält. Der **Dateiname** ersetzt das `+` durch
einen Punkt und, im veränderten Baum, die Tilde durch einen Bindestrich:
`Neutrino_2026.8.27.git20260815065207.g13ae2fa8b8_x86_64.AppImage`, bzw.
`…g13ae2fa8b8-dirty…`. Uploads von Release-Assets verstümmeln Sonderzeichen, und
ein als Leerzeichen gelesenes `+` lässt den Download-Link ins Leere zeigen.

Ein Quellbaum ohne `.git` — Export oder Tarball — meldet das nackte
`<major>.<minor>.<micro>`. Alles andere, was Git unbrauchbar macht, bricht den
Bau ab: ein `.git`, das Git nicht lesen kann, ein ins Leere zeigender
`.git`-Symlink, ein unlesbarer Index, ein fehlendes Commit-Objekt. Dazu gehört
auch der Fall, dass Git das `.git` bei seiner Suche überspringt und mit dem
*umschließenden* Arbeitsbaum antwortet — `sources/neutrino` liegt im Arbeitsbaum
dieses Repos, und ein abgebrochener Klon hinterlässt genau so ein halbfertiges
`.git`. Die nackte Version sortiert unter jedem echten Paket und würde nie als
Upgrade angeboten, deshalb ist stilles Raten dort schlechter als Anhalten.

Das Feld `git_tag` im JSON ist reine Information und ausdrücklich **nicht**
reproduzierbar: ein flacher Klon hat keine Historie hinter HEAD, also antwortet
`git describe` nur dann, wenn ein Tag genau auf dem geholten Commit sitzt, und
sonst gar nicht. Genau darum entscheidet es über keinen Namen mehr.

Eine Folge, die man kennen sollte: weil die Neutrino-Quellen mit `--depth 1`
geklont werden, zeigt `ver_git` aus `configure.ac` — die VCS-Zeile unter
*Image-Informationen* — bei einem CI-Bau einen nackten Commit-Hash, wo ein
lokaler Bau `v2026.8-32-g13ae2fa8b8` anzeigt. Tags nachzuholen behebt das nicht;
`git describe` braucht die Historie zwischen HEAD und Tag, und die hat ein
flacher Klon nicht.

### Wie ein Release benannt wird

Der Name oben beschreibt **Neutrino**, nicht dieses Repo: alle drei Bestandteile
stammen aus Neutrinos `configure.ac` und Neutrinos HEAD. Für den Dateinamen ist
das richtig — die Frage eines Nutzers lautet, welches Neutrino drinsteckt.

Fürs Archiv reicht es nicht. Zwei Bauten desselben Neutrino-Commits heißen
gleich, auch wenn dazwischen ffmpeg, libstb-hal oder das Packaging gewechselt
haben. Ein dauerhaftes Release allein auf diesen Namen zu setzen hieße, zwei
verschiedene Pakete unter ein Etikett zu stellen.

`scripts/release_tag.sh` benennt deshalb jede **Quell**-Eingabe, die sich
bewegen kann:

```
build/<slug>-<Buildsystem-Commit>-hal<libstb-hal>-dvbsi<libdvbsi++>[-dirty]
```

Der Slug sagt, welches Neutrino drin ist; der Buildsystem-Commit sagt, was es
gebaut hat — Packaging, Rezepte, Patches. Die letzten beiden Teile sind nötig,
weil libstb-hal und libdvbsi++ die beiden Abhängigkeiten sind, die **nicht
gepinnt** sind: `make/neutrino.mk` klont `LIBSTB_HAL_GIT_REF` (`mpx`) an der
Spitze, `make/deps.mk` klont `DVBSI_GIT_REF` (`master`) an der Spitze. Beider
Inhalt kann sich ändern, ohne dass ein anderer Teil sich bewegt. ffmpeg braucht
keinen eigenen Teil, `make/third_party/ffmpeg.mk` pinnt eine Version.

Beide Teile lesen `sys`, wenn es gar keinen Checkout gibt: `make/neutrino.mk`
und `make/deps.mk` überspringen den Bau, sobald der Host bereits eine passende
Bibliothek mitbringt, und eine Systembibliothek lässt sich nicht durch einen
Commit benennen. Verweigert wird das nicht — so ein Bau ist gültig, nur eben
nicht allein durch Commits beschreibbar. In CI gibt es immer beide Checkouts.

Wird kein Commit übergeben, nimmt das Skript HEAD. `-dirty` steht am Ende,
sobald einer der beiden Arbeitsbäume verändert ist — aus demselben Grund, aus
dem oben `~dirty` existiert. Ungetrackte Dateien zählen dabei nicht als
Änderung; ein fremder Plugin-Checkout neben den Quellen ändert nichts am
Gebauten. Eine Ausnahme gibt es: `Makefile.local` und `Makefile.local.post`
sind ebenfalls ungetrackt, werden von `make/main.mk` aber in jeden Bau
eingelesen — wer dort den Compiler oder ffmpeg umstellt, baut etwas anderes,
als die Commits im Tag beschreiben. Ihre bloße Anwesenheit genügt deshalb für
`-dirty`.

Nicht benannt wird die **Maschine**. CI baut auf `ubuntu-latest` und
installiert Hostpakete ungepinnt; GitHub erneuert dieses Image wöchentlich, und
die ABI-Untergrenze weiter oben hängt genau daran. Dieselben drei Commits
könnten Monate später also andere Bytes ergeben — tatsächlich ist es
schlimmer: der Bau ist gar nicht bitreproduzierbar. Gemessen am 2026-08-20
ergaben zwei Dispatches desselben Commits, Minuten auseinander auf demselben
Runner-Image, AppImages mit verschiedenen Prüfsummen. Ein siebenstelliges
Commit-Präfix kann zusätzlich im Prinzip kollidieren. Beides ist bewusst nicht im Tag
gelöst — einen Tag, der ein Runner-Image benennt, liest niemand mehr.
Stattdessen schließt der Archivschritt die Lücke am anderen Ende:
`scripts/publish_release.sh` vergleicht die unter dem Tag bereits
veröffentlichte `SHA256SUMS` mit der gerade gebauten und bricht bei Abweichung
ab. So fällt auf, was sonst still den zuerst hochgeladenen Bau behalten hätte.

Das rollende `latest`-Release braucht nichts davon: es wird bei jedem
veröffentlichenden Lauf überschrieben. Nur das Archiv muss unterscheidbar
bleiben.

### Wann veröffentlicht wird

Nur ein `workflow_dispatch` auf `master`. Pushes, Pull Requests und Tag-Pushes
bauen zwar, veröffentlichen aber nichts: was eine Versionsnummer dieses Repos
bedeuten soll, ist offen, und ein Release an einem Tag würde das nebenbei
beantworten. Der Dispatch hat einen Schalter `archive` (Vorgabe: aus). Ohne ihn
wird nur `latest` ersetzt, mit ihm entsteht zusätzlich das dauerhafte Release
unter dem Tag von oben.

Vier Dinge, die man wissen sollte, weil sie sich nicht wegprogrammieren lassen:

- GitHub hält pro Gruppe höchstens **einen** wartenden Lauf. Ein dritter
  Dispatch, während einer läuft und einer wartet, ersetzt den wartenden — samt
  dessen `archive`-Wunsch. Dann einfach noch einmal auslösen. Die Gruppe nach
  `archive` aufzuteilen würde das verhindern, ließe aber zwei Läufe gleichzeitig
  `latest` veröffentlichen, wo der eine das Paket des anderen wegräumt. Der
  schlechtere Tausch.
- Ein Asset lässt sich nicht an Ort und Stelle ersetzen; `gh` löscht das
  gleichnamige zuerst. Deshalb geht das Paket zuerst hoch, der Tag zieht danach
  nach, aufgeräumt wird zuletzt. Scheitert etwas dazwischen, bleibt im
  Regelfall ein überholtes AppImage zu viel liegen. Zwei Ausnahmen betreffen
  Namen, die sich nicht ändern: wurde derselbe Neutrino-Commit mit anderen
  Bytes gebaut, trägt das Paket denselben Namen und fehlt bis zum nächsten
  Lauf; und `SHA256SUMS` heißt immer gleich, scheitert der Lauf genau dort,
  liegen die Pakete ohne Prüfsumme da. Rot ist der Lauf in jedem Fall, und der
  nächste räumt auf.
- Alle Commits im Tag sind auf sieben Zeichen gekürzt. Teilen sich zwei
  Commits derselben Abhängigkeit dieses Präfix, kollidiert der Tag. Das
  Ergebnis ist dann eine **Verweigerung** des zweiten Archivs, kein falsches:
  der Prüfsummenvergleich schlägt an, bevor etwas hochgeladen wird.
- Ein erneuter Dispatch, der bitgleiche Bytes liefert, lädt gar nichts hoch.
  Das ist eine Sicherung, kein Regelfall: gemessen unterscheiden sich zwei
  Bauten desselben Commits immer. Praktische Folge — ein zweites
  `archive=true` auf einen bereits archivierten Commit wird **abgelehnt**, weil
  das Paket ein anderes ist als das dort liegende. Das ist so gewollt: zwei
  verschiedene Pakete unter einem Etikett waeren schlimmer.

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
  - `dpkg-deb` (Teil des Pakets `dpkg`) für Debian-Pakete.
- `python3` für die Paketierskripte, die das JSON von `scripts/version_info.sh`
  lesen — `make_deb.sh`, `gen_appimage.sh`, `static_link.sh`. `version_info.sh`
  selbst kommt ohne aus. Wird durch `make deps` bereitgestellt.
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
| `APPIMAGE_BUNDLE_GSTREAMER` | `1`, wenn `LIBSTB_HAL_CONFIGURE_FLAGS` GStreamer so einschaltet, wie configure es liest — `--enable-gstreamer` oder `=yes`, letzte Option gewinnt — sonst `0` | AppImage | Folgt dem Build. `0` bei einem mit `--enable-gstreamer` gebauten Neutrino lässt die Module weg — deutlich kleiner, dafür braucht die Wiedergabe dann ein GStreamer auf dem Zielsystem. Beim Standard-Build gibt es keine Wiedergabe, die bedient werden müsste; das Zielsystem braucht nichts. |
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
- **`dpkg-deb` fehlt**: Paket `dpkg` nachinstallieren (nicht `dpkg-dev` — `dpkg-deb` gehört zu `dpkg`).
- **Statische Builds scheitern**: Prüfen, ob alle Abhängigkeiten `--enable-static` unterstützen (ggf. auf musl wechseln).

Weitere Hintergrundinfos befinden sich in `docs/README.de.md`.

## Installation & Start der Artefakte

- **AppImage** (z. B. `Neutrino_2026.8.27.git20260815065207.g13ae2fa8b8_x86_64.AppImage`)
  1. AppImage auf das Zielsystem kopieren.
  2. Ausführbar machen: `chmod +x Neutrino_<version>_<arch>.AppImage`.
  3. Start (Root empfohlen): `sudo ./Neutrino_<version>_<arch>.AppImage`. Ohne Root startet Neutrino, hat aber keinen Zugriff auf DVB- und Eingabegeräte. (`ALLOW_NON_ROOT=1` gehört zu den `make run`-Wrappern und wirkt auf ein AppImage nicht.)

- **Debian-Paket** (z. B. `neutrino-generic-pc_2026.8.27.git20260815065207.g13ae2fa8b8_amd64.deb`)
  1. Installation per `sudo apt install ./neutrino-generic-pc_<version>_<arch>.deb`.
  2. Binary liegt anschließend unter `/usr/bin/neutrino`; Start über `sudo neutrino` (oder via Service/Unit). Das Postinst-Skript weist nochmals auf Root-/Geräteanforderungen hin.
