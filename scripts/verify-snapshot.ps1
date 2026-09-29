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
if ($state.schema_version -ne '1') { throw "Unsupported schema $($state.schema_version)" }
if ($state.complete -ne '1') { throw "Snapshot is not complete" }

$fs = [System.IO.File]::Open($itemsPath, 'Open', 'Read', 'ReadWrite')
try {
    $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
    try {
        $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
        try {
            $header = $sr.ReadLine()
            if (($header -split "`t").Count -ne 24) { throw "Payload header does not have 24 columns" }
            $count = 0
            while (($line = $sr.ReadLine()) -ne $null) {
                if (($line -split "`t").Count -ne 24) { throw "Payload row $($count+2) does not have 24 columns" }
                $count++
            }
        } finally { $sr.Dispose() }
    } finally { $gz.Dispose() }
} finally { $fs.Dispose() }

if ($count -ne [int]$state.item_count) { throw "item_count=$($state.item_count), payload=$count" }
$source = if ($state.source_name) { $state.source_name } else { '(legacy/no source metadata)' }
Write-Host "PASS: schema v1, generation $($state.generation), $count items, complete=1"
Write-Host "Source: $source"
if ($state.profile_path) { Write-Host "Profile: $($state.profile_path)" }
Write-Host "Bridge: $BridgeDirectory"
