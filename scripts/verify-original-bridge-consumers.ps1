#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TestRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# The source-of-truth readers are downloaded by immutable commit and verified
# byte-for-byte via Git blob hash; synthetic snapshots never leave runner temp.
if ($env:GITHUB_ACTIONS -ne 'true' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'Original consumer interoperability is restricted to isolated GitHub runners.'
}
$testPath = [IO.Path]::GetFullPath($TestRoot)
$runnerPrefix = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([char]'\\', [char]'/') + [IO.Path]::DirectorySeparatorChar
if (-not $testPath.StartsWith($runnerPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to read snapshots outside the disposable GitHub runner directory.'
}
if (-not (Test-Path -LiteralPath (Join-Path $testPath 'stages\g11-large\digital-items.tsv.gz') -PathType Leaf)) {
    throw 'Native Publisher did not generate the synthetic scale fixture.'
}
$TestRoot = $testPath
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    # Use the exact original DJ Library reader, not a test-only replacement.
    $readerCommit = '211e85726bcc7e63ce0f9b81f04c2e61257dc5d8'
    $readerBlob = '7ec0d945e5a31443c4e38b6fe72439ad07f6dc4a'
    $readerFile = Join-Path $testRoot 'OriginalBridgeSnapshot.cs'
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lxsdd/dj-library-public/$readerCommit/src/BridgeSnapshot.cs" -OutFile $readerFile -ErrorAction Stop
    $actualBlob = (& git hash-object -- $readerFile).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualBlob -cne $readerBlob) {
      throw "Original DJ Library reader SHA mismatch: $actualBlob"
    }
    $consumerOut = Join-Path $testRoot 'native-consumer'
    & dotnet build 'tests/native-consumer/BridgeNativeWindowsConsumer.csproj' -c Release "-p:ExternalBridgeSource=$readerFile" -o $consumerOut --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Original DJ Library reader compilation failed' }
    & dotnet (Join-Path $consumerOut 'BridgeNativeWindowsConsumer.dll') $testRoot
    if ($LASTEXITCODE -ne 0) { throw 'Actual native Publisher to original DJ Library C# consumer validation failed' }
    # Read the same actual native Publisher bytes with the production
    # MyTagSync Bridge readers. Pin both original source files by Git blob.
    $mytagCommit = 'f891f9cde526601e6d6ce098c20b7c8b65136193'
    $mytagFiles = @(
      @{ Relative = 'BridgeSnapshot.cs'; Sha = '7f3774cdf68d42ccc0050f971e30b8bfd4aab407'; Property = 'MyTagBridgeSource' },
      @{ Relative = 'BridgeSourceDiscovery.cs'; Sha = '8ba87ffbba0dc2a50a0d9b7cf4030c9361c19264'; Property = 'MyTagDiscoverySource' }
    )
    $mytagSource = @{}
    foreach ($source in $mytagFiles) {
      $sourcePath = Join-Path $testRoot ('original-mytag-' + $source.Relative)
      $uri = "https://raw.githubusercontent.com/lxsdd/rekordbox-mytag-sync/$mytagCommit/src/RekordboxMyTagSync/Core/$($source.Relative)"
      Invoke-WebRequest -Uri $uri -OutFile $sourcePath -ErrorAction Stop
      $actualGitBlob = (& git hash-object -- $sourcePath).Trim()
      if ($LASTEXITCODE -ne 0 -or $actualGitBlob -cne $source.Sha) {
        throw "Original MyTagSync $($source.Relative) source hash mismatch"
      }
      $mytagSource[$source.Property] = $sourcePath
    }
    $mytagOut = Join-Path $testRoot 'original-mytag-consumer'
    & dotnet build 'tests/mytag-consumer/OriginalMyTagBridgeInterop.csproj' -c Release "-p:MyTagBridgeSource=$($mytagSource.MyTagBridgeSource)" "-p:MyTagDiscoverySource=$($mytagSource.MyTagDiscoverySource)" -o $mytagOut --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Original MyTagSync Bridge source compilation failed' }
    & dotnet (Join-Path $mytagOut 'OriginalMyTagBridgeInterop.dll') $testRoot
    if ($LASTEXITCODE -ne 0) { throw 'Native Bridge Publisher to original MyTagSync Bridge consumer failed' }
    Write-Host 'NATIVE_PRODUCER_ORIGINAL_DJLIB_AND_MYTAG_READERS=PASS'
} finally {
    Pop-Location
}
