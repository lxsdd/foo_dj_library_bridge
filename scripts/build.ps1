param(
    [ValidateSet('Win32','x64')] [string]$Platform = 'x64',
    [ValidateSet('Debug','Release')] [string]$Configuration = 'Release',
    [string]$PlatformToolset = 'v143'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'bootstrap-sdk.ps1')
$MsBuild = (Get-Command msbuild.exe -ErrorAction SilentlyContinue).Source
if (-not $MsBuild) { throw 'MSBuild not found. Run from a Visual Studio Developer PowerShell or install Visual Studio 2022 C++ tools.' }
# The 2026-09-17 SDK declares C++20 and is documented by foobar2000 as VS2022/2026 compatible.
# Force the VS2022 v143 toolset as a global MSBuild property so the SDK project references
# do not require a newer toolset on GitHub's Windows runners.
& $MsBuild (Join-Path $Root 'foo_dj_library_bridge.sln') /m /p:Configuration=$Configuration /p:Platform=$Platform /p:PlatformToolset=$PlatformToolset /restore
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed with exit code $LASTEXITCODE" }
