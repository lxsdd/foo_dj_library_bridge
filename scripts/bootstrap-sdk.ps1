$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$SdkVersion = '2026-09-17'
# Confirmed against official vendor download on two separate GitHub Windows
# runners: run 39434344038, Win32 and x64, 2026-10-20.
$ExpectedSize = 793742
$ExpectedSHA256 = '24fa95ed66b42624f593fd4b94c5efb08ae81dfebb92b79fe69c8cd170961e48'
$Root = Split-Path -Parent $PSScriptRoot
$External = Join-Path $Root 'external'
$SdkRoot = Join-Path $External 'foobar2000-sdk'
$Entry = Join-Path $SdkRoot 'foobar2000\SDK\foobar2000.h'
$PinMarker = Join-Path $SdkRoot '.sdk-pin.sha256'
$Readme = Join-Path $SdkRoot 'sdk-readme.html'

# Avoid silently trusting local cached/unverified trees.
if (Test-Path -LiteralPath $SdkRoot) {
    if ((Test-Path -LiteralPath $Entry -PathType Leaf) -and
        (Test-Path -LiteralPath $Readme -PathType Leaf) -and
        (Test-Path -LiteralPath $PinMarker -PathType Leaf) -and
        ((Get-Content -LiteralPath $PinMarker -Raw).Trim() -eq $ExpectedSHA256) -and
        ((Get-Content -LiteralPath $Readme -Raw).Contains("foobar2000 SDK, version $SdkVersion"))) {
        Write-Host "PASS: verified cached SDK $SdkVersion."
        return
    }
    throw "Unqualified SDK already exists at $SdkRoot. Refusing overwrite; use a clean temporary source directory."
}

New-Item -ItemType Directory -Force -Path $External | Out-Null
$Archive = Join-Path $External "SDK-$SdkVersion.7z"
if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
    Invoke-WebRequest -UseBasicParsing -MaximumRedirection 5 -Uri "https://www.foobar2000.org/downloads/SDK-$SdkVersion.7z" -OutFile $Archive
}
$actualSize = (Get-Item -LiteralPath $Archive).Length
$actualHash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSize -ne $ExpectedSize -or $actualHash -ne $ExpectedSHA256) {
    throw "SDK integrity mismatch ($actualSize bytes / $actualHash); expected $ExpectedSize bytes / $ExpectedSHA256."
}

$command = Get-Command 7z.exe -ErrorAction SilentlyContinue
$SevenZip = if ($command) { $command.Source } else { Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) {
    throw '7-Zip 7z.exe required for pinned SDK integrity and extraction.'
}
& $SevenZip t $Archive | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Pinned official SDK archive failed 7-Zip integrity check.' }

$Stage = Join-Path $External ("sdk-" + [guid]::NewGuid().ToString('N') + '-staging')
New-Item -ItemType Directory -Path $Stage | Out-Null
try {
    & $SevenZip x $Archive "-o$Stage" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK extraction failed.' }
    foreach ($file in @('foobar2000\SDK\foobar2000.h', 'sdk-readme.html',
                        'sdk-license.txt', 'pfc\pfc-license.txt',
                        'libPPUI\libPPUI-license.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Stage $file) -PathType Leaf)) {
            throw "Official SDK archive missing required file $file"
        }
    }
    $readme = Get-Content -LiteralPath (Join-Path $Stage 'sdk-readme.html') -Raw
    if (-not $readme.Contains("foobar2000 SDK, version $SdkVersion")) {
        throw 'SDK readme version mismatch.'
    }
    Set-Content -LiteralPath (Join-Path $Stage '.sdk-pin.sha256') -Value $ExpectedSHA256 -Encoding ascii -NoNewline
    Move-Item -LiteralPath $Stage -Destination $SdkRoot
    Write-Host "PASS: pinned foobar2000 SDK $SdkVersion / SHA256 $ExpectedSHA256"
} finally {
    if (Test-Path -LiteralPath $Stage) {
        Remove-Item -LiteralPath $Stage -Force -Recurse -ErrorAction SilentlyContinue
    }
}
