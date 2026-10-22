# Architecture

## Safety boundary

The component is an exporter only. It calls Media Library read APIs and cached metadata APIs. There is deliberately no tag writer, no filesystem scan of the user's music folders, and no access to foobar2000 private database formats.

## Profile-local storage

Runtime bridge files live in:

`<active foobar2000 profile>\foo_dj_library_bridge\`

The profile is resolved through `core_api::get_profile_path()` and converted to a native path through the foobar2000 filesystem API. This is intentional:

- standard foobar2000 v2 installs naturally use the standard profile;
- portable installs naturally stay inside their own portable profile;
- two separate foobar profiles cannot overwrite one another;
- portable installations keep the bridge files inside their own profile tree;
- runtime data is not mixed with the installed DLL under `user-components[-x64]`.

The snapshot is regenerable runtime data, not user configuration, so it is kept as files below the profile rather than encoded into foobar2000's configuration store.

## Source identity

`bridge-state.tsv` keeps all original schema-v1 required keys and adds optional producer metadata:

- `source_id`: stable hash derived from the profile path;
- `source_name`: human-readable profile label;
- `profile_path`: resolved native profile path;
- `producer_version`;
- `producer_pid`.

Consumers that only understand the original schema-v1 required keys remain compatible.

## Physical sources and virtual foobar subsongs

The producer exports the Media Library **exactly** as foobar SDK handles:
`path = get_path()` and `subsong = get_subsong_index()`. Together these
constitute the complete row identity. A shared `path` is not sufficient to
deduplicate rows; a CUE file or one audio file can expose multiple legitimate
nonzero virtual segments. The Bridge never manufactures an additional
`subsong=0` source when foobar exposes only these virtual handles.

Consumer responsibilities are intentionally asymmetric:

- **DJ Library:** retain nonzero tracks for track-level CD catalog search.
  Preserve provenance, and only project genre automatically when independent
  timing and ambiguity checks justify it; virtual rows are not extra audio
  files.
- **rekordbox MyTagSync:** nonzero tracks are diagnostics, not file-level
  ContentID matches or additional physical-path duplicates. Only a unique,
  separately verified `subsong=0` source can be considered for matching,
  subject to the existing database/write-safety gates. If the Bridge supplies
  only virtual rows for a given audio/CUE source, there is no whole-file source
  to promote by guessing or copying metadata from the first segment.

This does **not** mean that subsong zero alone proves a path is a writable
audio file, or that every nonzero entry is an embedded-CUE track. The Bridge
does not parse, synthesize or publish full CUE timing/INDEX boundaries; it
exports the per-item duration already observed by foobar. These rules use
the existing schema-v3 `path`/`subsong` columns and require **no schema or
snapshot file format changes**. See README's physical/virtual consumer contract.

Actual foobar Win32/x64 host tests cover an external multi-file CUE source
and a Vorbis-comment embedded FLAC CUESHEET, including separate file-level
sources, distinct virtual handles, absence of synthetic subsong-zero rows,
and SHA-256 invariants of the generated audio fixtures.

## Atomic publication

For generation `N`:

1. atomically publish `bridge-state.tsv` with `complete=0`, generation `N`;
2. write and flush `digital-items.tsv.gz.tmp`;
3. atomically replace `digital-items.tsv.gz`;
4. atomically publish `bridge-state.tsv` with `complete=1` **last**.

Thus the app never treats a payload swap as authoritative before its matching state commit exists.

## Gzip implementation

The payload is a standards-compliant RFC 1952 gzip stream using DEFLATE stored blocks. This avoids a third-party runtime dependency and remains fully readable by .NET `GZipStream`.

## Threading

foobar library callbacks are handled on the foobar main thread. Metadata is copied immediately into plain C++ records. Disk I/O runs on a private worker and therefore performs no SDK calls.

## Incremental model

Callbacks update an in-memory map keyed by `path + subsong`. Publication rewrites the complete projected snapshot after a 750 ms coalescing interval. With the expected library sizes this is intentionally simpler and safer than introducing another persistent database.
