# Privater Bridge-Endabnahme-Build – aktuelles SDK 2026-10-01

**Vorbereitung, kein Auftrag zum Testen auf deinem DJ-Rechner.**
Das Skript `scripts/local-acceptance-build.ps1` erstellt eine
**ausschließlich lokale** Win32/x64-`.fb2k-component` für die spätere
Endabnahme. Es installiert nichts, startet foobar nicht, greift nicht auf
Musikdateien, Tags, Musik-/foobar-/rekordbox-Datenbanken zu und lädt keine
DLL oder anderen Artefakte nach GitHub hoch.

## Was das Skript sicherstellt

- `-PreflightOnly` prüft ausschließlich vorhandene Windows-Build-Werkzeuge.
  Keine Downloads, Installationen oder Profilzugriffe.
- Ein echter Build verlangt eine **zuvor freigegebene, vollständige
  40-stellige Git-Commit-SHA**. Der Originalcode wird in einem zufälligen
  Temp-Unterordner ausgecheckt; `git rev-parse HEAD` muss exakt die
  angeforderte SHA bestätigen. Der temporäre Git-Ordner wird nach dem
  Build entfernt. **Kein dauerhaftes lokales Repository.**
- Die kombinierte MIT + Commons Clause v1.0 mit `Licensor: lxsdd`
  wird anhand ihres festgelegten Git-Objekthashes überprüft. Es werden
  keine fremden Rechte übertragen und keine SDK-Lizenztexte ersetzt.
- Das Projekt verwendet das gepinnte foobar2000-SDK **2026-10-01**,
  das `scripts/bootstrap-sdk.ps1` aus dem vorhandenen
  `lxsdd/foobar2000_component_template` Git-Commit
  `31a35947a7527826c2199491692802e3ce3d8bd7`
  mit SDK-Subtree `2ba8caeb73f72633ad7f60ee5f72ed8074a0eb17`
  holt. Dies prüft den **Git-Quellbaum**, nicht die Byteidentität
  des offiziellen Hersteller-`.7z`-Archivs.
- Beide DLLs werden aus **demselben exakt gepinnten Git-Quellstand** mit
  dem ausdrücklich ausgewählten MSVC-Toolset gebaut: `v143` (VS2022) oder
  nach separater Win32/x64-Hostqualifikation `v145` (VS2026, 14.5x).
  Die tatsächliche PE-Architektur wird in beiden Fällen geprüft. Die private Komponente
  wird ausschließlich in einen explizit angegebenen **neuen**
  Zielordner kopiert, inklusive Build-Manifest und SHA-256-Prüfsummen.
  Bereits existierende Zielordner werden **nicht überschrieben**.
- Kein 7-Zip notwendig. Es werden nur vorhandene lokale Werkzeuge
  verwendet; keine Nachinstallation von Visual Studio oder Git.

## Voraussetzungen – erst später auf dem eigenen Windows-Rechner

- Windows 10/11 und **PowerShell 7.2+** (`pwsh.exe`).
- Visual Studio 2022/2026 Build Tools, `MSBuild` und ein tatsächlich
  vorhandenes **MSVC v143 (14.3x/14.4x) oder v145 (14.5x)** mit `cl.exe`
  für **beide Architekturen**, x86 und x64. `vswhere` und der erkannte
  MSBuild-Pfad werden getrennt ausgewertet.
- `BRIDGE_PREFLIGHT_MSVC_VERSIONS`, `BRIDGE_PREFLIGHT_V143`,
  `BRIDGE_PREFLIGHT_V145` und `BRIDGE_PREFLIGHT_SELECTED_TOOLSET` machen die
  Entscheidung nachvollziehbar. Die Wahl ist auf `Auto`, `v143` und `v145`
  beschränkt; `Auto` bevorzugt den bisher qualifizierten v143, andernfalls
  v145. Ein nicht gefundenes Toolset bleibt **FAIL**.
- `v145` ist kein pauschaler Ersatz für alle Compiler: sein Einsatz bei
  der Bridge setzt bestandene reale foobar-Win32/x64-Hosttests samt CUE,
  Original-Readern und privatem SHA-Build in GitHub voraus. Ein grüner
  Preflight allein ist **keine** Geräte- oder Sicherheitsabnahme.
- Eine zusätzliche v143-Installation ist für einen nachgewiesen qualifizierten
  v145-Build **nicht erforderlich**. Es gibt weiterhin keinerlei automatische
  Installation oder Annahme von Microsoft-Vertragsbedingungen.
- **Git for Windows** sowie HTTPS-Zugriff auf die beiden genannten
  GitHub-Repositories und ausreichend temporärer Speicher.
- Eine erfolgreich mit genau dieser Git-SHA qualifizierte Bridge-Version.
  Die Build-Tools müssen bereits installiert sein; bei Fehlen ist
  der Preflight ein **FAIL**, kein Anlass, Sicherheitseinstellungen
  oder Installationen automatisch zu verändern.

### Vorgesehener Ablauf (noch nicht ausführen)

```powershell
$sha = '<QUALIFIZIERTE_40_STELLIGE_GIT_SHA>'
$helper = Join-Path $env:TEMP 'bridge-local-acceptance-build.ps1'
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lxsdd/foo_dj_library_bridge/$sha/scripts/local-acceptance-build.ps1" -OutFile $helper
pwsh -NoProfile -File $helper -PreflightOnly -Toolset v145
# Erst nach erfolgreicher exakter v145-CI-Qualifikation und Gerätefreigabe:
pwsh -NoProfile -File $helper -SourceSha $sha -Toolset v145 -OutputDirectory 'C:\Temp\BridgePrivateAcceptance'
```

Keine Freigabe zur Weitergabe der erstellten Dateien an Dritte.
Insbesondere wird der separate Herstellerinstaller **nicht**
mit der privaten Komponente gebündelt. Die echte Endabnahme muss
anschließend **separat** in einem isolierten foobar-Profil beginnen.
Für produktive/portable Profile benötigen wir ausdrücklich
freigegebenen, rein lesenden Zugriff und vorher/nachher überprüfte
Audio-/Datenbank-Sicherheitsinvarianten.

## Noch offene Punkte

- Der neue Preflight wird für jeden veränderten Commit erneut auf
  Windows-CI-Runnern geprüft. Die lokale Toolchain auf dem Eigentümergerät
  bleibt eine getrennte Endabnahmevoraussetzung; keine vom GitHub-Runner
  verfügbaren Binärdateien werden zum Eigentümergerät veröffentlicht.
- Ein grüner GitHub-Runner beweist **nicht** die Verfügbarkeit der
  lokalen MSVC/PowerShell/Git-Werkzeuge oder tatsächliche Wiedergabe
  auf dem persönlichen Rechner.
- Bei fehlenden tatsächlich qualifizierten Tools/HTTPS bleibt der
  private Endabnahme-Build blockiert. Eine erkannte v145-Version darf niemals
  einen roten Win32/x64-CI-Hosttest übergehen. Ohne ausdrückliche Gerätefreigabe wird nichts dort
  installiert oder verändert.
- Öffentliche Binary-Releases bleiben nach unserer dauerhaften
  Freigaberegel bis zur unabhängigen privaten Endabnahme,
  rechtlichen Notice-/Provenance- und exakten Release-Verifikation gesperrt.

Siehe [Autonome Sicherheitsregel](AUTONOMOUS-PROMOTION-POLICY.md) und
[Lizenzhinweise](THIRD-PARTY-NOTICES-INVENTORY.md).
