#requires -Version 7.2
# Purely observational external-CUE acceptance. A default foobar profile can
# exclude *.cue from Media Library. Do NOT mark this as virtual-track PASS
# unless actual nonzero-subsong handles are observed in Bridge gzip.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ProfileDirectory,
 [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture,
 [Parameter(Mandatory)][string]$MediaDirectory,
 [Parameter(Mandatory)][long]$BeforeGeneration
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
 throw 'External CUE qualification limited to isolated CI Windows hosts.'
}
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/')+
    [IO.Path]::DirectorySeparatorChar
foreach($path in @($ProfileDirectory,$MediaDirectory)) {
 if (-not [IO.Path]::GetFullPath($path).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Refusing external cue probe outside isolated runner temp.'
 }
}
$backing=Join-Path $MediaDirectory 'Synthetic CUE image.wav'
$cuePath=Join-Path $MediaDirectory 'Synthetic CUE image.cue'
if ((Test-Path -LiteralPath $cuePath) -or (Test-Path -LiteralPath $backing)) {
 throw 'Refusing to overwrite an existing CUE fixture.'
}
function New-CueBackingWave {
 $fs=[IO.File]::Open($backing,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
 try {
  $bytes=352800 # 4 seconds, mono PCM 44.1k, 16-bit
  $w=[IO.BinaryWriter]::new($fs)
  try {
   $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
   $w.Write([int](36+$bytes))
   $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
   $w.Write([int]16);$w.Write([short]1);$w.Write([short]1)
   $w.Write([int]44100);$w.Write([int]88200)
   $w.Write([short]2);$w.Write([short]16)
   $w.Write([Text.Encoding]::ASCII.GetBytes('data'))
   $w.Write([int]$bytes)
   $w.Write([byte[]]::new($bytes))
  } finally {$w.Dispose()}
 } finally {$fs.Dispose()}
}
$stateFile=Join-Path (Join-Path $ProfileDirectory 'foo_dj_library_bridge') 'bridge-state.tsv'
$payload=Join-Path (Join-Path $ProfileDirectory 'foo_dj_library_bridge') 'digital-items.tsv.gz'
function Read-ActualSnapshot {
 $state=@{}
 foreach($l in (Get-Content -LiteralPath $stateFile -Encoding UTF8)) {
  $p=$l.Split([char]9,2)
  if ($p.Count -eq 2) { $state[$p[0]]=$p[1] }
 }
 if ($state.complete -ne '1') {return $null}
 $f=[IO.File]::OpenRead($payload)
 try {
  $gz=[IO.Compression.GZipStream]::new($f,[IO.Compression.CompressionMode]::Decompress)
  try {
   $r=[IO.StreamReader]::new($gz)
   try {$txt=$r.ReadToEnd()}
   finally {$r.Dispose()}
  } finally {$gz.Dispose()}
 } finally {$f.Dispose()}
 $all=@($txt.Split([char]10) | Where-Object {$_.Length -gt 0})
 if ($all.Count -lt 1 -or @($all[0].Split([char]9)).Count -ne 26) {
  throw 'CUE discovery saw invalid Bridge header.'
 }
 $rows=@()
 foreach($line in @($all | Select-Object -Skip 1)) {
  $cells=@($line.Split([char]9))
  if ($cells.Count -ne 26) {throw 'CUE discovery saw invalid Bridge row.'}
  $rows+= ,$cells
 }
 if ($rows.Count -ne [int]$state.item_count) {
  throw 'CUE discovery found inconsistent complete snapshot row count.'
 }
 return @{generation=[long]$state.generation; rows=$rows}
}
New-CueBackingWave
Write-Host "BRIDGE_CUE_BACKING_WAV_$Architecture=PASS"
# A caller must wait for the genuine Media Library ADD of the standalone
# backing file first, before the external .cue appears.
$deadline=[DateTime]::UtcNow.AddSeconds(30)
$backingGeneration=0L
while([DateTime]::UtcNow -lt $deadline) {
 try {
  $snap=Read-ActualSnapshot
  if ($null -ne $snap -and $snap.generation -gt $BeforeGeneration -and
      $snap.rows.Count -eq 2 -and
      @($snap.rows | Where-Object {[IO.Path]::GetFileName($_[0]) -ceq 'Synthetic CUE image.wav'}).Count -eq 1) {
   $backingGeneration=$snap.generation
   break
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 300
}
if ($backingGeneration -eq 0) {throw 'foobar did not import synthetic physical CUE backing WAV.'}
Write-Host "BRIDGE_CUE_BACKING_REAL_LIBRARY_$Architecture=PASS"
$cueText=@'
PERFORMER "Bridge CI"
TITLE "Synthetic Virtual Album"
FILE "Synthetic CUE image.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Virtual Cue Part One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Virtual Cue Part Two"
    INDEX 01 00:02:00
'@
[IO.File]::WriteAllText($cuePath,$cueText,[Text.Encoding]::ASCII)
Write-Host "BRIDGE_EXTERNAL_CUE_VALID_FIXTURE_$Architecture=PASS"
$virtualObserved=$false
$readableVirtualTracks=0
$observedVirtual=@()
$lastCueGeneration=$backingGeneration
# No *.cue exclusion changes yet. Observational discovery only.
$monitorUntil=[DateTime]::UtcNow.AddSeconds(7)
while([DateTime]::UtcNow -lt $monitorUntil) {
 try {
  $snap=Read-ActualSnapshot
  if ($null -ne $snap) {
   if ($snap.generation -gt $lastCueGeneration) {$lastCueGeneration=$snap.generation}
   $virtual=@($snap.rows | Where-Object {
    [int]($_[1]) -gt 0 -or ($_[4] -like 'Virtual Cue Part *')
   })
   if ($virtual.Count -gt 0) {
    $virtualObserved=$true
    $readableVirtualTracks=$virtual.Count
    $observedVirtual=$virtual
    break
   }
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 300
}
if (-not $virtualObserved) {
 throw 'External CUE enabled but no virtual subsongs reached the real Bridge snapshot.'
}
if ($readableVirtualTracks -ne 2) {
 throw "External two-track CUE exposed $readableVirtualTracks handles instead of two."
}
$cueTitles=@($observedVirtual | ForEach-Object { $_[4] } | Sort-Object)
if ($cueTitles.Count -ne 2 -or
    $cueTitles[0] -cne 'Virtual Cue Part One' -or
    $cueTitles[1] -cne 'Virtual Cue Part Two') {
 throw 'Real foobar CUE track title metadata differs from fixture.'
}
$cueIdentities=[System.Collections.Generic.HashSet[string]]::new(
 [StringComparer]::OrdinalIgnoreCase)
foreach($v in $observedVirtual) {
 $sub=[int]0
 if (-not [int]::TryParse($v[1],[ref]$sub) -or $sub -lt 0) {
  throw 'CUE virtual track exposed an invalid subsong index.'
 }
 if ($v[0] -notlike '*Synthetic CUE image*' -or
     $v[23] -notmatch '^[a-f0-9]{16}$' -or
     -not $cueIdentities.Add($v[0] + [char]9 + $v[1])) {
  throw 'CUE virtual track source identity or fingerprint mismatch.'
 }
 $seconds=[double]0
 if (-not [double]::TryParse(
       $v[19],[Globalization.NumberStyles]::Float,
       [Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -or
     [math]::Abs($seconds-2.0) -gt 0.025) {
  throw 'CUE virtual track duration differs from expected 2 seconds.'
 }
 Write-Host "BRIDGE_EXTERNAL_CUE_TRACK_$Architecture=PASS subsong:$sub title:$($v[4]) duration:2"
}
Write-Host "BRIDGE_EXTERNAL_CUE_AUTOINDEX_$Architecture=PASS count=$readableVirtualTracks"
Write-Host "BRIDGE_EXTERNAL_CUE_VIRTUAL_METADATA_$Architecture=PASS"
# Remove only newly created runner fixture files. The original test's 2s WAV
# must survive and will be qualified after this cleanup plus host restart.
Remove-Item -LiteralPath $cuePath -Force -ErrorAction Stop
Remove-Item -LiteralPath $backing -Force -ErrorAction Stop
$cleanupDeadline=[DateTime]::UtcNow.AddSeconds(40)
$clean=$false
while([DateTime]::UtcNow -lt $cleanupDeadline) {
 try {
  $snap=Read-ActualSnapshot
  if ($null -ne $snap -and $snap.generation -gt $backingGeneration -and
      $snap.rows.Count -eq 1 -and
      [IO.Path]::GetFileName($snap.rows[0][0]) -ceq 'Synthetic 01.wav') {
   $clean=$true
   break
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 350
}
if (-not $clean) {throw 'CUE fixture cleanup not reflected by actual foobar Media Library.'}
Write-Host "BRIDGE_EXTERNAL_CUE_CLEANUP_$Architecture=PASS"
Write-Host "BRIDGE_EXTERNAL_CUE_OBSERVATION_$Architecture=PASS"


# MULTI-FILE CUE DISCOVERY — separate from already qualified single-WAV CUE.
# A multi-file sheet references different physical WAV paths; inspect exactly
# what real foobar handed over, rather than assuming virtual identity values.
$multiA=Join-Path $MediaDirectory 'Synthetic Multi A.wav'
$multiB=Join-Path $MediaDirectory 'Synthetic Multi B.wav'
$multiCue=Join-Path $MediaDirectory 'Synthetic Multi.cue'
foreach ($p in @($multiA,$multiB,$multiCue)) {
 if (Test-Path -LiteralPath $p) { throw 'Refusing to overwrite multi-file CUE fixtures.' }
}
function New-MultiCueWave([string]$Target,[int]$Seconds) {
 $length=88200*$Seconds
 $fs=[IO.File]::Open($Target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
 try {
  $w=[IO.BinaryWriter]::new($fs)
  try {
   $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
   $w.Write([int](36+$length))
   $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
   $w.Write([int]16);$w.Write([short]1);$w.Write([short]1)
   $w.Write([int]44100);$w.Write([int]88200)
   $w.Write([short]2);$w.Write([short]16)
   $w.Write([Text.Encoding]::ASCII.GetBytes('data'))
   $w.Write([int]$length)
   $w.Write([byte[]]::new($length))
  } finally {$w.Dispose()}
 } finally {$fs.Dispose()}
}
$priorSnap=Read-ActualSnapshot
if ($null -eq $priorSnap -or $priorSnap.rows.Count -ne 1) {
 throw 'External CUE cleanup left an unexpected baseline before multi-file test.'
}
$baselineGen=$priorSnap.generation
New-MultiCueWave -Target $multiA -Seconds 1
New-MultiCueWave -Target $multiB -Seconds 2
$twoBackingDeadline=[DateTime]::UtcNow.AddSeconds(45)
$twoBackingGen=0L
while ([DateTime]::UtcNow -lt $twoBackingDeadline) {
 try {
  $snap=Read-ActualSnapshot
  if ($null -ne $snap -and $snap.generation -gt $baselineGen -and
      $snap.rows.Count -eq 3) {
   $backingNames=@($snap.rows | ForEach-Object { [IO.Path]::GetFileName($_[0]) })
   if ($backingNames -contains 'Synthetic Multi A.wav' -and
       $backingNames -contains 'Synthetic Multi B.wav' -and
       $backingNames -contains 'Synthetic 01.wav') {
    $twoBackingGen=$snap.generation
    break
   }
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 350
}
if ($twoBackingGen -eq 0) { throw 'Real foobar Media Library failed to index both multi-file WAV sources.' }
Write-Host "BRIDGE_MULTI_CUE_PHYSICAL_SOURCES_$Architecture=PASS count=2"
$multiContent=@'
PERFORMER "Bridge CI"
TITLE "Synthetic Multi-File Album"
FILE "Synthetic Multi A.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Multi File Cue Alpha"
    INDEX 01 00:00:00
FILE "Synthetic Multi B.wav" WAVE
  TRACK 02 AUDIO
    TITLE "Multi File Cue Beta"
    INDEX 01 00:00:00
'@
[IO.File]::WriteAllText($multiCue,$multiContent,[Text.Encoding]::ASCII)
Write-Host "BRIDGE_MULTI_CUE_FIXTURE_$Architecture=PASS"
$multiFound=$false
$multiRows=@()
$lastObservedGen=$twoBackingGen
$until=[DateTime]::UtcNow.AddSeconds(10)
while([DateTime]::UtcNow -lt $until) {
 try {
  $snap=Read-ActualSnapshot
  if($null -ne $snap) {
   $lastObservedGen=[math]::Max($lastObservedGen,$snap.generation)
   $multiRows=@($snap.rows | Where-Object {
     $_[4] -in @('Multi File Cue Alpha','Multi File Cue Beta')
   })
   if($multiRows.Count -eq 2) { $multiFound=$true; break }
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 300
}
if (-not $multiFound -or $multiRows.Count -ne 2) {
 throw 'Real foobar did not expose two distinct virtual subsongs from the two-file CUE.'
}
$multiExpected=@{
 'Multi File Cue Alpha'=@{Subsong=1;Duration=1}
 'Multi File Cue Beta'=@{Subsong=2;Duration=2}
}
$seenMulti=[System.Collections.Generic.HashSet[string]]::new(
 [StringComparer]::OrdinalIgnoreCase)
$seenMultiFingerprints=[System.Collections.Generic.HashSet[string]]::new(
 [StringComparer]::OrdinalIgnoreCase)
foreach($row in $multiRows) {
 $title=$row[4]
 if (-not $multiExpected.ContainsKey($title)) {
  throw 'Unknown title from real multi-file CUE.'
 }
 $expected=$multiExpected[$title]
 $actualSubsong=[int]0
 if (-not [int]::TryParse($row[1],[ref]$actualSubsong) -or
     $actualSubsong -ne $expected.Subsong) {
  throw "Incorrect subtrack index for multi-file cue: $title"
 }
 if ([IO.Path]::GetFileName($row[0]) -cne 'Synthetic Multi.cue' -or
     -not $seenMulti.Add($row[0] + [char]9 + $row[1]) -or
     $row[23] -notmatch '^[a-f0-9]{16}$' -or
     -not $seenMultiFingerprints.Add($row[23])) {
  throw 'Multi-file CUE virtual identity/fingerprint collision.'
 }
 $actualDuration=[double]0
 if (-not [double]::TryParse(
   $row[19],[Globalization.NumberStyles]::Float,
   [Globalization.CultureInfo]::InvariantCulture,[ref]$actualDuration) -or
   [math]::Abs($actualDuration-$expected.Duration) -gt 0.025) {
  throw "Multi-file CUE virtual duration mismatch: $title"
 }
 Write-Host "BRIDGE_MULTI_CUE_TRACK_$Architecture=PASS title:$title subsong:$actualSubsong duration:$actualDuration"
}
Write-Host "BRIDGE_MULTI_CUE_VIRTUAL_TRACKS_$Architecture=PASS count=2"
Write-Host "BRIDGE_MULTI_CUE_IDENTITY_$Architecture=PASS distinct_source_subsong_and_fingerprint"
Remove-Item -LiteralPath $multiCue -Force -ErrorAction Stop
Remove-Item -LiteralPath $multiA -Force -ErrorAction Stop
Remove-Item -LiteralPath $multiB -Force -ErrorAction Stop
$cleanupDeadline=[DateTime]::UtcNow.AddSeconds(45)
$cleanupConfirmed=$false
while ([DateTime]::UtcNow -lt $cleanupDeadline) {
 try {
  $snap=Read-ActualSnapshot
  if ($null -ne $snap -and $snap.generation -gt $twoBackingGen -and
      $snap.rows.Count -eq 1 -and
      [IO.Path]::GetFileName($snap.rows[0][0]) -ceq 'Synthetic 01.wav') {
   $cleanupConfirmed=$true
   break
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 350
}
if (-not $cleanupConfirmed) {
 throw 'foobar did not remove all temporary multi-file CUE WAV/virtual rows.'
}
Write-Host "BRIDGE_MULTI_CUE_CLEANUP_$Architecture=PASS"
Write-Host "BRIDGE_MULTI_CUE_OBSERVATION_$Architecture=PASS"
