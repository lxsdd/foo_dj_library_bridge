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
- Beide DLLs werden mit VS2022-Toolset `v143` gebaut und anhand
  ihrer tatsächlichen PE-Architektur geprüft. Die private Komponente
  wird ausschließlich in einen explizit angegebenen **neuen**
  Zielordner kopiert, inklusive Build-Manifest und SHA-256-Prüfsummen.
  Bereits existierende Zielordner werden **nicht überschrieben**.
- Kein 7-Zip notwendig. Es werden nur vorhandene lokale Werkzeuge
  verwendet; keine Nachinstallation von Visual Studio oder Git.

## Voraussetzungen – erst später auf dem eigenen Windows-Rechner

- Windows 10/11 und **PowerShell 7.2+** (`pwsh.exe`).
- Visual Studio 2022/2026 Build Tools mit **MSVC v143 für Win32/x64**
  und `MSBuild`; `vswhere` und der bereits gefundene MSBuild-Pfad werden für
  die unabhängige Erkennung von Compiler und Build-System genutzt.
- Der Preflight meldet `BRIDGE_PREFLIGHT_MSVC_VERSIONS`, um eine installierte
  VS2026-Standardversion 14.5x (**v145**) von einem kompatiblen 14.3x/14.4x
  (**v143**) zu unterscheiden. Bei weiterhin fehlendem v143 darf keine
  andere Compiler-Version stillschweigend als kompatibel gelten. In diesem
  Fall kann der Eigentümer bei Bedarf im **Visual Studio Installer → Ändern →
  Einzelne Komponenten** gezielt `MSVC v143 – VS 2022 C++ x64/x86 build tools`
  nachinstallieren; **kein automatisches Setup oder Lizenzakzeptieren**.
  Ein solcher Eingriff ist optional bis zur lokalen Geräteendprüfung.
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
pwsh -NoProfile -File $helper -PreflightOnly
pwsh -NoProfile -File $helper -SourceSha $sha -OutputDirectory 'C:\Temp\BridgePrivateAcceptance'
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
- Bei fehlenden Tools/HTTPS bleibt der private Endabnahme-Build
  blockiert. Ohne ausdrückliche Gerätefreigabe wird nichts dort
  installiert oder verändert.
- Öffentliche Binary-Releases bleiben nach unserer dauerhaften
  Freigaberegel bis zur unabhängigen privaten Endabnahme,
  rechtlichen Notice-/Provenance- und exakten Release-Verifikation gesperrt.

Siehe [Autonome Sicherheitsregel](AUTONOMOUS-PROMOTION-POLICY.md) und
[Lizenzhinweise](THIRD-PARTY-NOTICES-INVENTORY.md).
