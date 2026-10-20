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
