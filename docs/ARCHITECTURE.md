# Architecture

## Safety boundary

The component is an exporter only. It calls Media Library read APIs and cached metadata APIs. There is deliberately no tag writer, no filesystem scan of the user's music folders, and no access to foobar2000 private database formats.

## Atomic publication

Files live in `%LOCALAPPDATA%\DJLibrary\bridge`.

For generation `N`:

1. atomically publish `bridge-state.tsv` with `complete=0`, generation `N`;
2. write and flush `digital-items.tsv.gz.tmp`;
3. atomically replace `digital-items.tsv.gz`;
4. atomically publish `bridge-state.tsv` with `complete=1` **last**.

Thus the app never treats a payload swap as authoritative before its matching state commit exists.

## Gzip implementation

The payload is a standards-compliant RFC 1952 gzip stream using DEFLATE stored blocks. This gives no size compression, but avoids a third-party runtime dependency and remains fully readable by .NET `GZipStream`. The format can later be switched to compressed DEFLATE without changing the consumer contract.

## Threading

foobar library callbacks are handled on the foobar main thread. Metadata is copied immediately into plain C++ records. Disk I/O runs on a private worker and therefore performs no SDK calls.

## Incremental model

Callbacks update an in-memory map keyed by `path + subsong`. Publication currently rewrites the complete projected snapshot after a 750 ms coalescing interval. With the expected library size this is deliberately simpler and safer than introducing SQLite or another persistent cache. If real profiling later shows a problem, an internal incremental cache can be added without changing the external schema-v1 handoff.
