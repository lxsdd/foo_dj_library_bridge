#requires -Version 7.2
# Enables CUE indexing ONLY after the disposable host's physical Media Library
# registration has already been committed and verified by an actual snapshot.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ProfileDirectory,
 [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
 throw 'CUE indexing preferences can only be changed in isolated GitHub CI.'
}
$profile=[IO.Path]::GetFullPath($ProfileDirectory)
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/')+
 [IO.Path]::DirectorySeparatorChar
if (-not $profile.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) {
 throw 'Refusing to update any non-disposable foobar profile.'
}
$exe=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $profile) 'foobar2000.exe'))
$hosts=@(Get-Process -Name foobar2000 -ErrorAction Stop)
if ($hosts.Count -ne 1 -or
    -not [string]::Equals([IO.Path]::GetFullPath($hosts[0].Path),$exe,
     [StringComparison]::OrdinalIgnoreCase)) {
 throw 'Cannot identify the one official disposable foobar host.'
}
$hostPid=[uint32]$hosts[0].Id
Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
if (-not ('FoobarIsolatedUiMessage' -as [type])) {
 throw 'Verified host UI helper was not initialized by the parent probe.'
}
# /config is the built-in official command delegated to the already-running
# instance, not a direct write into foobar's internal settings databases.
$cmd=Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList '/config' -PassThru
if (-not $cmd.WaitForExit(8000) -or $cmd.ExitCode -ne 0) {
 throw 'Disposable foobar /config preferences delegation failed.'
}
Start-Sleep -Milliseconds 500
$root=[System.Windows.Automation.AutomationElement]::RootElement
$windows=@($root.FindAll([System.Windows.Automation.TreeScope]::Children,
 [System.Windows.Automation.Condition]::TrueCondition) |
 Where-Object { $_.Current.ProcessId -eq [int]$hostPid })
$prefs=@($windows | ForEach-Object {
 $_.FindAll([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition)
} | Where-Object {
 $_.Current.ProcessId -eq [int]$hostPid -and
 $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Window' -and
 $_.Current.Name -like 'Preferences:*'
})
if ($prefs.Count -ne 1) {throw 'No unique official foobar Preferences window.'}
$pref=$prefs[0]
if ($pref.Current.Name -cne 'Preferences: Media Library') {
 $treeCond=[System.Windows.Automation.PropertyCondition]::new(
  [System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1068')
 $tree=$pref.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$treeCond)
 if ($null -eq $tree -or $tree.Current.ClassName -cne 'SysTreeView32') {
  throw 'Official Preferences Media Library tree is unavailable.'
 }
 $treeHwnd=[IntPtr]::new([int]$tree.Current.NativeWindowHandle)
 if ($treeHwnd -eq [IntPtr]::Zero) {throw 'No Preferences tree HWND.'}
 $first=[FoobarIsolatedUiMessage]::SendMessage(
  $treeHwnd,[uint32]0x110a,[IntPtr]::Zero,[IntPtr]::Zero)
 $pending=[System.Collections.Generic.Stack[IntPtr]]::new()
 if ($first -ne [IntPtr]::Zero) {$pending.Push($first)}
 $visited=[System.Collections.Generic.HashSet[string]]::new()
 $found=$false
 while ($pending.Count -gt 0 -and $visited.Count -lt 120) {
  $item=$pending.Pop()
  if (-not $visited.Add($item.ToString())) {continue}
  [void][FoobarIsolatedUiMessage]::SendMessage(
    $treeHwnd,[uint32]0x110b,[IntPtr]::new(9),$item)
  Start-Sleep -Milliseconds 60
  if ($pref.Current.Name -ceq 'Preferences: Media Library') {
   $found=$true
   break
  }
  $next=[FoobarIsolatedUiMessage]::SendMessage(
   $treeHwnd,[uint32]0x110a,[IntPtr]::new(1),$item)
  $child=[FoobarIsolatedUiMessage]::SendMessage(
   $treeHwnd,[uint32]0x110a,[IntPtr]::new(4),$item)
  if ($next -ne [IntPtr]::Zero) {$pending.Push($next)}
  if ($child -ne [IntPtr]::Zero) {$pending.Push($child)}
 }
 if (-not $found) {throw 'Cannot select official Media Library Preferences page.'}
}
$edits=@($pref.FindAll([System.Windows.Automation.TreeScope]::Descendants,
 [System.Windows.Automation.Condition]::TrueCondition) | Where-Object {
 $_.Current.ClassName -ceq 'Edit' -and $_.Current.Name -ceq '*.CUE'
})
if ($edits.Count -ne 1) {
 throw 'The official default *.CUE exclusion field is not uniquely present.'
}
$excludeHwnd=[IntPtr]::new([int]$edits[0].Current.NativeWindowHandle)
$ownerPid=[uint32]0
[void][FoobarIsolatedUiMessage]::GetWindowThreadProcessId(
 $excludeHwnd,[ref]$ownerPid)
if ($excludeHwnd -eq [IntPtr]::Zero -or $ownerPid -ne $hostPid) {
 throw 'Refusing edit outside verified official foobar process.'
}
$before=[Text.StringBuilder]::new(512)
[void][FoobarIsolatedUiMessage]::GetEditText(
 $excludeHwnd,[uint32]0x000d,[IntPtr]::new(512),$before)
if ($before.ToString() -cne '*.CUE') {
 throw 'Native exclusion value unexpectedly differs from *.CUE.'
}
$set=[FoobarIsolatedUiMessage]::SendMessageText(
 $excludeHwnd,[uint32]0x000c,[IntPtr]::Zero,'')
$after=[Text.StringBuilder]::new(512)
[void][FoobarIsolatedUiMessage]::GetEditText(
 $excludeHwnd,[uint32]0x000d,[IntPtr]::new(512),$after)
if ($set -eq [IntPtr]::Zero -or $after.Length -ne 0) {
 throw 'Cannot clear exclusion on the disposable Media Library profile.'
}
$prefHwnd=[IntPtr]::new([int]$pref.Current.NativeWindowHandle)
if ($prefHwnd -eq [IntPtr]::Zero) {throw 'Official Preferences HWND disappeared.'}
[void][FoobarIsolatedUiMessage]::SendMessage(
 $prefHwnd,[uint32]0x0111,[IntPtr]::new(1),[IntPtr]::Zero)
Write-Host "FOOBAR_CUE_EXCLUSION_CLEAR_$Architecture=PASS separate_preferences_transaction"
Write-Host "FOOBAR_CUE_INDEXING_READY_$Architecture=PASS"

# WM_SETTEXT can change an Edit control without guaranteeing the hosting
# preferences page persisted it. Reopen official Preferences and verify the
# actual native exclusion value in the same isolated foobar process.
$verifyCmd=Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList '/config' -PassThru
if (-not $verifyCmd.WaitForExit(8000) -or $verifyCmd.ExitCode -ne 0) {
 throw 'Cannot reopen disposable foobar Preferences to verify CUE indexing.'
}
Start-Sleep -Milliseconds 500
$verifyWindows=@($root.FindAll([System.Windows.Automation.TreeScope]::Children,
 [System.Windows.Automation.Condition]::TrueCondition) |
 Where-Object { $_.Current.ProcessId -eq [int]$hostPid })
$verifyPrefs=@($verifyWindows | ForEach-Object {
 $_.FindAll([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition)
} | Where-Object {
 $_.Current.ProcessId -eq [int]$hostPid -and
 $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Window' -and
 $_.Current.Name -ceq 'Preferences: Media Library'
})
if ($verifyPrefs.Count -ne 1) {
 throw 'Cannot identify reopened Media Library Preferences to verify CUE exclusion.'
}
$editControls=@($verifyPrefs[0].FindAll(
 [System.Windows.Automation.TreeScope]::Descendants,
 [System.Windows.Automation.Condition]::TrueCondition) | Where-Object {
 $_.Current.ClassName -ceq 'Edit'
})
$values=[System.Collections.Generic.List[string]]::new()
foreach ($control in $editControls) {
 $handle=[IntPtr]::new([int]$control.Current.NativeWindowHandle)
 $pid=[uint32]0
 [void][FoobarIsolatedUiMessage]::GetWindowThreadProcessId($handle,[ref]$pid)
 if ($handle -eq [IntPtr]::Zero -or $pid -ne $hostPid) {
  throw 'Refusing to inspect a non-foobar Preferences edit.'
 }
 $buffer=[Text.StringBuilder]::new(512)
 [void][FoobarIsolatedUiMessage]::GetEditText(
  $handle,[uint32]0x000d,[IntPtr]::new(512),$buffer)
 $values.Add($buffer.ToString())
}
$persisted = ($values.Count -eq 2 -and
    $values.Contains('*') -and $values.Contains('') -and
    -not $values.Contains('*.CUE'))
Write-Host "FOOBAR_CUE_EXCLUSION_REOPEN_$Architecture=$(if($persisted){'PASS'}else{'FAIL'}) fields:$($values.Count)"
$verifyHwnd=[IntPtr]::new([int]$verifyPrefs[0].Current.NativeWindowHandle)
[void][FoobarIsolatedUiMessage]::SendMessage(
 $verifyHwnd,[uint32]0x0111,[IntPtr]::new(2),[IntPtr]::Zero)
if (-not $persisted) {
 throw 'Disposably cleared CUE exclusion did not persist after Preferences were reopened.'
}

