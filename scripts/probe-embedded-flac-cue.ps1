#requires -Version 7.2
# Real in-process foobar Media Library acceptance for FLAC Vorbis-comment
# CUESHEET embedding. Only generated silent audio under GitHub RUNNER_TEMP.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ProfileDirectory,
 [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture,
 [Parameter(Mandatory)][string]$MediaDirectory,
 [Parameter(Mandatory)][long]$BeforeGeneration
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
 throw 'Embedded FLAC test requires isolated public GitHub Windows runner.'
}
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/') +
 [IO.Path]::DirectorySeparatorChar
foreach ($v in @($ProfileDirectory,$MediaDirectory)) {
 if (-not [IO.Path]::GetFullPath($v).StartsWith(
      $temp,[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Refusing embedded FLAC test outside ephemeral Windows runner temp.'
 }
}
$work=Join-Path $env:RUNNER_TEMP ("embedded-flac-bridge-$Architecture-" + $env:GITHUB_RUN_ID)
if (Test-Path -LiteralPath $work) {throw 'Refusing to reuse FLAC test working directory.'}
New-Item -ItemType Directory -Path $work | Out-Null
$flacName='Synthetic Embedded.flac'
$generated=Join-Path $work $flacName
$active=Join-Path $MediaDirectory $flacName
if (Test-Path -LiteralPath $active) {throw 'Refusing to overwrite an existing FLAC.'}
if (Test-Path -LiteralPath (Join-Path $MediaDirectory 'Synthetic Embedded.cue')) {
 throw 'External .cue file unexpectedly present in embedded-only fixture.'
}
# Python is part of the runner image; no third-party encoder/download.
& python (Join-Path $PSScriptRoot 'generate-embedded-flac-fixture.py') $generated
if ($LASTEXITCODE -ne 0) {throw 'Source-only synthetic FLAC generator failed.'}
& python (Join-Path $PSScriptRoot 'verify-embedded-flac-fixture.py') $generated
if ($LASTEXITCODE -ne 0) {
 throw 'Independent lossless FLAC/embedded CUESHEET check failed before foobar.'
}
Write-Host "BRIDGE_EMBEDDED_FLAC_INDEPENDENT_VERIFICATION_$Architecture=PASS"
$bytes=[IO.File]::ReadAllBytes($generated)
if ($bytes.Length -lt 1024 -or
    [Text.Encoding]::ASCII.GetString($bytes,0,4) -cne 'fLaC') {
 throw 'Generated silent FLAC stream lacks fLaC magic.'
}
# Independently inspect the native FLAC VORBIS_COMMENT metadata block.
# The cue text must be present in that block, NOT merely somewhere in the
# encoded audio or in a neighboring external file.
$offset=4
$cueTags=[System.Collections.Generic.List[string]]::new()
$blockSeen=$false
$done=$false
while (-not $done) {
 if ($offset+4 -gt $bytes.Length) {throw 'Truncated FLAC metadata header.'}
 $first=[int]$bytes[$offset]
 $done=(($first -band 128) -ne 0)
 $type=$first -band 127
 $size=([int]$bytes[$offset+1] -shl 16) -bor
       ([int]$bytes[$offset+2] -shl 8) -bor [int]$bytes[$offset+3]
 $start=$offset+4
 $end=$start+$size
 if ($end -gt $bytes.Length) {throw 'Truncated FLAC metadata block.'}
 if ($type -eq 4) {
  if ($blockSeen) {throw 'Unexpected repeated VORBIS_COMMENT block.'}
  $blockSeen=$true
  $pos=$start
  if ($pos+4 -gt $end) {throw 'Invalid vendor field.'}
  $vendorLength=[int][BitConverter]::ToUInt32($bytes,$pos)
  $pos+=4+$vendorLength
  if ($pos+4 -gt $end) {throw 'Invalid FLAC comment count.'}
  $count=[int][BitConverter]::ToUInt32($bytes,$pos)
  $pos+=4
  if ($count -gt 32) {throw 'Unexpected huge FLAC comment count.'}
  for ($i=0; $i -lt $count; $i++) {
   if ($pos+4 -gt $end) {throw 'Invalid FLAC tag length.'}
   $len=[int][BitConverter]::ToUInt32($bytes,$pos)
   $pos+=4
   if ($len -lt 0 -or $pos+$len -gt $end) {
    throw 'FLAC comment exceeds metadata block.'
   }
   $tag=[Text.Encoding]::UTF8.GetString($bytes,$pos,$len)
   $pos+=$len
   if ($tag.StartsWith('CUESHEET=',[StringComparison]::OrdinalIgnoreCase)) {
    $cueTags.Add($tag.Substring(9))
   }
  }
  if ($pos -ne $end) {throw 'FLAC Vorbis metadata trailing bytes.'}
 }
 $offset=$end
}
if (-not $blockSeen -or $cueTags.Count -ne 1 -or
    $cueTags[0] -notmatch 'TRACK 01 AUDIO' -or
    $cueTags[0] -notmatch 'TRACK 02 AUDIO' -or
    $cueTags[0] -notmatch 'Embedded Alpha' -or
    $cueTags[0] -notmatch 'Embedded Beta') {
 throw 'Required two-track foobar CUESHEET not embedded in FLAC Vorbis metadata.'
}
Write-Host "BRIDGE_EMBEDDED_FLAC_VALID_VORBIS_CUE_$Architecture=PASS"
$stateFile=Join-Path (Join-Path $ProfileDirectory 'foo_dj_library_bridge') 'bridge-state.tsv'
$gzipFile=Join-Path (Join-Path $ProfileDirectory 'foo_dj_library_bridge') 'digital-items.tsv.gz'
function Read-EmbeddedHostSnapshot {
 $raw=Get-Content -Raw -LiteralPath $stateFile -Encoding UTF8
 $state=@{}
 foreach ($line in ($raw -split "\r?\n")) {
  if (-not $line) {continue}
  $p=$line.Split([char]9,2)
  if ($p.Count -eq 2) {$state[$p[0]]=$p[1]}
 }
 if ($state.complete -ne '1' -or $state.schema_version -ne '3') {return $null}
 $file=[IO.File]::OpenRead($gzipFile)
 try {
  $gzip=[IO.Compression.GZipStream]::new($file,[IO.Compression.CompressionMode]::Decompress)
  try {
   $reader=[IO.StreamReader]::new($gzip,[Text.UTF8Encoding]::new($false))
   try {$txt=$reader.ReadToEnd()} finally {$reader.Dispose()}
  } finally {$gzip.Dispose()}
 } finally {$file.Dispose()}
 $after=Get-Content -Raw -LiteralPath $stateFile -Encoding UTF8
 if ($after -cne $raw) {return $null}
 $lines=@($txt.Split([char]10) | Where-Object {$_.Length -gt 0})
 if ($lines.Count -eq 0 -or @($lines[0].Split([char]9)).Count -ne 26) {
  throw 'Embedded FLAC Bridge snapshot has invalid v3 26-column header.'
 }
 $records=@()
 foreach ($line in @($lines | Select-Object -Skip 1)) {
  $v=@($line.Split([char]9))
  if ($v.Count -ne 26) {throw 'Invalid Bridge FLAC record width.'}
  $records+= ,$v
 }
 if ($records.Count -ne [int]$state.item_count) {
  throw 'Incomplete embedded FLAC snapshot row count.'
 }
 return @{ Generation=[long]$state.generation; Rows=$records }
}
$prior=Read-EmbeddedHostSnapshot
if ($null -eq $prior -or $prior.Rows.Count -ne 1 -or
    $prior.Generation -lt $BeforeGeneration) {
 throw 'Baseline Media Library must contain exactly one original synthetic WAV.'
}
# Establish the FLAC content baseline after generation and before foobar
# observes its metadata; only our synthetic file is in scope.
$generatedFlacHash=(Get-FileHash -LiteralPath $generated -Algorithm SHA256).Hash
Move-Item -LiteralPath $generated -Destination $active -ErrorAction Stop
Write-Host "BRIDGE_EMBEDDED_FLAC_FIXTURE_ADDED_$Architecture=PASS"
$deadline=[DateTime]::UtcNow.AddSeconds(35)
$lastGen=$prior.Generation
$found=$false
$observed=@()
while ([DateTime]::UtcNow -lt $deadline) {
 try {
  $snap=Read-EmbeddedHostSnapshot
  if ($null -ne $snap -and $snap.Generation -gt $prior.Generation) {
   $lastGen=[math]::Max($lastGen,$snap.Generation)
   $virtual=@($snap.Rows | Where-Object {
    $_[4] -in @('Embedded Alpha','Embedded Beta')
   })
   if ($virtual.Count -eq 2) {
    $observed=$virtual
    $found=$true
    break
   }
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 350
}
if (-not $found) {
 Write-Host "BRIDGE_EMBEDDED_FLAC_DIAGNOSTIC_$Architecture=last_generation:$lastGen"
 $snap=Read-EmbeddedHostSnapshot
 if ($null -ne $snap) {
  foreach ($r in $snap.Rows) {
   $safe=if ($r[4] -in @('Embedded Alpha','Embedded Beta')) {$r[4]} else {'other'}
   Write-Host "BRIDGE_EMBEDDED_FLAC_ROW_$Architecture=ext:$([IO.Path]::GetExtension($r[0])) subsong:$($r[1]) title:$safe"
  }
 }
 throw 'Real foobar did not index two virtual subsongs from the embedded FLAC Vorbis CUESHEET.'
}
# This isolated FLAC has only virtual foobar handles 1 and 2. No
# invented file-level subsong-0 row may be published for this path: that
# would appear to authorize an unverified Rekordbox ContentID candidate.
# Inspect the *complete actual Media Library snapshot*, not the two-title
# subset, so an unexpected third row cannot hide behind the title filter.
$cueSourceRows=@($snap.Rows | Where-Object {
 [IO.Path]::GetFileName($_[0]) -ceq $flacName
})
if ($cueSourceRows.Count -ne 2 -or
    @($cueSourceRows | Where-Object {[int]($_[1]) -eq 0}).Count -ne 0) {
 throw 'Embedded FLAC virtual-only source unexpectedly acquired a physical subsong-0 or extra Bridge row.'
}
Write-Host "BRIDGE_EMBEDDED_FLAC_VIRTUAL_ONLY_SOURCE_$Architecture=PASS count=2"
$expected=@{'Embedded Alpha'=1;'Embedded Beta'=2}
$identities=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$fingerprints=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $observed) {
 $duration=[double]0
 $subsong=[int]0
 if ([IO.Path]::GetFileName($r[0]) -cne $flacName -or
     -not [int]::TryParse($r[1],[ref]$subsong) -or
     $subsong -ne $expected[$r[4]] -or
     -not [double]::TryParse($r[19],[Globalization.NumberStyles]::Float,
             [Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -or
     [math]::Abs($duration-2.0) -gt 0.025 -or
     $r[23] -notmatch '^[a-f0-9]{16}$' -or
     -not $identities.Add($r[0]+[char]9+$r[1]) -or
     -not $fingerprints.Add($r[23])) {
  throw "Embedded FLAC virtual track identity, subsong, duration or fingerprint mismatch for $($r[4])."
 }
 Write-Host "BRIDGE_EMBEDDED_FLAC_VIRTUAL_TRACK_$Architecture=PASS title:$($r[4]) subsong:$subsong duration:2"
}
Write-Host "BRIDGE_EMBEDDED_FLAC_VIRTUAL_TRACKS_$Architecture=PASS count=2"
Write-Host "BRIDGE_EMBEDDED_FLAC_IDENTITY_$Architecture=PASS"
if (-not (Test-Path -LiteralPath $active -PathType Leaf) -or
    (Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -cne $generatedFlacHash) {
 throw 'Actual foobar embedded-FLAC CUE scan unexpectedly modified synthetic audio bytes.'
}
Write-Host "BRIDGE_EMBEDDED_FLAC_AUDIO_READONLY_$Architecture=PASS"
# Remove ONLY our generated file from the isolated monitored folder and
# observe the real foobar Media Library/Bridge callback cleanup.
Remove-Item -LiteralPath $active -Force -ErrorAction Stop
$end=[DateTime]::UtcNow.AddSeconds(45)
$clean=$false
while ([DateTime]::UtcNow -lt $end) {
 try {
  $snap=Read-EmbeddedHostSnapshot
  if ($null -ne $snap -and $snap.Generation -gt $lastGen -and
      $snap.Rows.Count -eq 1 -and
      [IO.Path]::GetFileName($snap.Rows[0][0]) -ceq 'Synthetic 01.wav') {
   $clean=$true
   break
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 350
}
if (-not $clean) {throw 'Real foobar did not remove embedded FLAC virtual rows after deletion.'}
Write-Host "BRIDGE_EMBEDDED_FLAC_CLEANUP_$Architecture=PASS"
Write-Host "BRIDGE_EMBEDDED_FLAC_REAL_HOST_$Architecture=PASS"
