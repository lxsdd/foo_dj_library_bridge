#requires -Version 7.2
# Private, source-SHA-pinned acceptance build. Never installs into foobar or uploads binaries.
param(
    [string]$SourceSha = '',
    [string]$OutputDirectory = '',
    [switch]$PreflightOnly,
    [ValidateSet('Auto','v143','v145')][string]$Toolset = 'Auto'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Windows 10/11 required.' }
# Check the installed toolchain rather than requiring Developer PowerShell.
# vswhere searches both VS2022 (17.x) and VS2026 (18.x) including BuildTools.
$msbuildCommand = Get-Command msbuild.exe -ErrorAction SilentlyContinue
$msbuildPath = if ($msbuildCommand) { $msbuildCommand.Source } else { '' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
# MSBuild and optional v143 can be installed as separate VS components.
# Do not filter *compiler* discovery by whether a VS instance advertises
# the MSBuild component; MSBuild.exe is checked independently.
$vsRoots = @()
if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
    $vsRoots = @(& $vswhere -all -products '*' -property installationPath |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })
    if (-not $msbuildPath) {
        $choices = @(& $vswhere -all -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\Current\Bin\MSBuild.exe' |
            Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($choices.Count -gt 0) { $msbuildPath = $choices[0] }
    }
}
# Resolve a conventional VS root from MSBuild on PATH as another read-only
# discovery fallback when vswhere does not report the compiler installation.
if ($msbuildPath -and $msbuildPath -match '(?i)^(.*)[\\/]MSBuild[\\/]Current[\\/]Bin[\\/]MSBuild\.exe$') {
    $derivedRoot = $Matches[1]
    if (Test-Path -LiteralPath $derivedRoot -PathType Container) {
        $vsRoots += $derivedRoot
    }
}
$vsRoots = @($vsRoots | Sort-Object -Unique)
$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
$gitPath = if ($gitCommand) { $gitCommand.Source } else { '' }
if (-not $gitPath) {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $gitPath = $candidate
            break
        }
    }
}
# Enumerate only two explicitly reviewed C++ toolset families. Both must
# expose real x86 and x64 cl.exe binaries; do not infer this from MSBuild.
# v143: 14.3x/14.4x; v145 (VS2026): 14.5x.
$hasV143 = $false
$hasV145 = $false
$detectedMsvcVersions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($root in $vsRoots) {
    $toolDir = Join-Path $root 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $toolDir -PathType Container)) { continue }
    $toolsets = @(Get-ChildItem -LiteralPath $toolDir -Directory -ErrorAction SilentlyContinue)
    foreach ($tool in $toolsets) {
        [void]$detectedMsvcVersions.Add($tool.Name)
        $bothArchitectures = (
            (Test-Path -LiteralPath (Join-Path $tool.FullName 'bin\Hostx64\x64\cl.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $tool.FullName 'bin\Hostx64\x86\cl.exe') -PathType Leaf))
        if (-not $bothArchitectures) { continue }
        if ($tool.Name -match '^14\.(3[0-9]|4[0-9])\.') { $hasV143 = $true }
        if ($tool.Name -match '^14\.5[0-9]\.') { $hasV145 = $true }
    }
}
# Log compiler version numbers only; do not expose workstation paths.
$installedMsvc = @($detectedMsvcVersions | Sort-Object)
Write-Host ('BRIDGE_PREFLIGHT_MSVC_VERSIONS=' + $(if ($installedMsvc.Count) { $installedMsvc -join ',' } else { 'NONE' }))
Write-Host ('BRIDGE_PREFLIGHT_MSBUILD=' + $(if ($msbuildPath) { 'FOUND' } else { 'MISSING' }))
Write-Host ('BRIDGE_PREFLIGHT_V143=' + $(if ($hasV143) { 'FOUND' } else { 'MISSING' }))
Write-Host ('BRIDGE_PREFLIGHT_V145=' + $(if ($hasV145) { 'FOUND' } else { 'MISSING' }))
$selectedToolset = if ($Toolset -eq 'Auto') {
    if ($hasV143) { 'v143' } else { 'v145' }
} else { $Toolset }
Write-Host "BRIDGE_PREFLIGHT_SELECTED_TOOLSET=$selectedToolset"
Write-Host ('BRIDGE_PREFLIGHT_GIT=' + $(if ($gitPath) { 'FOUND' } else { 'MISSING' }))
$missing = @()
if (-not $msbuildPath) { $missing += 'MSBuild (VS2022/VS2026)' }
if (($selectedToolset -eq 'v143' -and -not $hasV143) -or
    ($selectedToolset -eq 'v145' -and -not $hasV145)) {
    $missing += "MSVC C++ $selectedToolset x86/x64"
}
if (-not $gitPath) { $missing += 'Git for Windows (temporary SHA-bound source checkout)' }
if ($missing.Count -gt 0) {
    throw ('Preflight missing: ' + ($missing -join ', ') +
        '. No installation or download attempted. GitHub CI builds remain available.')
}
# Nested build.ps1 resolves msbuild.exe using Get-Command; only add to this
# process and any child processes. Never write a persistent PATH setting.
$env:PATH = (Split-Path -Parent $msbuildPath) + [IO.Path]::PathSeparator +
    (Split-Path -Parent $gitPath) + [IO.Path]::PathSeparator + $env:PATH
# Runs standalone from any directory, including a single downloaded script
# under $env:TEMP. Source project files are checked after exact-SHA download.
if ($PreflightOnly) {
    Write-Host 'LOCAL_ACCEPTANCE_PREFLIGHT=PASS; no download, build, installation or personal data touched.'
    return
}
if ($SourceSha -cnotmatch '^[a-f0-9]{40}$') { throw 'Pass exact lowercase 40-digit Git SHA.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'Explicit -OutputDirectory required.' }
$destination = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ("Bridge-local-" + $SourceSha)
if (Test-Path -LiteralPath $destination) { throw 'Output already exists: refuse overwrite.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('m-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $root = Join-Path $temp 'r'
    # Git's object SHA, not a ZIP folder name, authenticates the exact source.
    # The repository exists only in this throwaway GUID temp directory and
    # is removed by the enclosing finally; no permanent local repository.
    & $gitPath clone --quiet --no-checkout --filter=blob:none 'https://github.com/lxsdd/foo_dj_library_bridge.git' $root
    if ($LASTEXITCODE -ne 0) { throw 'Private SHA-pinned source clone failed.' }
    & $gitPath -C $root checkout --quiet --detach $SourceSha
    if ($LASTEXITCODE -ne 0) { throw 'Requested exact source commit unavailable.' }
    $actual = (& $gitPath -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -cne $SourceSha) {
        throw 'Exact source Git object identity mismatch.'
    }
    $projectLicenseBlob = (& $gitPath -C $root hash-object LICENSE).Trim()
    if ($LASTEXITCODE -ne 0 -or
        $projectLicenseBlob -cne 'b9998241259c5cc30a512ae25257409c48319f9a') {
        throw 'Owner-approved MIT plus Commons Clause license mismatch.'
    }
    Write-Host "LOCAL_ACCEPTANCE_SOURCE_SHA_VERIFIED=PASS sha=$actual"
    foreach ($f in @('LICENSE','scripts\build.ps1','scripts\package-component.ps1',
                     'scripts\bootstrap-sdk.ps1','VERSION','foo_dj_library_bridge.sln')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $f) -PathType Leaf)) {
            throw "Pinned source missing $f"
        }
    }
    $build = Join-Path $root 'scripts\build.ps1'
    & $build -Platform Win32 -Configuration Release -PlatformToolset $selectedToolset
    if ($LASTEXITCODE -ne 0) { throw 'Win32 build failed.' }
    & $build -Platform x64 -Configuration Release -PlatformToolset $selectedToolset
    if ($LASTEXITCODE -ne 0) { throw 'x64 build failed.' }
    $dll32 = Join-Path $root 'out\Win32\Release\foo_dj_library_bridge.dll'
    $dll64 = Join-Path $root 'out\x64\Release\foo_dj_library_bridge.dll'
    foreach ($p in @($dll32,$dll64)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing compiled DLL $p" }
    }
    $version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.-]+)?$') {
        throw 'Unexpected version string.'
    }
    $stage = Join-Path $temp 'package'
    & (Join-Path $root 'scripts\package-component.ps1') -Win32Dll $dll32 -X64Dll $dll64 -OutputDirectory $stage -Version $version -Commit $SourceSha
    $file = Join-Path $stage ("foo_dj_library_bridge-" + $version + ".fb2k-component")
    $manifest = Join-Path $stage 'BUILD-MANIFEST.txt'
    $sums = Join-Path $stage 'SHA256SUMS.txt'
    foreach ($p in @($file,$manifest,$sums)) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'Incomplete package.' }
    }
    $proof = Get-Content -LiteralPath $manifest -Raw
    foreach ($value in @("commit=$SourceSha",'root_dll_machine=0x014C',
                         'x64_dll_machine=0x8664','status=PASS')) {
        if (-not $proof.Contains($value)) { throw "Missing manifest proof: $value" }
    }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecar = (Get-Content -LiteralPath $sums -Raw).Trim()
    if (-not $sidecar.StartsWith($hash + '  ')) { throw 'SHA256 sidecar mismatch.' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    if (Test-Path -LiteralPath $destination) { throw 'Destination appeared; refuse overwrite.' }
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -LiteralPath $file,$manifest,$sums -Destination $destination
    $copiedHash = (Get-FileHash -LiteralPath (Join-Path $destination (Split-Path -Leaf $file)) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($copiedHash -ne $hash) { throw 'Local copy checksum mismatch.' }
    Write-Host "LOCAL_ACCEPTANCE_BUILD=PASS PATH=$destination SOURCE_SHA=$SourceSha SHA256=$hash TOOLSET=$selectedToolset"
    Write-Host 'No installation, tag/database/music writes or public GitHub binary artifacts.'
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
    }
}
