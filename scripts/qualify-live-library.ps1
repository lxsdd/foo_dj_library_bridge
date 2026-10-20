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
$pickerHwnd=[IntPtr]::new([int]$Picker.Current.NativeWindowHandle)
if ($editHwnd -eq [IntPtr]::Zero -or $selectHwnd -eq [IntPtr]::Zero -or
    $pickerHwnd -eq [IntPtr]::Zero) { throw 'Missing isolated Folder Picker HWND.' }
$process = @(Get-Process -Name foobar2000 -ErrorAction Stop)
if ($process.Count -ne 1) { throw 'Expected exactly one disposable foobar process.' }
# foobar2000 delegates its official Windows file/folder chooser to its
# sidecar fooHelper.exe. Only the helper extracted from the verified installer
# into this exact disposable foobar host folder may receive simulated input.
$installRoot=[IO.Path]::GetFullPath((Split-Path -Parent $profile))
$verifiedHelperPath=[IO.Path]::GetFullPath(
    (Join-Path $installRoot 'fooHelper.exe'))
if (-not (Test-Path -LiteralPath $verifiedHelperPath -PathType Leaf)) {
    throw 'Official disposable foobar helper executable was not found.'
}
$expectedPickerOwner=[uint32]0
foreach ($controlSpec in @(
    @{ Role='picker'; Handle=$pickerHwnd },
    @{ Role='edit';   Handle=$editHwnd },
    @{ Role='select'; Handle=$selectHwnd }
)) {
    $ownerPid=[uint32]0
    [void][FoobarIsolatedUiMessage]::GetWindowThreadProcessId(
        $controlSpec.Handle,[ref]$ownerPid)
    $ownerProcess=Get-Process -Id $ownerPid -ErrorAction Stop
    $ownerPath=$ownerProcess.Path
    if ([string]::IsNullOrWhiteSpace($ownerPath)) {
        throw 'Cannot establish native owner executable for folder chooser.'
    }
    $fullOwnerPath=[IO.Path]::GetFullPath($ownerPath)
    $isOfficialHelper=(
        $ownerProcess.ProcessName -ieq 'fooHelper' -and
        [string]::Equals($fullOwnerPath,$verifiedHelperPath,
                        [StringComparison]::OrdinalIgnoreCase))
    if (-not $isOfficialHelper) {
        throw 'Refusing real input into an unverified Windows folder chooser process.'
    }
    if ($expectedPickerOwner -eq [uint32]0) { $expectedPickerOwner=$ownerPid }
    if ($ownerPid -ne $expectedPickerOwner) {
        throw 'Folder picker controls belong to inconsistent helper processes.'
    }
    Write-Host "BRIDGE_PICKER_CONTROL_OWNER_$Architecture=$($controlSpec.Role) officialHelper:PASS"
}
Write-Host "BRIDGE_PICKER_OFFICIAL_SIDECAR_$Architecture=PASS"
function Invoke-DisposableRealMouseClick([System.Windows.Automation.AutomationElement]$Control) {
    $r=$Control.Current.BoundingRectangle
    if ($r.Width -lt 3 -or $r.Height -lt 3 -or
        [math]::Abs($r.Left) -gt 10000 -or [math]::Abs($r.Top) -gt 10000) {
        throw 'Isolated Windows control is not visibly clickable.'
    }
    $cx=[int][math]::Round($r.Left+$r.Width/2)
    $cy=[int][math]::Round($r.Top+$r.Height/2)
    if (-not [FoobarIsolatedUiMessage]::SetCursorPos($cx,$cy)) {
        throw 'Cannot move isolated runner cursor to native picker control.'
    }
    Start-Sleep -Milliseconds 60
    [FoobarIsolatedUiMessage]::mouse_event([uint32]2,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 75
    [FoobarIsolatedUiMessage]::mouse_event([uint32]4,0,0,0,[UIntPtr]::Zero)
}
[void][FoobarIsolatedUiMessage]::SetForegroundWindow($pickerHwnd)
Invoke-DisposableRealMouseClick -Control $FolderEdit
Write-Host "BRIDGE_NATIVE_FOLDER_EDIT_REAL_FOCUS_$Architecture=PASS"
$set=[FoobarIsolatedUiMessage]::SendMessageText(
 $editHwnd,[uint32]0x000c,[IntPtr]::Zero,$mediaDir)
if ($set -eq [IntPtr]::Zero) { throw 'Native folder edit rejected WM_SETTEXT.' }
$echo=[Text.StringBuilder]::new(4096)
[void][FoobarIsolatedUiMessage]::GetEditText(
 $editHwnd,[uint32]0x000d,[IntPtr]::new(4096),$echo)
$actualEditText=$echo.ToString()
if (-not [string]::Equals($actualEditText,$mediaDir,[StringComparison]::OrdinalIgnoreCase)) {
 throw "Native Folder Edit text differed from requested isolated directory: '$actualEditText'"
}
Write-Host "BRIDGE_SYNTHETIC_FOLDER_EDIT_$Architecture=PASS"
# A shell Folder Picker accepts a typed absolute path through the edit field
# only after the path is navigated/committed with Enter. BM_CLICK alone can
# dismiss the chooser while leaving the monitored-folder list empty.
[FoobarIsolatedUiMessage]::keybd_event([byte]13,[byte]0,[uint32]0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 70
[FoobarIsolatedUiMessage]::keybd_event([byte]13,[byte]0,[uint32]2,[UIntPtr]::Zero)
Write-Host "BRIDGE_NATIVE_FOLDER_ENTER_REAL_INPUT_$Architecture=PASS"
Start-Sleep -Milliseconds 450
$pickerAfterEnter=$FirstWindow.FindFirst(
 [System.Windows.Automation.TreeScope]::Descendants,$PickerCondition)
Write-Host "BRIDGE_SYNTHETIC_FOLDER_ENTER_$Architecture=$(if($null -eq $pickerAfterEnter){'PICKER_CLOSED'}else{'PICKER_OPEN'})"
if ($null -ne $pickerAfterEnter) {
 # Native BM_CLICK and UIA InvokePattern do not reliably dispatch the modern
 # Windows Shell folder chooser. Use a real OS mouse action, restricted to its
 # verified control in the runner's *own* disposable foobar process.
 Invoke-DisposableRealMouseClick -Control $SelectButton
 Write-Host "BRIDGE_NATIVE_FOLDER_SELECT_REAL_INPUT_$Architecture=PASS"
}
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
# The foobar Media Library monitored-folder list is a custom libPPUI
# CListControl, NOT SysListView32. Inspect it via UI Automation's observed
# rows; never send an unsupported native ListView message.
if ($null -ne $folderList) {
 $listChildren = @($folderList.FindAll(
  [System.Windows.Automation.TreeScope]::Children,
  [System.Windows.Automation.Condition]::TrueCondition))
 Write-Host "BRIDGE_PREFS_FOLDER_LIST_CHILDREN_$Architecture=$($listChildren.Count)"
 $foundSyntheticFolder = $false
 foreach ($child in $listChildren) {
  $name = $child.Current.Name
  $class = $child.Current.ClassName
  if ($name -like '*bridge-ci-music*') { $foundSyntheticFolder = $true }
  $safeName = if ($name -match 'bridge-ci-music') { '[synthetic folder]' } elseif ($name -match '[A-Za-z]:\\|[/\\]') { '[path redacted]' } else { $name }
  Write-Host "BRIDGE_PREFS_FOLDER_LIST_CHILD_$Architecture=class:$class name:$safeName synthetic:$($name -like '*bridge-ci-music*')"
 }
 Write-Host "BRIDGE_PREFS_FOLDER_UIA_EXPOSED_$Architecture=$($foundSyntheticFolder.ToString().ToUpperInvariant())"
 $listDescendants = @($folderList.FindAll(
  [System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition))
 $folderDescendantMatches = @($listDescendants | Where-Object { $_.Current.Name -like '*bridge-ci-music*' }).Count
 Write-Host "BRIDGE_PREFS_FOLDER_LIST_DESCENDANTS_$Architecture=$($listDescendants.Count) syntheticMatches=$folderDescendantMatches"
 if (-not $foundSyntheticFolder -and $folderDescendantMatches -eq 0) {
  Write-Host "BRIDGE_PREFS_FOLDER_REGISTRATION_$Architecture=AWAITING_LIVE_SNAPSHOT_PROOF"
 }

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
 [string[]]$TrackNames,[string]$Phase,[double]$ExpectedDurationSeconds=-1) {
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
    $durationMatched=($ExpectedDurationSeconds -lt 0)
    foreach ($row in $rows) {
     $cells=@($row.Split([char]9))
     if ($cells.Count -ne 26 -or $cells[1] -ne '0') { throw "Invalid live foobar row at $Phase" }
     $trackName=[IO.Path]::GetFileName($cells[0])
     $names.Add($trackName)
     if ($ExpectedDurationSeconds -ge 0 -and $trackName -ceq 'Synthetic 01.wav') {
      $observedSeconds=[double]0
      if (-not [double]::TryParse(
          $cells[19],[Globalization.NumberStyles]::Float,
          [Globalization.CultureInfo]::InvariantCulture,[ref]$observedSeconds)) {
       throw "foobar emitted an invalid synthetic WAV duration in $Phase"
      }
      $durationMatched=([math]::Abs($observedSeconds-$ExpectedDurationSeconds) -lt 0.02)
     }
    }
    if (@(Compare-Object -ReferenceObject $TrackNames -DifferenceObject $names.ToArray()).Count -eq 0 -and
        $durationMatched) {
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
Write-Host "BRIDGE_PREFS_FOLDER_REGISTRATION_$Architecture=PASS via_actual_foobar_library_callback"
New-SilentWave -Path $second -Seconds 1
$g2=Wait-BridgeSnapshot -ExpectedCount 2 -PreviousGeneration $g1 -TrackNames @('Synthetic 01.wav','Synthetic 02.wav') -Phase ADDED
# Exercise the actual foobar file-monitor and metadata/technical-info refresh.
# The same isolated one-second WAV is rewritten as a valid two-second WAV.
# No real user file, tag or database is touched.
Start-Sleep -Milliseconds 1100
New-SilentWave -Path $first -Seconds 2
$g3=Wait-BridgeSnapshot -ExpectedCount 2 -PreviousGeneration $g2 -TrackNames @('Synthetic 01.wav','Synthetic 02.wav') -Phase MODIFIED -ExpectedDurationSeconds 2
Remove-Item -LiteralPath $second -Force -ErrorAction Stop
$g4=Wait-BridgeSnapshot -ExpectedCount 1 -PreviousGeneration $g3 -TrackNames @('Synthetic 01.wav') -Phase REMOVED -ExpectedDurationSeconds 2
Write-Host "BRIDGE_REAL_LIBRARY_ADD_MODIFY_REMOVE_$Architecture=PASS"
& (Join-Path $PSScriptRoot 'probe-external-cue.ps1') -ProfileDirectory $profile -Architecture $Architecture -MediaDirectory $mediaDir -BeforeGeneration $g4

