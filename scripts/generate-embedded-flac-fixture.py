#!/usr/bin/env python3
"""Generate a deterministic FLAC/Vorbis-CUESHEET fixture using Python stdlib.

No downloaded encoder, no audio from the user: 44.1 kHz mono silent PCM.
The FLAC Vorbis-comment field CUESHEET is intentionally different from the
structural FLAC METADATA_BLOCK_CUESHEET. The fixture tests the foobar2000
embedded-cuesheet tag convention; do not conflate these two FLAC mechanisms.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import struct

SAMPLE_RATE = 44100
BLOCK = 4096


def crc(data: bytes, bits: int, poly: int) -> int:
    mask = (1 << bits) - 1
    result = 0
    for byte in data:
        result ^= byte << (bits - 8)
        for _ in range(8):
            result = ((result << 1) ^ (poly if result & (1 << (bits - 1)) else 0)) & mask
    return result


def frame_number(number: int) -> bytes:
    if not 0 <= number < 128:
        raise ValueError("Fixture frame count outside tested UTF-8 frame-number range")
    return bytes([number])


def metadata_block(block_type: int, payload: bytes, last: bool = False) -> bytes:
    if len(payload) >= (1 << 24):
        raise ValueError("FLAC metadata block too large")
    return bytes([block_type | (0x80 if last else 0)]) + len(payload).to_bytes(3, "big") + payload


def vorbis_comment(name: str, value: str) -> bytes:
    field = f"{name}={value}".encode("utf-8")
    return struct.pack("<I", len(field)) + field


def frame(number: int, length: int) -> bytes:
    # FLAC: fixed block strategy, explicit 16-bit blocksize, 44.1kHz mono,
    # 16-bit verbatim subframe containing only silent samples.
    header = (b"\xff\xf8\x79\x08" + frame_number(number) +
              struct.pack(">H", length - 1))
    header += bytes([crc(header, 8, 0x07)])
    uncompressed = b"\x02" + (b"\x00\x00" * length)
    data = header + uncompressed
    return data + struct.pack(">H", crc(data, 16, 0x8005))


def make_flac(path: pathlib.Path) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite existing fixture: {path}")
    samples = 4 * SAMPLE_RATE
    pcm = b"\x00\x00" * samples
    remainder = samples % BLOCK
    if remainder != 272:
        raise ValueError("Unexpected FLAC block-size assumptions")
    word = (SAMPLE_RATE << 44) | (15 << 36) | samples
    streaminfo = (struct.pack(">HH", remainder, BLOCK) + b"\x00" * 6 +
                  word.to_bytes(8, "big") + hashlib.md5(pcm).digest())
    assert len(streaminfo) == 34
    cuesheet = "\n".join([
        'PERFORMER "Bridge CI"',
        'TITLE "Embedded Synthetic Album"',
        f'FILE "{path.name}" WAVE',
        "  TRACK 01 AUDIO",
        '    TITLE "Embedded Alpha"',
        '    PERFORMER "Bridge CI"',
        "    INDEX 01 00:00:00",
        "  TRACK 02 AUDIO",
        '    TITLE "Embedded Beta"',
        '    PERFORMER "Bridge CI"',
        "    INDEX 01 00:02:00",
        "",
    ])
    vendor = b"foobar-bridge-synthetic-fixture"
    comments = [
        vorbis_comment("CUESHEET", cuesheet),
        vorbis_comment("GENRE", "Trance"),
        vorbis_comment("DATE", "2026"),
        vorbis_comment("ALBUM ARTIST", "Bridge CI"),
    ]
    vorbis = (struct.pack("<I", len(vendor)) + vendor +
              struct.pack("<I", len(comments)) + b"".join(comments))
    with path.open("xb") as handle:
        handle.write(b"fLaC")
        handle.write(metadata_block(0, streaminfo))
        handle.write(metadata_block(4, vorbis, last=True))
        offset = 0
        number = 0
        while offset < samples:
            take = min(BLOCK, samples - offset)
            handle.write(frame(number, take))
            offset += take
            number += 1
    print("FLAC_EMBEDDED_FIXTURE=PASS frames={} samples={} bytes={}".format(
        number, samples, path.stat().st_size))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    make_flac(args.output)
