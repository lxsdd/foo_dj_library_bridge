# DJ Library bridge handoff v1

Payload header (exactly 24 UTF-8 TSV columns):

`path, subsong, artist, artists, title, original_title, remixed_by, album, album_artist, track_number, total_tracks, disc_number, total_discs, date, genre, style, bpm, label, catalog_number, duration_seconds, isrc, codec, bitrate, tag_fingerprint`

Tabs/newlines/NUL in textual values are normalized to spaces before publication. `duration_seconds` uses invariant decimal notation. Canonical identity is `(path, subsong)`.

`bridge-state.tsv` contains exactly these required keys:

- `schema_version`
- `generation`
- `complete`
- `item_count`
- `last_change_utc`

The consumer accepts only schema 1 with `complete=1`, exact row width, exact item count and a stable state file before/after payload read.
