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
- moving a portable installation preserves the bridge relationship;
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
