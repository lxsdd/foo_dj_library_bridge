# foo_dj_library_bridge

Private companion component for the **DJ Library** desktop application.

## Goal

Read the foobar2000 Media Library through the supported SDK and publish a small, read-only cross-process snapshot into the **active foobar2000 profile**:

`<foobar-profile>\foo_dj_library_bridge\`

This follows foobar2000's profile/portable architecture. Standard and portable foobar2000 instances therefore keep separate bridge state automatically. The component never writes audio files, tags, or foobar2000's private database files.

## Current contract

- foobar2000: v2.0+
- SDK: **2026-09-17**
- C++: **C++20**
- Windows: Win32 + x64
- Identity: `(path, subsong)`
- Payload: `digital-items.tsv.gz`, UTF-8, exactly 24 columns
- Commit marker: `bridge-state.tsv`, schema v1
- Optional source metadata: `source_id`, `source_name`, `profile_path`, `producer_version`, `producer_pid`
- DJ Library remains read-only toward every bridge directory.

The producer writes an explicit `complete=0` marker before replacing the payload and commits `complete=1` last. This closes the crash window where a new payload could otherwise be paired with an old complete state.

## Multi-instance behavior

Each foobar2000 profile has its own directory and generation counter. Two distinct foobar2000 installations/profiles therefore no longer overwrite one global snapshot. DJ Library can remember/select the profile-local source it should consume.

The previous RC1 global location `%LOCALAPPDATA%\DJLibrary\bridge` is **not written** by RC2. It can remain on disk only as a legacy compatibility snapshot.

## Data flow

1. `on_library_initialized()` resolves the active profile using `core_api::get_profile_path()` and the SDK filesystem conversion helper.
2. The component creates `<profile>\foo_dj_library_bridge`.
3. `library_manager::get_all_items()` enumerates the complete Media Library.
4. `library_callback_v2` receives added, removed and modified items.
5. The component keeps a compact in-memory projection keyed by `path + subsong`.
6. Changes are coalesced for 750 ms and published by a worker thread. The worker receives plain copied records and never calls foobar SDK services.
7. DJ Library validates schema, row width, item count and generation before accepting a snapshot.

## Build

Open a Visual Studio Developer PowerShell and run:

```powershell
./scripts/build.ps1 -Platform x64 -Configuration Release
./scripts/build.ps1 -Platform Win32 -Configuration Release
```

The script downloads the exact official SDK archive from foobar2000.org into the ignored `external/` directory. GitHub Actions performs Win32/x64 Windows builds and independent GCC + Clang contract tests on Linux.

## Runtime verification

For the standard non-portable foobar2000 v2 profile:

```powershell
./scripts/verify-snapshot.ps1
```

For another/portable profile:

```powershell
./scripts/verify-snapshot.ps1 -BridgeDirectory 'D:\path\to\profile\foo_dj_library_bridge'
```

## Status

`0.1.0-rc2`: profile-local/multi-instance release candidate.

RC1 passed full-scan/add/remove/modify/restart qualification. RC2 is now also real-Windows qualified for profile-local multi-instance operation: a portable 1,345-item profile and the standard 54,129-item profile coexist independently, and DJ Library can switch between them without cross-overwrite.
