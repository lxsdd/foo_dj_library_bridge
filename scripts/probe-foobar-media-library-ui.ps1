#requires -Version 7.2
<#
  Disposable foobar UI-discovery preflight ONLY.
  Intent: identify deterministic Win32/x64 automation selectors before enabling
  a real Media Library folder. No user directories or installed profiles.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfileDirectory,
    [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture,
    [ValidateRange(1,2)][int]$ProbeIteration = 1
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify-empty-host-snapshot.ps1') -ProfileDirectory $ProfileDirectory -Architecture $Architecture -ProbeIteration $ProbeIteration
if ($ProbeIteration -ne 1) { return }
if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'UI exploration is restricted to ephemeral GitHub Windows runners.'
}
$profile = [IO.Path]::GetFullPath($ProfileDirectory)
$temp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/') + [IO.Path]::DirectorySeparatorChar
if (-not $profile.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'UI exploration refused: not a disposable foobar profile.'
}
Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
$procs = @(Get-Process -Name foobar2000 -ErrorAction Stop)
if ($procs.Count -ne 1) { throw "Expected exactly one isolated foobar process, found $($procs.Count)" }
$foobarPid = [int]$procs[0].Id
Write-Host "FOOBAR_UI_DIAGNOSTIC_$Architecture=RUNNING_PID $foobarPid"
Write-Host "FOOBAR_UI_MAIN_WINDOW_HANDLE_$Architecture=$($procs[0].MainWindowHandle)"
$root = [System.Windows.Automation.AutomationElement]::RootElement
$windows = @($root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition) |
    Where-Object { $_.Current.ProcessId -eq $foobarPid })
Write-Host "FOOBAR_UI_DIAGNOSTIC_$Architecture=TOP_WINDOWS $($windows.Count)"
# Close the default first-run appearance dialog only inside the isolated host.
# WM_COMMAND/IDOK is equivalent to clicking its OK control (UI Automation id 1).
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FoobarIsolatedUiMessage {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hwnd, UInt32 msg, IntPtr wp, IntPtr lp);
}
'@ -ErrorAction Stop
$uiName = [System.Windows.Automation.AutomationElement]::NameProperty
$welcomeCond = [System.Windows.Automation.PropertyCondition]::new($uiName, 'Quick Appearance Setup')
$firstWindow = $windows | Select-Object -First 1
if ($null -ne $firstWindow) {
    $welcome = $firstWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $welcomeCond)
    if ($null -ne $welcome) {
        $hwnd = [IntPtr]::new([int]$welcome.Current.NativeWindowHandle)
        if ($hwnd -eq [IntPtr]::Zero) { throw 'Quick Appearance Setup did not expose its isolated HWND.' }
        [void][FoobarIsolatedUiMessage]::SendMessage($hwnd,0x111,[IntPtr]::new(1),[IntPtr]::Zero)
        Start-Sleep -Milliseconds 450
        $afterWelcome = $firstWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $welcomeCond)
        if ($null -ne $afterWelcome) { throw 'Isolated Quick Appearance Setup did not close on IDOK.' }
        Write-Host "FOOBAR_UI_FIRST_RUN_SETUP_$Architecture=PASS"
    }
}
# Built-in /config asks the running, isolated foobar instance to display Preferences.
$hostExe = Join-Path (Split-Path -Parent $profile) 'foobar2000.exe'
if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf)) {
    throw 'Disposable installed foobar executable was not found.'
}
$preferencesCommand = Start-Process -FilePath $hostExe -WorkingDirectory (Split-Path -Parent $hostExe) -ArgumentList '/config' -PassThru
if (-not $preferencesCommand.WaitForExit(8000)) {
    Stop-Process -Id $preferencesCommand.Id -Force -ErrorAction SilentlyContinue
    throw 'Isolated /config delegation timed out.'
}
Start-Sleep -Milliseconds 450
$windows = @($root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition) |
    Where-Object { $_.Current.ProcessId -eq $foobarPid })
Write-Host "FOOBAR_UI_AFTER_CONFIG_$Architecture=TOP_WINDOWS $($windows.Count)"

# Use the native Windows treeview API to select pages by *observed* caption.
# No keyboard automation, input injection, direct config edits or library writes.
$prefWindows = @($windows | ForEach-Object {
    $_.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
} | Where-Object {
    $_.Current.ProcessId -eq $foobarPid -and
    $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Window' -and
    $_.Current.Name -like 'Preferences:*'
})
if ($prefWindows.Count -eq 1) {
    $prefs = $prefWindows[0]
    $treeCond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '1068')
    $tree = $prefs.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$treeCond)
    if ($null -ne $tree) {
        $treeClass = $tree.Current.ClassName
        $treeHwnd = [IntPtr]::new([int]$tree.Current.NativeWindowHandle)
        Write-Host "FOOBAR_PREFS_TREE_$Architecture=class:$treeClass,handle:$treeHwnd"
        if ($treeClass -eq 'SysTreeView32' -and $treeHwnd -ne [IntPtr]::Zero) {
            $tvNext = [uint32]0x110a
            $tvSelect = [uint32]0x110b
            $rootItem = [FoobarIsolatedUiMessage]::SendMessage(
                $treeHwnd,$tvNext,[IntPtr]::Zero,[IntPtr]::Zero)
            $pending = [System.Collections.Generic.Stack[IntPtr]]::new()
            if ($rootItem -ne [IntPtr]::Zero) { $pending.Push($rootItem) }
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            $observedNames = [System.Collections.Generic.HashSet[string]]::new()
            $count = 0
            $foundMediaLibrary = $false
            while ($pending.Count -gt 0 -and $count -lt 120) {
                $item = $pending.Pop()
                if (-not $seen.Add($item.ToString())) { continue }
                $count++
                [void][FoobarIsolatedUiMessage]::SendMessage(
                    $treeHwnd,$tvSelect,[IntPtr]::new(9),$item)
                Start-Sleep -Milliseconds 65
                $pageTitle = $prefs.Current.Name
                if ($pageTitle -like 'Preferences:*' -and $observedNames.Add($pageTitle)) {
                    Write-Host "FOOBAR_PREFS_PAGE_$Architecture=$pageTitle"
                }
                if ($pageTitle -eq 'Preferences: Media Library') {
                    $foundMediaLibrary = $true
                    break
                }
                $next = [FoobarIsolatedUiMessage]::SendMessage(
                    $treeHwnd,$tvNext,[IntPtr]::new(1),$item)
                $child = [FoobarIsolatedUiMessage]::SendMessage(
                    $treeHwnd,$tvNext,[IntPtr]::new(4),$item)
                if ($next -ne [IntPtr]::Zero) { $pending.Push($next) }
                if ($child -ne [IntPtr]::Zero) { $pending.Push($child) }
            }
            Write-Host "FOOBAR_PREFS_MEDIA_LIBRARY_$Architecture=$($foundMediaLibrary.ToString().ToUpperInvariant()) traversed=$count"

            if ($foundMediaLibrary) {
                $buttonCond = [System.Windows.Automation.PropertyCondition]::new(
                    [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '1234')
                $button = $prefs.FindFirst(
                    [System.Windows.Automation.TreeScope]::Descendants, $buttonCond)
                if ($null -eq $button) { throw 'Isolated Media Library + Folder button disappeared.' }
                $btnClass = $button.Current.ClassName
                $btnHandle = [IntPtr]::new([int]$button.Current.NativeWindowHandle)
                Write-Host "FOOBAR_LIBRARY_ADD_FOLDER_$Architecture=class:$btnClass,handle:$btnHandle"
                if ($btnClass -ne 'Button' -or $btnHandle -eq [IntPtr]::Zero) {
                    throw 'Unknown Media Library add-folder button implementation.'
                }
                # Open only the chooser. No path has been selected or committed.
                [void][FoobarIsolatedUiMessage]::SendMessage(
                    $btnHandle,[uint32]0x00f5,[IntPtr]::Zero,[IntPtr]::Zero)
                Start-Sleep -Milliseconds 700
                $windows = @($root.FindAll(
                    [System.Windows.Automation.TreeScope]::Children,
                    [System.Windows.Automation.Condition]::TrueCondition) |
                    Where-Object { $_.Current.ProcessId -eq $foobarPid })
                Write-Host "FOOBAR_LIBRARY_FOLDER_PICKER_$Architecture=TOP_WINDOWS $($windows.Count)"
                Write-Host "FOOBAR_LIBRARY_FOLDER_PICKER_$Architecture=OPENED_READ_ONLY"
            }

        } else {
            Write-Host "FOOBAR_PREFS_MEDIA_LIBRARY_$Architecture=UNSUPPORTED_CONTROL"
        }
    } else {
        Write-Host "FOOBAR_PREFS_MEDIA_LIBRARY_$Architecture=NO_TREE"
    }
} else {
    Write-Host "FOOBAR_PREFS_MEDIA_LIBRARY_$Architecture=NO_UNIQUE_PREFERENCES_DIALOG"
}


$printed = 0
function Visit-Control {
    param([System.Windows.Automation.AutomationElement]$element,[int]$depth)
    if ($script:printed -ge 140 -or $depth -ge 6) { return }
    try {
        $type = $element.Current.ControlType.ProgrammaticName
        $name = $element.Current.Name
        $aid  = $element.Current.AutomationId
        if ($name.Length -gt 85) { $name = $name.Substring(0,85) }
        if ($name -match '(?i)(users\\|appdata\\|github\\workspace|run(?:ner)?_temp)') {
            $name = '[disposable path]'
        }
        Write-Host ('FOOBAR_UI_NODE={0} {1} name="{2}" aid="{3}"' -f $depth,$type,$name,$aid)
        $script:printed++
        if ($script:printed -ge 140) { return }
        $children = $element.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($child in $children) {
            Visit-Control -element $child -depth ($depth+1)
            if ($script:printed -ge 140) { break }
        }
    } catch [System.Windows.Automation.ElementNotAvailableException] {
        Write-Host 'FOOBAR_UI_NODE=STALE_SKIPPED'
    }
}
foreach ($window in $windows) {
    Visit-Control -element $window -depth 0
}
Write-Host "FOOBAR_UI_INSPECT_$Architecture=PASS nodes=$printed"
Write-Host "FOOBAR_NONEMPTY_LIBRARY_$Architecture=NOT_TESTED"
