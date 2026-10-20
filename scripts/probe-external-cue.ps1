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
 foreach($l in Get-Content -LiteralPath $stateFile -Encoding UTF8) {
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
    break
   }
  }
 } catch [IO.IOException] {}
 Start-Sleep -Milliseconds 300
}
if ($virtualObserved) {
 Write-Host "BRIDGE_EXTERNAL_CUE_AUTOINDEX_$Architecture=VIRTUAL_TRACKS_OBSERVED count=$readableVirtualTracks"
} else {
 Write-Host "BRIDGE_EXTERNAL_CUE_AUTOINDEX_$Architecture=NOT_OBSERVED_IN_DEFAULT_LIBRARY"
}
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
