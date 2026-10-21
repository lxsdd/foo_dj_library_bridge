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
