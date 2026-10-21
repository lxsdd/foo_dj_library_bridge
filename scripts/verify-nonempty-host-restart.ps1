#requires -Version 7.2
# Check the real, restarted foobar host with the same populated disposable
# Media Library. No user profile or user music may be accessed.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ProfileDirectory,
 [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture,
 [ValidateRange(2,2)][int]$ProbeIteration=2
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
 throw 'Nonempty Media Library restart qualification requires isolated GitHub Windows CI.'
}
$profile=[IO.Path]::GetFullPath($ProfileDirectory)
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/') +
 [IO.Path]::DirectorySeparatorChar
if (-not $profile.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) {
 throw 'Refusing to inspect a non-disposable foobar profile.'
}
$dir=Join-Path $profile 'foo_dj_library_bridge'
$stateFile=Join-Path $dir 'bridge-state.tsv'
$gzipFile=Join-Path $dir 'digital-items.tsv.gz'
$errorFile=Join-Path $dir 'bridge-error.txt'
$deadline=[DateTime]::UtcNow.AddSeconds(60)
$lastState='NOT_CREATED'
while ([DateTime]::UtcNow -lt $deadline) {
 if (Test-Path -LiteralPath $errorFile -PathType Leaf) {
  throw 'Actual Bridge publisher reported an error on populated-profile restart.'
 }
 if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf) -or
     -not (Test-Path -LiteralPath $gzipFile -PathType Leaf)) {
  Start-Sleep -Milliseconds 350
  continue
 }
 try {
  $raw=Get-Content -Raw -LiteralPath $stateFile -Encoding UTF8
  $state=@{}
  foreach ($line in ($raw -split "\r?\n")) {
   if (-not $line) { continue }
   $pair=$line.Split([char]9,2)
   if ($pair.Count -ne 2 -or $state.ContainsKey($pair[0])) {
    throw 'Malformed restarted Bridge state marker.'
   }
   $state[$pair[0]]=$pair[1]
  }
  $lastState="$($state.generation),$($state.complete),$($state.item_count)"
  if ($state.schema_version -ne '3' -or $state.complete -ne '1' -or
      $state.item_count -ne '1' -or $state.producer_version -ne '0.1.0-rc4' -or
      [long]$state.generation -lt 6) {
   Start-Sleep -Milliseconds 350
   continue
  }
  $file=[IO.File]::OpenRead($gzipFile)
  try {
   $gzip=[IO.Compression.GZipStream]::new(
     $file,[IO.Compression.CompressionMode]::Decompress)
   try {
    $reader=[IO.StreamReader]::new($gzip,[Text.UTF8Encoding]::new($false))
    try { $body=$reader.ReadToEnd() }
    finally { $reader.Dispose() }
   } finally { $gzip.Dispose() }
  } finally { $file.Dispose() }
  $records=@($body.Split([char]10) | Where-Object { $_.Length -gt 0 })
  if ($records.Count -ne 2 -or @($records[0].Split([char]9)).Count -ne 26) {
   throw 'Populated foobar restart did not produce one schema-v3 row.'
  }
  $item=@($records[1].Split([char]9))
  if ($item.Count -ne 26 -or $item[1] -ne '0' -or
      [IO.Path]::GetFileName($item[0]) -cne 'Synthetic 01.wav' -or
      $item[0] -notlike '*bridge-ci-music*') {
   throw 'Populated restart lost the isolated original Media Library item.'
  }
  $duration=[double]0
  if (-not [double]::TryParse(
       $item[19],[Globalization.NumberStyles]::Float,
       [Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -or
      [math]::Abs($duration-2) -gt 0.02) {
   throw 'Restart lost the updated 2-second synthetic WAV duration.'
  }
  $after=Get-Content -Raw -LiteralPath $stateFile -Encoding UTF8
  if ($after -ne $raw) {
   Start-Sleep -Milliseconds 300
   continue
  }
  Write-Host "BRIDGE_REAL_LIBRARY_RESTART_$Architecture=PASS count=1 generation=$($state.generation)"
  Write-Host "BRIDGE_REAL_LIBRARY_MODIFIED_PERSISTED_$Architecture=PASS duration_seconds=$duration"
  Write-Host "FOOBAR_NONEMPTY_RESTART_$Architecture=PASS"
  return
 } catch [System.IO.IOException] {
  Start-Sleep -Milliseconds 300
 }
}
throw "Populated foobar restart did not commit a complete post-restart generation. Last state: $lastState"
