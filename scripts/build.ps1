param(
    [ValidateSet('Win32','x64')] [string]$Platform = 'x64',
    [ValidateSet('Debug','Release')] [string]$Configuration = 'Release',
    [ValidateSet('v143','v145')] [string]$PlatformToolset = 'v143'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'bootstrap-sdk.ps1')
$MsBuild = (Get-Command msbuild.exe -ErrorAction SilentlyContinue).Source
if (-not $MsBuild) { throw 'MSBuild not found. Run from a Visual Studio Developer PowerShell or install Visual Studio 2022 C++ tools.' }
# SDK 2026-10-01 requires C++20 and supports VS2022/2026. The source is pinned to the owner's verified exact SDK Git tree.
# Require a specifically selected, CI-qualified toolset (v143 or v145).
# Forward the global MSBuild property to the SDK project references so the
# project and its dependencies use the identical selected compiler family.
& $MsBuild (Join-Path $Root 'foo_dj_library_bridge.sln') /m /p:Configuration=$Configuration /p:Platform=$Platform /p:PlatformToolset=$PlatformToolset /restore
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed with exit code $LASTEXITCODE" }
