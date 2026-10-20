#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TestRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expected = @(
    @{name='g1-empty';      generation=1; count=0;    titles=@()},
    @{name='g2-add';        generation=2; count=2;    titles=@('Alpha','Beta')},
    @{name='g3-edit';       generation=3; count=2;    titles=@('Alpha (updated)','Beta')},
    @{name='g4-remove';     generation=4; count=1;    titles=@('Alpha (updated)')},
    @{name='g5-coalesced';  generation=5; count=3;    titles=@('Alpha (updated)','Beta','Burst final')},
    @{name='g6-restart';    generation=6; count=3;    titles=@('Alpha (updated)','Beta','Burst final')},
    @{name='g7-delete';     generation=7; count=0;    titles=@()},
    @{name='g8-many';       generation=8; count=1024; titles=@()},
    @{name='g10-recovery';  generation=10;count=1;    titles=@('Recovered after failure')},
    @{name='g11-large';     generation=11;count=54129;titles=@()}
)
$headerFields = @(
    'path','subsong','artist','artists','title','original_title','remixed_by',
    'album','album_artist','track_number','total_tracks','disc_number',
    'total_discs','date','genre','style','bpm','label','catalog_number',
    'duration_seconds','isrc','codec','bitrate','tag_fingerprint',
    'extra_metadata_json','metadata_vectors_json'
)
$previousFingerprints = @{}
foreach ($stage in $expected) {
    $folder = Join-Path (Join-Path $TestRoot 'stages') $stage.name
    $stateFile = Join-Path $folder 'bridge-state.tsv'
    $gzipFile = Join-Path $folder 'digital-items.tsv.gz'
    if (-not (Test-Path -LiteralPath $gzipFile -PathType Leaf)) { throw "Missing gzip stage $($stage.name)" }
    $state = @{}
    foreach ($line in (Get-Content -LiteralPath $stateFile -Encoding UTF8)) {
        if (-not $line) { continue }
        $pair = $line.Split([char]9,2)
        if ($pair.Count -ne 2 -or $state.ContainsKey($pair[0])) { throw 'Bad state marker' }
        $state[$pair[0]] = $pair[1]
    }
    if ($state.schema_version -ne '3' -or $state.complete -ne '1' -or
        $state.generation -ne [string]$stage.generation -or
        $state.item_count -ne [string]$stage.count) {
        throw "Unexpected state marker at $($stage.name)"
    }
    if ($state.source_id -ne 'ci-synthetic-source' -or
        $state.producer_version -ne '0.1.0-rc4') { throw 'Source identity lost' }
    $file = [IO.File]::OpenRead($gzipFile)
    try {
        $gzip = [IO.Compression.GZipStream]::new($file,[IO.Compression.CompressionMode]::Decompress)
        try {
            $reader = [IO.StreamReader]::new($gzip,[Text.UTF8Encoding]::new($false))
            try { $data = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
        } finally { $gzip.Dispose() }
    } finally { $file.Dispose() }
    $lines = @($data.Split([char]10) | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -ne ($stage.count + 1)) { throw "Wrong payload count at $($stage.name): $($lines.Count)" }
    $header = @($lines[0].Split([char]9))
    if ($header.Count -ne $headerFields.Count) { throw 'Bad v3 header width' }
    for ($i=0; $i -lt $header.Count; $i++) {
        if ($header[$i] -cne $headerFields[$i]) { throw 'Bad v3 column name or order' }
    }
    if ($stage.count -gt 5000) {
        # Full gzip/header/row count above; original C# reader checks all rows.
        foreach ($idx in @(1, ([int][math]::Floor($stage.count / 2) + 1), $stage.count)) {
            $cols = @($lines[$idx].Split([char]9))
            if ($cols.Count -ne 26 -or
                $cols[0] -notlike 'C:\SyntheticCI\Track*.flac' -or
                $cols[4] -notlike 'Synthetic library track *' -or
                $cols[23] -notmatch '^[0-9a-f]{16}$') {
                throw "Malformed Windows-native large stage record $idx"
            }
            $extra = $cols[24] | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $vectors = @($cols[25] | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
            if (@($extra.MOOD).Count -ne 2 -or $vectors.Count -lt 3) {
                throw "Native large stage lost metadata vectors in record $idx"
            }
        }
        Write-Host "PUBLISHER_GZIP_STAGE_$($stage.generation)=PASS count=$($stage.count)"
        Write-Host 'PUBLISHER_NATIVE_54129_GZIP_STREAM=PASS'
        continue
    }
    $titles = @()
    $fingerprints = @{}
    $paths = @()
    $rows = @()
    if ($lines.Count -gt 1) { $rows = @($lines[1..($lines.Count - 1)]) }
    foreach ($line in $rows) {
        if (-not $line) { continue }
        $v = @($line.Split([char]9))
        if ($v.Count -ne 26) { throw "Bad v3 row width at $($stage.name)" }
        $titles += $v[4]
        $paths += $v[0]
        if ($v[23] -notmatch '^[a-f0-9]{16}$') { throw 'Missing fingerprint' }
        if ($fingerprints.ContainsKey($v[0])) { throw 'Duplicate identity in test snapshot' }
        $fingerprints[$v[0]] = $v[23]
        $extra = $v[24] | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $vectors = $v[25] | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (@($extra.MOOD).Count -ne 2) { throw 'Custom multivalue metadata lost' }
        if (@($vectors).Count -lt 3) { throw 'Lossless metadata vectors missing' }
    }
    if ($stage.count -gt 0) {
        $sorted = @($paths | Sort-Object -CaseSensitive)
        for($i=0; $i -lt $paths.Count; $i++) {
            if ($paths[$i] -cne $sorted[$i]) { throw "Unsorted payload: $($stage.name)" }
        }
    }
    foreach ($expectedTitle in $stage.titles) {
        if ($titles -cnotcontains $expectedTitle) { throw "Title missing: $expectedTitle" }
    }
    if ($stage.name -eq 'g3-edit') {
        $p = 'C:\SyntheticCI\Track1.flac'
        if ($previousFingerprints[$p] -eq $fingerprints[$p]) { throw 'Edit did not change fingerprint' }
    }
    if ($stage.name -eq 'g4-remove' -and ($fingerprints.ContainsKey('C:\SyntheticCI\Track2.flac'))) {
        throw 'Removed item still present'
    }
    $previousFingerprints = $fingerprints
    Write-Host "PUBLISHER_GZIP_STAGE_$($stage.generation)=PASS count=$($stage.count)"
}
# Failure-injection stage deliberately commits an incomplete generation-9
# state and does not overwrite generation-8's last valid gzip bytes.
$failDir = Join-Path (Join-Path $TestRoot 'stages') 'g9-fail-closed'
$failedLines = @(Get-Content -LiteralPath (Join-Path $failDir 'bridge-state.tsv') -Encoding UTF8)
if ($failedLines -cnotcontains ("generation" + [char]9 + "9") -or
    $failedLines -cnotcontains ("complete" + [char]9 + "0") -or
    $failedLines -cnotcontains ("item_count" + [char]9 + "1")) {
    throw 'Injected Publisher write failure did not publish complete=0'
}
$oldGzip = Join-Path (Join-Path (Join-Path $TestRoot 'stages') 'g8-many') 'digital-items.tsv.gz'
$failedGzip = Join-Path $failDir 'digital-items.tsv.gz'
$oldHash = (Get-FileHash -LiteralPath $oldGzip -Algorithm SHA256).Hash
$failedHash = (Get-FileHash -LiteralPath $failedGzip -Algorithm SHA256).Hash
if ($oldHash -cne $failedHash) { throw 'Interrupted new publish destroyed the previous gzip payload' }
$err = Get-Content -Raw -LiteralPath (Join-Path $failDir 'bridge-error.txt')
if ($err -notmatch 'publish failed') { throw 'Publisher failure did not surface an error state' }
Write-Host 'PUBLISHER_FAIL_CLOSED_INCOMPLETE_STATE=PASS'
Write-Host 'PUBLISHER_LAST_GOOD_PAYLOAD_UNCHANGED=PASS'
Write-Host 'PUBLISHER_RECOVERY_COMPLETE_10=PASS'
Write-Host 'PUBLISHER_SNAPSHOT_INTEGRITY=PASS'
) {
                throw "Malformed Windows-native large stage record $idx"
            }
            $extra = $cols[24] | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $vectors = @($cols[25] | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
            if (@($extra.MOOD).Count -ne 2 -or $vectors.Count -lt 3) {
                throw "Native large stage lost metadata vectors in record $idx"
            }
        }
        Write-Host "PUBLISHER_GZIP_STAGE_$($stage.generation)=PASS count=$($stage.count)"
        Write-Host 'PUBLISHER_NATIVE_54129_GZIP_STREAM=PASS'
        continue
    }
    $titles = @()
    $fingerprints = @{}
    $paths = @()
    $rows = @()
    if ($lines.Count -gt 1) { $rows = @($lines[1..($lines.Count - 1)]) }
    foreach ($line in $rows) {
        if (-not $line) { continue }
        $v = @($line.Split([char]9))
        if ($v.Count -ne 26) { throw "Bad v3 row width at $($stage.name)" }
        $titles += $v[4]
        $paths += $v[0]
        if ($v[23] -notmatch '^[a-f0-9]{16}$') { throw 'Missing fingerprint' }
        if ($fingerprints.ContainsKey($v[0])) { throw 'Duplicate identity in test snapshot' }
        $fingerprints[$v[0]] = $v[23]
        $extra = $v[24] | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $vectors = $v[25] | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (@($extra.MOOD).Count -ne 2) { throw 'Custom multivalue metadata lost' }
        if (@($vectors).Count -lt 3) { throw 'Lossless metadata vectors missing' }
    }
    if ($stage.count -gt 0) {
        $sorted = @($paths | Sort-Object -CaseSensitive)
        for($i=0; $i -lt $paths.Count; $i++) {
            if ($paths[$i] -cne $sorted[$i]) { throw "Unsorted payload: $($stage.name)" }
        }
    }
    foreach ($expectedTitle in $stage.titles) {
        if ($titles -cnotcontains $expectedTitle) { throw "Title missing: $expectedTitle" }
    }
    if ($stage.name -eq 'g3-edit') {
        $p = 'C:\SyntheticCI\Track1.flac'
        if ($previousFingerprints[$p] -eq $fingerprints[$p]) { throw 'Edit did not change fingerprint' }
    }
    if ($stage.name -eq 'g4-remove' -and ($fingerprints.ContainsKey('C:\SyntheticCI\Track2.flac'))) {
        throw 'Removed item still present'
    }
    $previousFingerprints = $fingerprints
    Write-Host "PUBLISHER_GZIP_STAGE_$($stage.generation)=PASS count=$($stage.count)"
}
# Failure-injection stage deliberately commits an incomplete generation-9
# state and does not overwrite generation-8's last valid gzip bytes.
$failDir = Join-Path (Join-Path $TestRoot 'stages') 'g9-fail-closed'
$failedLines = @(Get-Content -LiteralPath (Join-Path $failDir 'bridge-state.tsv') -Encoding UTF8)
if ($failedLines -cnotcontains ("generation" + [char]9 + "9") -or
    $failedLines -cnotcontains ("complete" + [char]9 + "0") -or
    $failedLines -cnotcontains ("item_count" + [char]9 + "1")) {
    throw 'Injected Publisher write failure did not publish complete=0'
}
$oldGzip = Join-Path (Join-Path (Join-Path $TestRoot 'stages') 'g8-many') 'digital-items.tsv.gz'
$failedGzip = Join-Path $failDir 'digital-items.tsv.gz'
$oldHash = (Get-FileHash -LiteralPath $oldGzip -Algorithm SHA256).Hash
$failedHash = (Get-FileHash -LiteralPath $failedGzip -Algorithm SHA256).Hash
if ($oldHash -cne $failedHash) { throw 'Interrupted new publish destroyed the previous gzip payload' }
$err = Get-Content -Raw -LiteralPath (Join-Path $failDir 'bridge-error.txt')
if ($err -notmatch 'publish failed') { throw 'Publisher failure did not surface an error state' }
Write-Host 'PUBLISHER_FAIL_CLOSED_INCOMPLETE_STATE=PASS'
Write-Host 'PUBLISHER_LAST_GOOD_PAYLOAD_UNCHANGED=PASS'
Write-Host 'PUBLISHER_RECOVERY_COMPLETE_10=PASS'
Write-Host 'PUBLISHER_SNAPSHOT_INTEGRITY=PASS'
