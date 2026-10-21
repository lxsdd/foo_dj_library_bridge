# Synthetic nonexistent media only; execute solely on ephemeral GitHub Windows runners.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $env:RUNNER_TEMP) { throw 'RUNNER_TEMP required; never use real profiles' }
$verifier = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\verify-snapshot.ps1'
$work = Join-Path $env:RUNNER_TEMP ("bridge-verifier-json-" + [guid]::NewGuid().ToString('N'))
$utf8 = [System.Text.UTF8Encoding]::new($false)
$tab = [string][char]9
$lf = [string][char]10
$header = @(
    'path','subsong','artist','artists','title','original_title','remixed_by','album',
    'album_artist','track_number','total_tracks','disc_number','total_discs','date',
    'genre','style','bpm','label','catalog_number','duration_seconds','isrc',
    'codec','bitrate','tag_fingerprint','extra_metadata_json','metadata_vectors_json'
)

function New-SyntheticBridge {
    param([string]$Name, [int]$Schema, [string]$Subsong = '0', [string]$Vectors = '[]', [string]$Extra = '{}')
    $directory = Join-Path $work $Name
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $row = New-Object 'string[]' $header.Count
    $row[0] = 'X:\NONEXISTENT_SYNTHETIC\Track.wav'
    $row[1] = $Subsong
    $row[4] = 'Synthetic'
    $row[19] = '1.25'
    $row[23] = 'fake-fingerprint'
    $row[24] = $Extra
    $row[25] = $Vectors
    if ($Schema -eq 2) {
        $tsv = ($header[0..24] -join $tab) + $lf + ($row[0..24] -join $tab) + $lf
    } else {
        $tsv = ($header -join $tab) + $lf + ($row -join $tab) + $lf
    }
    $path = Join-Path $directory 'digital-items.tsv.gz'
    $output = [System.IO.File]::Create($path)
    try {
        $zip = [System.IO.Compression.GZipStream]::new(
            $output, [System.IO.Compression.CompressionMode]::Compress)
        try {
            $writer = [System.IO.StreamWriter]::new($zip, $utf8)
            try { $writer.Write($tsv) } finally { $writer.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $output.Dispose() }
    $state = @(
        ('schema_version' + $tab + $Schema),
        ('generation' + $tab + '7'),
        ('complete' + $tab + '1'),
        ('item_count' + $tab + '1'),
        ('last_change_utc' + $tab + '2026-10-21T00:00:00Z')
    ) -join $lf
    [System.IO.File]::WriteAllText((Join-Path $directory 'bridge-state.tsv'), $state + $lf, $utf8)
    return $directory
}

New-Item -ItemType Directory -Path $work | Out-Null
try {
    foreach ($schema in @(2,3)) {
        $directory = New-SyntheticBridge -Name "good-v$schema" -Schema $schema
        & $verifier -BridgeDirectory $directory
        Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) schema-v$schema"
    }
    $rich = New-SyntheticBridge -Name 'valid-rich-json' -Schema 3 -Extra '{"MOOD":["warm","cold"]}' -Vectors '[{"name":"ARTIST","values":["A","A",""]},{"name":"MOOD","values":["warm"]}]'
    & $verifier -BridgeDirectory $rich
    Write-Host 'PASS: valid multivalue metadata and empty vector strings preserved'
    # A complete=1 marker declaring zero items must reject an unexpected
    # payload row immediately, without consuming additional gzip records.
    $overflow = New-SyntheticBridge -Name 'declared-zero-with-row' -Schema 3
    $stateFile = Join-Path $overflow 'bridge-state.tsv'
    $originalState = [System.IO.File]::ReadAllText($stateFile, $utf8)
    $originalToken = 'item_count' + $tab + '1'
    $invalidState = $originalState.Replace($originalToken, 'item_count' + $tab + '0')
    if ($invalidState -eq $originalState) { throw 'Synthetic item_count replacement did not execute' }
    [System.IO.File]::WriteAllText($stateFile, $invalidState, $utf8)
    $overflowRejected = $false
    try { & $verifier -BridgeDirectory $overflow } catch { $overflowRejected = $true }
    if (-not $overflowRejected) { throw 'Row overflow was accepted despite declared zero items' }
    Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) refuses row overflow"
    # A UTF-8 BOM at the beginning of state must be treated identically
    # to BOM-free state, including on the legacy Windows PowerShell runtime.
    $bomDir = New-SyntheticBridge -Name 'state-with-utf8-bom' -Schema 3
    $bomPath = Join-Path $bomDir 'bridge-state.tsv'
    $withBom = [byte[]]@(239, 187, 191) + [System.IO.File]::ReadAllBytes($bomPath)
    [System.IO.File]::WriteAllBytes($bomPath, $withBom)
    & $verifier -BridgeDirectory $bomDir
    Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) accepts UTF-8 BOM state"
    # Validate that state keys remain authoritative even when the payload is
    # structurally correct: no partial commit or unsupported future schema.
    foreach ($invalidStateCase in @(
        @{ Name = 'state-incomplete'; Old = 'complete' + $tab + '1'; New = 'complete' + $tab + '0' },
        @{ Name = 'state-future-schema'; Old = 'schema_version' + $tab + '3'; New = 'schema_version' + $tab + '99' },
        @{ Name = 'state-wrong-count'; Old = 'item_count' + $tab + '1'; New = 'item_count' + $tab + '2' },
        @{ Name = 'state-zero-generation'; Old = 'generation' + $tab + '7'; New = 'generation' + $tab + '0' }
    )) {
        $directory = New-SyntheticBridge -Name $invalidStateCase.Name -Schema 3
        $statePath = Join-Path $directory 'bridge-state.tsv'
        $stateContents = [System.IO.File]::ReadAllText($statePath, $utf8)
        $changed = $stateContents.Replace($invalidStateCase.Old, $invalidStateCase.New)
        if ($changed -eq $stateContents) { throw "Failed to mutate synthetic state $($invalidStateCase.Name)" }
        [System.IO.File]::WriteAllText($statePath, $changed, $utf8)
        $rejected = $false
        try { & $verifier -BridgeDirectory $directory } catch { $rejected = $true }
        if (-not $rejected) { throw "Unsafe state was accepted: $($invalidStateCase.Name)" }
        Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) rejected $($invalidStateCase.Name)"
    }
    # A damaged compressed stream must not be counted as complete.
    $corrupt = New-SyntheticBridge -Name 'bad-gzip-header' -Schema 3
    $gzPath = Join-Path $corrupt 'digital-items.tsv.gz'
    $gzipBytes = [System.IO.File]::ReadAllBytes($gzPath)
    $gzipBytes[0] = 0
    [System.IO.File]::WriteAllBytes($gzPath, $gzipBytes)
    $rejected = $false
    try { & $verifier -BridgeDirectory $corrupt } catch { $rejected = $true }
    if (-not $rejected) { throw 'Verifier accepted corrupted gzip header' }
    Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) rejects corrupt gzip"
    foreach ($testcase in @(
        @{ Name = 'bad-subsong'; Subsong = '-1'; Vectors = '[]' },
        @{ Name = 'bad-vectors'; Subsong = '0'; Vectors = '{}' },
        @{ Name = 'bad-values'; Subsong = '0'; Vectors = '[{"name":"TITLE","values":[2]}]' },
        @{ Name = 'bad-vector-name'; Subsong = '0'; Vectors = '[{"name":"","values":[]}]' },
        @{ Name = 'bad-extra-type'; Subsong = '0'; Vectors = '[]'; Extra = '{"MOOD":"not-array"}' },
        @{ Name = 'bad-extra-item'; Subsong = '0'; Vectors = '[]'; Extra = '{"MOOD":[4]}' },
        @{ Name = 'bad-extra-name'; Subsong = '0'; Vectors = '[]'; Extra = '{"":[]}' }
    )) {
        $extra = if ($testcase.ContainsKey('Extra')) { $testcase.Extra } else { '{}' }
        $directory = New-SyntheticBridge -Name $testcase.Name -Schema 3 -Subsong $testcase.Subsong -Vectors $testcase.Vectors -Extra $extra
        $rejected = $false
        try { & $verifier -BridgeDirectory $directory } catch { $rejected = $true }
        if (-not $rejected) { throw "Malformed synthetic fixture accepted: $($testcase.Name)" }
        Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion) rejected $($testcase.Name)"
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
