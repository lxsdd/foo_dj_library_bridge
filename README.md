# foo_dj_library_bridge

Private companion component for the **DJ Library** desktop application and read-only metadata source for companion tools such as **Rekordbox MyTag Sync**.

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
- Payload: `digital-items.tsv.gz`, UTF-8
- Schema v3 payload: the existing 25 schema-v2 columns plus one appended `metadata_vectors_json` column
- Commit marker: `bridge-state.tsv`, schema v3
- Optional source metadata: `source_id`, `source_name`, `profile_path`, `producer_version`, `producer_pid`
- DJ Library and other consumers remain read-only toward every bridge directory.

The first 25 schema-v2 columns preserve their established ordering and meaning. `extra_metadata_json` contains only foobar metadata that is not already represented by the core projection. Values are emitted as JSON arrays so true multivalue metadata stays multivalue. Core aliases such as `DATE`/`YEAR`, `LABEL`/`PUBLISHER`, track/disc aliases, `GENRE`, `STYLE`, `BPM`, `ISRC` and the other existing projection fields are deliberately excluded from the generic JSON field to avoid double representation. The generic JSON is deterministically ordered and JSON-escaped; an item with no additional metadata uses canonical `{}`.

`metadata_vectors_json` contains every real foobar metadata field as an ordered array entry with its exact ordered value vector, including duplicate and empty values. It does not synthesize aliases or flatten multivalue fields. `tag_fingerprint` includes both `extra_metadata_json` and `metadata_vectors_json`, so structural metadata changes participate in change detection.

The producer writes an explicit `complete=0` marker before replacing the payload and commits `complete=1` last. This closes the crash window where a new payload could otherwise be paired with an old complete state.

## Multi-instance behavior

Each foobar2000 profile has its own directory and generation counter. Two distinct foobar2000 installations/profiles therefore no longer overwrite one global snapshot. Consumers can remember/select the profile-local source they should use.

The previous RC1 global location `%LOCALAPPDATA%\DJLibrary\bridge` is **not written**. It can remain on disk only as a legacy compatibility snapshot.

## Data flow

1. `on_library_initialized()` resolves the active profile using `core_api::get_profile_path()` and the SDK filesystem conversion helper.
2. The component creates `<profile>\foo_dj_library_bridge`.
3. `library_manager::get_all_items()` enumerates the complete Media Library.
4. `library_callback_v2` receives added, removed and modified items.
5. The component keeps a compact in-memory projection keyed by `path + subsong`.
6. Core fields are projected to their established columns; all remaining metadata is serialized into `extra_metadata_json`, while `metadata_vectors_json` preserves the complete exact metadata vectors for normalization consumers.
7. Changes are coalesced for 750 ms and published by a worker thread. The worker receives plain copied records and never calls foobar SDK services.
8. Consumers validate schema, row width, item count and generation before accepting a snapshot.

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

The verifier recognizes both historical **schema v2 / 25-column** and
current **schema v3 / 26-column** snapshots. For schema v3 it also
validates the appended `metadata_vectors_json` array and its string
value lists. It fails closed for malformed headers, incomplete commits,
unsupported schemas, declared item-count mismatches and producer-state
changes during verification. The public CI generates its positive and
negative fixtures from the actual C++ contract-test producer and never
uses a real foobar profile.

## Status

`0.1.0-rc4`: schema-v3 development candidate for the single-snapshot lossless metadata-vector projection. This revision must not be promoted to `main`/release until downstream compatibility has been qualified against DJ Library and Rekordbox MyTag Sync.

RC2 remains the last real-Windows-qualified profile-local/multi-instance baseline: a portable 1,345-item profile and the standard 54,129-item profile coexist independently, and DJ Library can switch between them without cross-overwrite.

## GitHub candidate and release flow

GitHub is the canonical build authority. The workflow builds and tests both Win32 and x64, verifies the PE machine architecture, and packages one combined foobar2000 component with the Win32 DLL in the archive root and the x64 DLL under `x64/`.

A manually dispatched candidate run produces an immutable `foo_dj_library_bridge-component-<commit>` Actions artifact. `VERSION` is the canonical package/release version source.

Final release promotion accepts only a successful manually dispatched candidate from `main`, verifies the manifest, commit binding, package version, SHA-256 and component layout, then creates tag `v<VERSION>` and publishes those exact bytes without rebuilding.

## Automated source-to-source producer/consumer end-to-end check

The public `consumer-interop` job builds and executes the **real C++ Bridge
contract-test producer**, creating gzip `digital-items.tsv.gz` with three
synthetic subsongs and a genuine 26-column schema-v3 payload. The test-fixture
generator supplies synthetic `bridge-state.tsv` markers and a v2 backward
compatibility fixture. It then compiles the **unchanged, SHA-pinned
`lxsdd/dj-library-public/src/BridgeSnapshot.cs`** against .NET 10 and
feeds these exact C++-generated files into `Inspect(..., true)` and
`LoadItems(...)` on the **same hosted Linux runner**.

The consumer must preserve all three (path, subsong) identities, native
fingerprints, all core values and C++-produced schema-v3 metadata vectors
(including duplicated/case-distinct field names, empty values, quotes,
newlines and multi-value arrays). It must reject incomplete, wrong-count,
unsupported future schema and bad-header inputs. This is a stricter
**producer→consumer** proof than independent format mocks.

The source link pins DJ Library experiment commit
`211e85726bcc7e63ce0f9b81f04c2e61257dc5d8`, whose original
`BridgeSnapshot.cs` Git blob is `7ec0d945e5a31443c4e38b6fe72439ad07f6dc4a`.
The test does not modify either product, foobar, tags or real library;
no package/artifact upload or paid Actions runner. This synthetic
integration does not prove the DLL works inside a real foobar process
or the user's source-specific 54k-track snapshot.

## Library-scale regression (synthetic, not production throughput)

The same original Bridge C++ contract and gzip writer also generate
**54,129 completely fictional schema-v3 rows**, with deterministic
distinct synthetic paths and subsongs, tags, fingerprints and canonical
metadata-vector arrays. A C++-produced gzip stream and matching
throwaway commit-state file are checked by the *actual unchanged*
DJ Library `BridgeSnapshotReader.Inspect(..., true)` and
`LoadItems(...)` on public Linux CI.

The test asserts the exact count and **every record's** original C++
path/subsong, artist, album, title, genre, BPM, codec and duration; all
54,129 identities and producer-derived 16-character fingerprints must
be distinct. The first and last rows additionally test correct
multi-valued `MOOD`, empty metadata strings and `ARTIST` vectors.
It reports scan and full read times for diagnosis but does not use
a hardware-specific benchmark threshold.

The scale is chosen to approximate a typical large foobar library;
this is **not** a measurement of the installed foobar Bridge producer,
native component memory usage, Windows GUI performance or real
metadata-network ingestion. No actual audio or user catalog is opened.
