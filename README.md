# foo_dj_library_bridge

Private companion component for the **DJ Library** desktop application.

## Goal

Read the foobar2000 Media Library through the supported SDK and publish a small, read-only cross-process snapshot to:

`%LOCALAPPDATA%\DJLibrary\bridge`

The component never writes audio files, tags, or foobar2000's private database files.

## Current contract

- foobar2000: v2.0+
- SDK: **2026-09-17**
- C++: **C++20**
- Windows: Win32 + x64
- Identity: `(path, subsong)`
- Payload: `digital-items.tsv.gz`, UTF-8, exactly 24 columns
- Commit marker: `bridge-state.tsv`, schema v1
- App remains read-only toward the bridge directory.

The producer writes an explicit `complete=0` marker before replacing the payload and commits `complete=1` last. This closes the crash window where a new payload could otherwise be paired with an old complete state.

## Data flow

1. `on_library_initialized()` enumerates the complete Media Library through `library_manager::get_all_items()`.
2. `library_callback_v2` receives added, removed and modified items.
3. The component keeps a compact in-memory projection keyed by `path + subsong`.
4. Changes are coalesced for 750 ms and published by a worker thread. The worker receives plain copied records and never calls foobar SDK services.
5. DJ Library validates schema, row width, item count and generation before accepting a snapshot.

## Build

Open a Visual Studio Developer PowerShell and run:

```powershell
./scripts/build.ps1 -Platform x64 -Configuration Release
./scripts/build.ps1 -Platform Win32 -Configuration Release
```

The script downloads the exact official SDK archive from foobar2000.org into the ignored `external/` directory. The build forces the Visual Studio 2022 `v143` toolset across the component and SDK project references; the 2026-09-17 SDK is documented as compatible with Visual Studio 2022/2026. GitHub Actions performs Win32/x64 Windows builds and runs independent GCC + Clang contract tests on Linux.

## Runtime verification

After installing the appropriate DLL and starting foobar2000:

```powershell
./scripts/verify-snapshot.ps1
```

Expected: `PASS: schema v1, generation N, X items, complete=1`.

DJ Library should then report a live bridge generation instead of `Digitalindex: Test`.

## Status

`0.1.0-dev`: cloud-bootstrap stage. Serialization/gzip tests, sanitizer checks, exact consumer-contract comparison and static read-only audits pass. The component itself still requires the Windows/MSVC GitHub Actions build and a real foobar2000 runtime qualification before release.
