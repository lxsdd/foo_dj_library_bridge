#!/usr/bin/env python3
"""Generate disposable v2/v3 verifier fixtures from REAL C++ contract-test gzip.

Only the producer's own generated contract-test.tsv.gz is used. No user profile,
music paths, installed foobar, or external files are accessed.
"""
from __future__ import annotations

import gzip
from pathlib import Path

SRC = Path("contract-test.tsv.gz")
ROOT = Path("snapshot-verifier-fixtures")
if not SRC.is_file():
    raise RuntimeError("First run the original C++ contract-tests executable")
with gzip.open(SRC, "rt", encoding="utf-8", newline="") as file:
    rows = [line.rstrip("\r\n").split("\t") for line in file]
assert len(rows) == 4, f"Expected C++ header and three records, got {len(rows)}"
assert all(len(row) == 26 for row in rows), "Original C++ producer no longer emits v3 (26 columns)"
assert rows[0][-2:] == ["extra_metadata_json", "metadata_vectors_json"]
count = len(rows) - 1


def state(schema: int, n: int = count, complete: int = 1) -> str:
    return (
        f"schema_version\t{schema}\n"
        "generation\t7\n"
        f"complete\t{complete}\n"
        f"item_count\t{n}\n"
        "last_change_utc\t2026-10-20T10:00:00Z\n"
        "source_id\tci-bridge-source-only\n"
        "source_name\tSynthetic C++ producer\n"
        "profile_path\tX:\\SYNTHETIC_NOT_A_REAL_PROFILE\n"
        "producer_version\tci-v3\n"
        "producer_pid\t1\n"
    )


def write(name: str, source_rows: list[list[str]], schema: int = 3,
          n: int = count, complete: int = 1) -> None:
    folder = ROOT / name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "bridge-state.tsv").write_text(
        state(schema, n, complete), encoding="utf-8"
    )
    with gzip.open(folder / "digital-items.tsv.gz", "wt", encoding="utf-8",
                   newline="\n") as file:
        for row in source_rows:
            file.write("\t".join(row) + "\n")


write("v3", rows)
write("v2", [row[:-1] for row in rows], schema=2)

write("wrong-count", rows, n=count + 1)
write("incomplete", rows, complete=0)
write("future-schema", rows, schema=4)

bad_header = [row.copy() for row in rows]
bad_header[0][0] = "BROKEN_PATH_HEADER"
write("wrong-header", bad_header)

bad_vectors = [row.copy() for row in rows]
bad_vectors[1][-1] = "not-json"
write("invalid-vectors", bad_vectors)

not_array = [row.copy() for row in rows]
not_array[1][-1] = "{}"
write("nonarray-vectors", not_array)

empty_vectors = [row.copy() for row in rows]
empty_vectors[1][-1] = ""
write("empty-vectors", empty_vectors)

print(f"PASS generated real C++ producer v3 ({count} records) and v2 legacy fixtures "
      "plus seven intentionally invalid snapshots")
