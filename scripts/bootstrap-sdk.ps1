$ErrorActionPreference = 'Stop'
$SdkVersion = '2026-09-17'
$Root = Split-Path -Parent $PSScriptRoot
$External = Join-Path $Root 'external'
$SdkRoot = Join-Path $External 'foobar2000-sdk'
if (Test-Path (Join-Path $SdkRoot 'foobar2000\SDK\foobar2000.h')) {
    Write-Host "foobar2000 SDK $SdkVersion already present."
    exit 0
}
New-Item -ItemType Directory -Force -Path $External | Out-Null
$Archive = Join-Path $External "SDK-$SdkVersion.7z"
# Official vendor transport occasionally refuses hosted Windows connections.
# Use the same vendor URL with bounded retries, then an alternate HTTPS
# client (curl.exe) on that SAME origin. Never accept an unpinned mirror.
$SdkUrl = "https://www.foobar2000.org/downloads/SDK-$SdkVersion.7z"
$downloaded = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Invoke-WebRequest -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 90 -ErrorAction Stop -Uri $SdkUrl -OutFile $Archive
        $downloaded = $true
        break
    } catch {
        Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
        if ($attempt -lt 3) {
            Write-Warning "Official SDK PowerShell connection failed ($attempt/3); retrying same host."
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}
if (-not $downloaded) {
    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    if (-not $curl) { throw 'Official SDK server unreachable with PowerShell, and curl.exe is not installed.' }
    Write-Host 'Trying same official SDK HTTPS URL with curl.exe; no mirror or unpinned version.'
    & $curl.Source --fail --silent --show-error --location --retry 2 --retry-all-errors --connect-timeout 20 --max-time 120 --output $Archive $SdkUrl
    if ($LASTEXITCODE -ne 0) { throw "Official SDK download failed using both HTTP clients (curl exit $LASTEXITCODE)." }
}
# Same immutable vendor-archive evidence as the separately qualified safety PR.
# Transport fallback is not permission to change the SDK bytes or version.
$ExpectedSize = 793742
$ExpectedSha256 = '24fa95ed66b42624f593fd4b94c5efb08ae81dfebb92b79fe69c8cd170961e48'
$ActualSize = (Get-Item -LiteralPath $Archive).Length
$ActualHash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualSize -ne $ExpectedSize -or $ActualHash -ne $ExpectedSha256) {
    throw "Official SDK integrity mismatch: $ActualSize bytes / $ActualHash."
}

$SevenZip = $null
$SevenZipCommand = Get-Command '7z.exe' -ErrorAction SilentlyContinue
if ($SevenZipCommand) {
    $SevenZip = $SevenZipCommand.Source
} else {
    $Candidate = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    if (Test-Path $Candidate) { $SevenZip = $Candidate }
}
if (-not $SevenZip) { throw '7-Zip not found.' }

New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null
& $SevenZip x $Archive "-o$SdkRoot" -y | Out-Host
if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed with exit code $LASTEXITCODE" }
if (-not (Test-Path (Join-Path $SdkRoot 'foobar2000\SDK\foobar2000.h'))) {
    throw 'SDK extraction did not produce the expected foobar2000/SDK/foobar2000.h path.'
}
Write-Host "Installed foobar2000 SDK $SdkVersion at $SdkRoot"
