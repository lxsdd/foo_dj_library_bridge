#requires -Version 7.2
<#
Read-only runtime qualification of the *real* Bridge output from a brand-new
portable foobar2000 profile. Called while the isolated foobar process is alive.
Does not add library folders, write tags, or inspect the user's real collection.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfileDirectory,
    [Parameter(Mandatory)][ValidateSet('Win32','x64')][string]$Architecture
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'Only an isolated disposable GitHub Actions host can run this check.'
}
$profile = [IO.Path]::GetFullPath($ProfileDirectory)
$temp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\',[char]'/') + [IO.Path]::DirectorySeparatorChar
if (-not $profile.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to inspect a non-disposable foobar profile.'
}
$bridge = Join-Path $profile 'foo_dj_library_bridge'
$statePath = Join-Path $bridge 'bridge-state.tsv'
$payloadPath = Join-Path $bridge 'digital-items.tsv.gz'
$errorPath = Join-Path $bridge 'bridge-error.txt'
$headerFields = @(
    'path','subsong','artist','artists','title','original_title','remixed_by',
    'album','album_artist','track_number','total_tracks','disc_number',
    'total_discs','date','genre','style','bpm','label','catalog_number',
    'duration_seconds','isrc','codec','bitrate','tag_fingerprint',
    'extra_metadata_json','metadata_vectors_json'
)

$deadline = [DateTime]::UtcNow.AddSeconds(45)
$observed = ''
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $errorPath -PathType Leaf) {
        throw ('Bridge publisher failed in the disposable profile: ' + (Get-Content -Raw -LiteralPath $errorPath))
    }
    if ((Test-Path -LiteralPath $statePath -PathType Leaf) -and
        (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        try {
            $before = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8
            $state = @{}
            foreach ($line in ($before -split "\r?\n")) {
                if ($line.Length -eq 0) { continue }
                $kv = $line -split "\`t",2
                if ($kv.Count -ne 2 -or $state.ContainsKey($kv[0])) {
                    throw 'Malformed or duplicated Bridge state key.'
                }
                $state[$kv[0]] = $kv[1]
            }
            if (-not $state.ContainsKey('complete') -or $state.complete -ne '1') {
                $observed = 'Snapshot not yet complete'
            } else {
                foreach ($name in @('schema_version','generation','item_count','profile_path','source_id','producer_version','producer_pid')) {
                    if (-not $state.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($state[$name])) {
                        throw "Missing Bridge runtime state: $name"
                    }
                }
                if ($state.schema_version -ne '3') { throw "Unexpected Bridge schema: $($state.schema_version)" }
                if ($state.item_count -ne '0') { throw "Unexpected non-empty disposable Media Library: $($state.item_count)" }
                if ($state.generation -notmatch '^[1-9][0-9]*$') { throw "Invalid initial generation: $($state.generation)" }
                if ($state.producer_version -ne '0.1.0-rc4') { throw "Wrong Bridge producer: $($state.producer_version)" }
                if ($state.producer_pid -notmatch '^[1-9][0-9]*$') { throw 'Missing live producer PID' }

                $fs = [IO.File]::Open($payloadPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                try {
                    $gz = [IO.Compression.GZipStream]::new($fs,[IO.Compression.CompressionMode]::Decompress)
                    try {
                        $reader = [IO.StreamReader]::new($gz,[Text.UTF8Encoding]::new($false),$true)
                        try {
                            $header = $reader.ReadLine()
                            if ($null -eq $header) { throw 'Empty gzip Bridge payload' }
                            $actual = @($header -split "\`t")
                            if ($actual.Count -ne $headerFields.Count) { throw "Wrong v3 column count: $($actual.Count)" }
                            for ($i=0; $i -lt $headerFields.Count; ++$i) {
                                if ($actual[$i] -cne $headerFields[$i]) { throw "Wrong v3 header at column $i" }
                            }
                            if ($null -ne $reader.ReadLine()) { throw 'Unexpected Media Library items in fresh portable profile' }
                        } finally { $reader.Dispose() }
                    } finally { $gz.Dispose() }
                } finally { $fs.Dispose() }

                $after = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8
                if ($before -cne $after) {
                    $observed = 'Atomic marker changed while reading payload'
                } else {
                    Write-Host "BRIDGE_HOST_SNAPSHOT_$Architecture=PASS"
                    Write-Host "BRIDGE_HOST_SCHEMA_$Architecture=3"
                    Write-Host "BRIDGE_HOST_ITEMS_$Architecture=0"
                    Write-Host "BRIDGE_HOST_GENERATION_$Architecture=$($state.generation)"
                    return
                }
            }
        } catch [System.IO.IOException] {
            $observed = $_.Exception.Message
        }
    }
    Start-Sleep -Milliseconds 500
}
throw "Timed out verifying real empty foobar Media Library Bridge snapshot ($Architecture): $observed"
