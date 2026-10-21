# Nichtöffentlicher lokaler Endabnahme-Build der foobar Bridge

**Für persönliche Prüfung, keine Freigabe zur öffentlichen Weitergabe.**

Der geprüfte PowerShell-Helfer `scripts/local-acceptance-build.ps1` erstellt auf
**dem eigenen Windows-Rechner** eine Win32/x64-`.fb2k-component`, ohne den
Build über öffentliche GitHub-Actions-Artefakte zu verteilen. Er installiert
keine DLL, liest keine Musikbibliothek, ändert keine Tags und schreibt nicht
in produktive foobar-Profile. Die Quellen liegen vorübergehend in einem
GUID-basierten Temp-Verzeichnis, nicht in einem dauerhaften Git-Repository.

## Voraussetzungen

- Windows 10/11, installierte Visual Studio 2022/2026 Build Tools mit
  **MSVC v143 für Win32 und x64** sowie MSBuild. Der Helfer findet diese
  über `vswhere`; eine Developer PowerShell ist nicht zwingend erforderlich.
  Fehlende Werkzeuge werden nur angezeigt, **nicht installiert**.
- 7-Zip/`7z.exe`, ausreichend freier temporärer Speicher, HTTPS-Zugriff
  auf GitHub und foobar2000.org
- Eine **vorher qualifizierte exakte 40-stellige lowercase Git-Commit-SHA**
- Ein ausdrücklich benannter neuer lokaler Ausgabeordner

## Beispiel, ohne Git-Clone oder Downloads vom öffentlichen Actions-Artefaktserver

```powershell
$sha = '<40-STELLIGER-QUALIFIZIERTER-COMMIT-SHA>'
$helper = Join-Path $env:TEMP 'bridge-local-acceptance-build.ps1'
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/lxsdd/foo_dj_library_bridge/$sha/scripts/local-acceptance-build.ps1" -OutFile $helper
& $helper -PreflightOnly
& $helper -SourceSha $sha -OutputDirectory 'C:\Temp\BridgePrivateAcceptance'
```

Das Skript lädt ausschließlich das Quellcode-ZIP zu **diesem SHA**, kontrolliert
den Archivordner, baut per bestehenden Originalskripten für Win32 und x64
und nutzt dabei das offiziell von foobar2000.org bezogene SDK **2026-09-17**.

Das SDK ist seit dem Draft-Fix mit **793742 Byte** und SHA-256
`24fa95ed66b42624f593fd4b94c5efb08ae81dfebb92b79fe69c8cd170961e48`
festgepinnt. Die Werte stimmen aus zwei unabhängigen Windows-Runner-Downloads
im [öffentlichen Lauf 39434344038](https://github.com/lxsdd/foo_dj_library_bridge/actions/runs/39434344038)
überein. Abweichende Archive oder ungeprüfte alte SDK-Verzeichnisse werden
abgewiesen.

Der originale `package-component.ps1` prüft die Win32-/x64-PE-Maschinenwerte,
erzeugt Manifest/Prüfsummen und schreibt zusammen mit der Komponente nur in
`<OutputDirectory>\Bridge-local-<SHA>\`. Bestehende Zielordner werden nicht
überschrieben. Temporäre Quellen werden nach dem Build entfernt.

## Nachweis und noch offene Freigaben

- [GitHub Test 39435835240](https://github.com/lxsdd/foo_dj_library_bridge/actions/runs/39435835240)
  **SUCCESS** für komplette lokale Quellarchiv-Download-/Win32-/x64-
  Kompilierung sowie Manifest- und Paket-SHA-256-Verifikation.
- Der Lauf hat **0 hochgeladene GitHub-Actions-Artefakte**; die DLL blieb
  ausschließlich im temporären Runner-Bereich.
- Auch der dokumentierte Standalone-Aufruf des einzeln aus GitHub in den
  Windows-Temp-Ordner geladenen Helfers wurde ohne lokal ausgecheckte
  Projektdateien bestätigt
  ([Lauf 39438579118](https://github.com/lxsdd/foo_dj_library_bridge/actions/runs/39438579118), Win32/x64 PASS, 0 Artefakte).
- Die Testkandidaten sind **nicht auf dem Endgerät installiert**. Ein realer
  foobar-Lauf mit standardmäßigem/portablem Profil und persönlicher Sammlung
  bleibt eine separate ausdrückliche Endabnahme.
- Der sichere Privat-Build ist **keine** Urheberrechtsfreigabe für spätere
  öffentliche Binärdistribution und keine pauschale Freigabe für Drittcode.
- Sicherheits-PR und dessen Quellcodeprüfung sind noch **nicht auf main**
  aktiv, solange der jeweilige Merge nicht explizit freigegeben ist.
