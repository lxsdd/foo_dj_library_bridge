#!/usr/bin/env python3
"""Independent strict decoder of the silent embedded-CUE FLAC fixture.

Source-only: no binary codecs, network downloads, or third-party dependencies.
Checks FLAC STREAMINFO, 44 verbatim frames/CRCs, decoded PCM MD5, and the
Vorbis-comment CUESHEET convention for foobar2000.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import struct


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def crc(data: bytes, bits: int, polynomial: int) -> int:
    # Bit-at-a-time, no dependency on the fixture generator's CRC routines.
    result = 0
    highest = 1 << (bits - 1)
    mask = (1 << bits) - 1
    for item in data:
        result = result ^ (item << (bits - 8))
        for _ in range(8):
            if result & highest:
                result = ((result * 2) ^ polynomial) & mask
            else:
                result = (result * 2) & mask
    return result


def little_word(data: bytes, index: int) -> int:
    require(index + 4 <= len(data), "Truncated FLAC Vorbis integer")
    return struct.unpack_from("<I", data, index)[0]


def verify(filename: pathlib.Path) -> None:
    file = filename.read_bytes()
    require(file[:4] == b"fLaC", "Not a native FLAC file")
    index = 4
    blocks = {}
    final_block = False
    while not final_block:
        require(index + 4 <= len(file), "Truncated FLAC metadata")
        tag = file[index]
        final_block = bool(tag & 128)
        kind = tag & 127
        size = int.from_bytes(file[index + 1:index + 4], "big")
        index += 4
        require(index + size <= len(file), "Invalid FLAC metadata size")
        require(kind not in blocks, "Duplicate FLAC metadata type")
        blocks[kind] = file[index:index + size]
        index += size

    streaminfo = blocks.get(0)
    require(streaminfo is not None and len(streaminfo) == 34,
            "Missing 34-byte FLAC STREAMINFO")
    bits = int.from_bytes(streaminfo[10:18], "big")
    sample_rate = bits >> 44
    channels = 1 + ((bits >> 41) & 7)
    depth = 1 + ((bits >> 36) & 31)
    total_samples = bits & ((1 << 36) - 1)
    require((sample_rate, channels, depth, total_samples) ==
            (44100, 1, 16, 176400), "Unexpected decoded STREAMINFO")

    comment = blocks.get(4)
    require(comment is not None, "Missing FLAC Vorbis comments")
    pos = 0
    vendor_length = little_word(comment, pos)
    pos += 4 + vendor_length
    number = little_word(comment, pos)
    pos += 4
    require(1 <= number <= 10, "Unexpected FLAC comment count")
    tags: dict[str, list[str]] = {}
    for _ in range(number):
        length = little_word(comment, pos)
        pos += 4
        require(pos + length <= len(comment), "Truncated Vorbis tag")
        name, separator, value = comment[pos:pos + length].decode(
            "utf-8").partition("=")
        pos += length
        require(bool(separator), "Malformed Vorbis comment")
        tags.setdefault(name.upper(), []).append(value)
    require(pos == len(comment), "Unused trailing Vorbis bytes")
    cue = tags.get("CUESHEET", [])
    require(len(cue) == 1, "Expected one actual embedded CUESHEET comment")
    for term in ("FILE \"" + filename.name + "\" WAVE",
                 "TRACK 01 AUDIO", "TRACK 02 AUDIO",
                 "Embedded Alpha", "Embedded Beta",
                 "INDEX 01 00:02:00"):
        require(term in cue[0], f"Missing embedded CUE term {term}")

    pcm_md5 = hashlib.md5()
    frame_count = 0
    decoded_samples = 0
    while index < len(file):
        header_start = index
        require(index + 8 < len(file), "Truncated FLAC frame")
        require(file[index:index + 4] == bytes((255, 248, 121, 8)),
                "Unexpected FLAC frame format (fixture is fixed/mono/verbatim)")
        index += 4
        frame_id = file[index]
        index += 1
        require(frame_id == frame_count and frame_id < 128,
                "Unexpected FLAC frame number")
        count = int.from_bytes(file[index:index + 2], "big") + 1
        index += 2
        require(16 <= count <= 4096, "Invalid block sample count")
        header_crc = file[index]
        require(crc(file[header_start:index], 8, 0x07) == header_crc,
                "FLAC frame header CRC8 invalid")
        index += 1
        require(file[index] == 2, "Expected FLAC verbatim 16-bit subframe")
        index += 1
        length = count * 2
        require(index + length + 2 <= len(file), "Truncated FLAC PCM subframe")
        compressed_samples = file[index:index + length]
        require(not any(compressed_samples), "Expected wholly synthetic silent samples")
        pcm_md5.update(compressed_samples)
        index += length
        frame_crc = int.from_bytes(file[index:index + 2], "big")
        require(crc(file[header_start:index], 16, 0x8005) == frame_crc,
                "FLAC frame CRC16 invalid")
        index += 2
        decoded_samples += count
        frame_count += 1

    require(decoded_samples == total_samples and frame_count == 44,
            "Unexpected FLAC decoded sample/frame count")
    require(pcm_md5.digest() == streaminfo[18:34],
            "FLAC STREAMINFO PCM checksum mismatch")
    print("FLAC_EMBEDDED_INDEPENDENT_PCM_CRC_MD5_CUE=PASS "
          f"frames={frame_count} samples={decoded_samples}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("path", type=pathlib.Path)
    args = p.parse_args()
    verify(args.path)
