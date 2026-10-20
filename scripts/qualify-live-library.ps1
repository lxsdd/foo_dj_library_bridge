#requires -Version 7.2
# Synthetic, isolated foobar Media Library acceptance. No user media touched.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ProfileDirectory,
 [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture,
 [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Picker,
 [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$FirstWindow,
 [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Preferences,
 [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$FolderEdit,
 [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$SelectButton,
 [Parameter(Mandatory)][System.Windows.Automation.PropertyCondition]$PickerCondition
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { throw 'Ephemeral Windows GitHub Actions only.' }
$profile = [IO.Path]::GetFullPath($ProfileDirectory)
$temp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/') + [IO.Path]::DirectorySeparatorChar
if (-not $profile.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing non-disposable profile.' }
function New-SilentWave([string]$Path,[int]$Seconds) {
 $length=88200*$Seconds
 $fs=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write)
 try {
  $w=[IO.BinaryWriter]::new($fs)
  try {
   $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
   $w.Write([int](36+$length))
   $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
   $w.Write([int]16)
   $w.Write([short]1)
   $w.Write([short]1)
   $w.Write([int]44100)
   $w.Write([int]88200)
   $w.Write([short]2)
   $w.Write([short]16)
   $w.Write([Text.Encoding]::ASCII.GetBytes('data'))
   $w.Write([int]$length)
   $w.Write([byte[]]::new($length))
  } finally { $w.Dispose() }
 } finally { $fs.Dispose() }
}
$mediaDir=Join-Path (Split-Path -Parent (Split-Path -Parent $profile)) 'bridge-ci-music'
if (Test-Path -LiteralPath $mediaDir) { throw 'Refusing to reuse test media directory.' }
New-Item -ItemType Directory -Path $mediaDir -ErrorAction Stop | Out-Null
$first=Join-Path $mediaDir 'Synthetic 01.wav'
$second=Join-Path $mediaDir 'Synthetic 02.wav'
New-SilentWave -Path $first -Seconds 1
Write-Host "BRIDGE_SYNTHETIC_WAVE_$Architecture=PASS"

if ($FolderEdit.Current.ClassName -ne 'Edit' -or $SelectButton.Current.ClassName -ne 'Button') {
 throw 'Unrecognized system folder picker controls.'
}
$editHwnd=[IntPtr]::new([int]$FolderEdit.Current.NativeWindowHandle)
$selectHwnd=[IntPtr]::new([int]$SelectButton.Current.NativeWindowHandle)
if ($editHwnd -eq [IntPtr]::Zero -or $selectHwnd -eq [IntPtr]::Zero) { throw 'Missing native picker HWND.' }
$set=[FoobarIsolatedUiMessage]::SendMessageText(
 $editHwnd,[uint32]0x000c,[IntPtr]::Zero,$mediaDir)
if ($set -eq [IntPtr]::Zero) { throw 'Native folder edit rejected WM_SETTEXT.' }
Write-Host "BRIDGE_SYNTHETIC_FOLDER_EDIT_$Architecture=PASS"
[void][FoobarIsolatedUiMessage]::SendMessage(
 $selectHwnd,[uint32]0x00f5,[IntPtr]::Zero,[IntPtr]::Zero)
$deadline=[DateTime]::UtcNow.AddSeconds(15)
$still=$Picker
while ([DateTime]::UtcNow -lt $deadline) {
 $still=$FirstWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$PickerCondition)
 if ($null -eq $still) { break }
 Start-Sleep -Milliseconds 250
}
if ($null -ne $still) { throw 'Folder chooser did not accept synthetic path.' }
Write-Host "BRIDGE_SYNTHETIC_FOLDER_SELECTED_$Architecture=PASS"
$folderListCond=[System.Windows.Automation.PropertyCondition]::new(
 [System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1233')
$folderList=$Preferences.FindFirst(
 [System.Windows.Automation.TreeScope]::Descendants,$folderListCond)
if ($null -ne $folderList) {
 $listType=$folderList.Current.ClassName
 $listHwnd=[IntPtr]::new([int]$folderList.Current.NativeWindowHandle)
 if ($listType -eq 'SysListView32' -and $listHwnd -ne [IntPtr]::Zero) {
  $listCount=[FoobarIsolatedUiMessage]::SendMessage(
   $listHwnd,[uint32]0x1004,[IntPtr]::Zero,[IntPtr]::Zero)
  Write-Host "BRIDGE_PREFS_MONITORED_FOLDER_ROWS_$Architecture=$($listCount.ToInt64())"
 } else {
  Write-Host "BRIDGE_PREFS_MONITORED_FOLDER_ROWS_$Architecture=UNKNOWN_CLASS_$listType"
 }
} else {
 Write-Host "BRIDGE_PREFS_MONITORED_FOLDER_ROWS_$Architecture=NO_LIST"
}
$prefsHwnd=[IntPtr]::new([int]$Preferences.Current.NativeWindowHandle)
if ($prefsHwnd -eq [IntPtr]::Zero) { throw 'Preferences HWND vanished.' }
[void][FoobarIsolatedUiMessage]::SendMessage(
 $prefsHwnd,[uint32]0x0111,[IntPtr]::new(1),[IntPtr]::Zero)
Write-Host "BRIDGE_SYNTHETIC_LIBRARY_CONFIGURED_$Architecture=PASS"

$dir=Join-Path $profile 'foo_dj_library_bridge'
$stateFile=Join-Path $dir 'bridge-state.tsv'
$gzipFile=Join-Path $dir 'digital-items.tsv.gz'
function Wait-BridgeSnapshot([int]$ExpectedCount,[long]$PreviousGeneration,
 [string[]]$TrackNames,[string]$Phase) {
 $deadline=[DateTime]::UtcNow.AddSeconds(45)
 $observed=''
 while ([DateTime]::UtcNow -lt $deadline) {
  try {
   $state=@{}
   foreach ($line in (Get-Content -LiteralPath $stateFile -Encoding UTF8)) {
    $pair=$line.Split([char]9,2)
    if ($pair.Count -eq 2) { $state[$pair[0]]=$pair[1] }
   }
   $observed="$($state.generation),$($state.complete),$($state.item_count)"
   if ($state.complete -eq '1' -and
       $state.item_count -eq [string]$ExpectedCount -and
       [long]$state.generation -gt $PreviousGeneration) {
    $f=[IO.File]::OpenRead($gzipFile)
    try {
     $z=[IO.Compression.GZipStream]::new($f,[IO.Compression.CompressionMode]::Decompress)
     try {
      $reader=[IO.StreamReader]::new($z)
      try {
       $head=$reader.ReadLine()
       $rows=@()
       while ($null -ne ($line=$reader.ReadLine())) { $rows+=$line }
      } finally { $reader.Dispose() }
     } finally { $z.Dispose() }
    } finally { $f.Dispose() }
    if (@($head.Split([char]9)).Count -ne 26 -or $rows.Count -ne $ExpectedCount) {
     throw "Invalid actual foobar Media Library record count or header: $Phase"
    }
    $names=[System.Collections.Generic.List[string]]::new()
    foreach ($row in $rows) {
     $cells=@($row.Split([char]9))
     if ($cells.Count -ne 26 -or $cells[1] -ne '0') { throw "Invalid live foobar row at $Phase" }
     $names.Add([IO.Path]::GetFileName($cells[0]))
    }
    if (@(Compare-Object -ReferenceObject $TrackNames -DifferenceObject $names.ToArray()).Count -eq 0) {
     Write-Host "BRIDGE_REAL_LIBRARY_$($Phase)_$Architecture=PASS count=$ExpectedCount generation=$($state.generation)"
     return [long]$state.generation
    }
   }
  } catch [System.IO.IOException] { $observed=$_.Exception.Message }
  Start-Sleep -Milliseconds 500
 }
 throw "Real foobar Media Library phase $Phase timed out: $observed"
}
$g1=Wait-BridgeSnapshot -ExpectedCount 1 -PreviousGeneration 1 -TrackNames @('Synthetic 01.wav') -Phase INITIAL
New-SilentWave -Path $second -Seconds 1
$g2=Wait-BridgeSnapshot -ExpectedCount 2 -PreviousGeneration $g1 -TrackNames @('Synthetic 01.wav','Synthetic 02.wav') -Phase ADDED
Remove-Item -LiteralPath $second -Force -ErrorAction Stop
$g3=Wait-BridgeSnapshot -ExpectedCount 1 -PreviousGeneration $g2 -TrackNames @('Synthetic 01.wav') -Phase REMOVED
Write-Host "BRIDGE_REAL_LIBRARY_ADD_REMOVE_$Architecture=PASS"
