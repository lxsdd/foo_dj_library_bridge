param(
    [string]$BridgeDirectory = ""
)
$ErrorActionPreference = 'Stop'

if (-not $BridgeDirectory) {
    $standard = Join-Path $env:APPDATA 'foobar2000-v2\foo_dj_library_bridge'
    if (Test-Path (Join-Path $standard 'bridge-state.tsv')) {
        $BridgeDirectory = $standard
    } else {
        throw "No bridge directory supplied and no standard foobar2000-v2 bridge found at $standard"
    }
}

$statePath = Join-Path $BridgeDirectory 'bridge-state.tsv'
$itemsPath = Join-Path $BridgeDirectory 'digital-items.tsv.gz'
if (-not (Test-Path $statePath)) { throw "Missing $statePath" }
if (-not (Test-Path $itemsPath)) { throw "Missing $itemsPath" }

$state = @{}
Get-Content -LiteralPath $statePath -Encoding UTF8 | ForEach-Object {
    if (-not $_) { return }
    $parts = $_ -split "`t", 2
    if ($parts.Count -ne 2) { throw "Malformed bridge-state line: $_" }
    if ($state.ContainsKey($parts[0])) { throw "Duplicate state key: $($parts[0])" }
    $state[$parts[0]] = $parts[1]
}
foreach ($required in @('schema_version','generation','complete','item_count','last_change_utc')) {
    if (-not $state.ContainsKey($required)) { throw "Missing state key: $required" }
}
if ($state.schema_version -notin @('2', '3')) { throw "Unsupported schema $($state.schema_version): expected v2 or v3" }
if ($state.complete -ne '1') { throw "Snapshot is not complete" }

$expectedHeader = @('path','subsong','artist','artists','title','original_title','remixed_by','album','album_artist','track_number','total_tracks','disc_number','total_discs','date','genre','style','bpm','label','catalog_number','duration_seconds','isrc','codec','bitrate','tag_fingerprint','extra_metadata_json')
if ($state.schema_version -eq '3') { $expectedHeader += 'metadata_vectors_json' }
$expectedColumns = $expectedHeader.Count
$declaredCount = 0
$generation = [long]0
if (-not [int]::TryParse($state.item_count, [ref]$declaredCount) -or $declaredCount -lt 0) {
    throw "Invalid item_count: $($state.item_count)"
}
if (-not [long]::TryParse($state.generation, [ref]$generation) -or $generation -le 0) {
    throw "Invalid generation: $($state.generation)"
}
$stateBefore = [System.IO.File]::ReadAllBytes($statePath)
$fs = [System.IO.File]::Open($itemsPath, 'Open', 'Read', 'ReadWrite')
try {
    $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
    try {
        $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
        try {
            $header = $sr.ReadLine() -split "`t"
            if ($header.Count -ne $expectedColumns) { throw "Payload header has $($header.Count) instead of $expectedColumns columns" }
            for ($i = 0; $i -lt $expectedHeader.Count; $i++) {
                if ($header[$i] -cne $expectedHeader[$i]) { throw "Unexpected payload header column $($i+1): $($header[$i])" }
            }
            $count = 0
            while (($line = $sr.ReadLine()) -ne $null) {
                # PowerShell negative split limits suppress the actual TSV split.
                # Split all tabs and retain trailing empty columns for validation.
                $parts = $line -split "`t"
                if ($parts.Count -ne $expectedColumns) { throw "Payload row $($count+2) has $($parts.Count) instead of $expectedColumns columns" }
                if ([string]::IsNullOrWhiteSpace($parts[24])) { throw "Payload row $($count+2) has empty extra_metadata_json; canonical '{}' expected" }
                try { $extra = ConvertFrom-Json -InputObject $parts[24] -AsHashtable -NoEnumerate -ErrorAction Stop }
                catch { throw "Payload row $($count+2) has invalid extra_metadata_json: $($_.Exception.Message)" }
                if ($extra -isnot [System.Collections.IDictionary]) { throw "Payload row $($count+2) extra_metadata_json must be an object" }
                if ($state.schema_version -eq '3') {
                    if ([string]::IsNullOrWhiteSpace($parts[25])) {
                        throw "Payload row $($count+2) has empty metadata_vectors_json; canonical [] expected"
                    }
                    try { $vectors = ConvertFrom-Json -InputObject $parts[25] -AsHashtable -NoEnumerate -ErrorAction Stop }
                    catch { throw "Payload row $($count+2) has invalid metadata_vectors_json: $($_.Exception.Message)" }
                    if ($vectors -isnot [System.Array]) {
                        throw "Payload row $($count+2) metadata_vectors_json must be an array"
                    }
                    foreach ($entry in $vectors) {
                        if ($entry -isnot [System.Collections.IDictionary] -or
                            $entry['name'] -isnot [string] -or
                            $entry['values'] -isnot [System.Array]) {
                            throw "Payload row $($count+2) metadata vector must contain string name and array values"
                        }
                        foreach ($value in $entry['values']) {
                            if ($value -isnot [string]) {
                                throw "Payload row $($count+2) metadata vector values must all be strings"
                            }
                        }
                    }
                }
                $count++
            }
        } finally { $sr.Dispose() }
    } finally { $gz.Dispose() }
} finally { $fs.Dispose() }

if ($count -ne $declaredCount) { throw "item_count=$declaredCount, payload=$count" }
$stateAfter = [System.IO.File]::ReadAllBytes($statePath)
$sameState = $stateBefore.Length -eq $stateAfter.Length
if ($sameState) {
    for ($i = 0; $i -lt $stateBefore.Length; $i++) {
        if ($stateBefore[$i] -ne $stateAfter[$i]) {
            $sameState = $false
            break
        }
    }
}
if (-not $sameState) {
    throw 'Bridge generation/state changed while verifying; refuse mixed snapshot'
}
$source = if ($state.source_name) { $state.source_name } else { '(legacy/no source metadata)' }
Write-Host "PASS: schema v$($state.schema_version), generation $($state.generation), $count items, complete=1, $expectedColumns columns"
Write-Host "Source: $source"
if ($state.profile_path) { Write-Host "Profile: $($state.profile_path)" }
Write-Host "Bridge: $BridgeDirectory"
