#!/usr/bin/env python3
"""Extract one installed face and rewrite it as OmarchyShellFont Regular."""
from __future__ import annotations

import errno
import math
import os
import stat
import struct
import subprocess
import sys

MAX_FONT_BYTES = 16 * 1024 * 1024

FAMILY = "OmarchyShellFont"
SUBFAMILY = "Regular"


def be_u16(n: int) -> bytes:
    return struct.pack(">H", n)


def be_u32(n: int) -> bytes:
    return struct.pack(">I", n)


def read_u16(data: bytes, off: int) -> int:
    return struct.unpack_from(">H", data, off)[0]


def read_u32(data: bytes, off: int) -> int:
    return struct.unpack_from(">I", data, off)[0]


def sfnt_search(num_tables: int) -> tuple[int, int, int]:
    max_pow2 = 1
    while max_pow2 * 2 <= num_tables:
        max_pow2 *= 2
    search_range = max_pow2 * 16
    entry_selector = int(math.log2(max_pow2)) if max_pow2 else 0
    range_shift = num_tables * 16 - search_range
    return search_range, entry_selector, range_shift


def table_checksum(data: bytes) -> int:
    padded = data + b"\x00" * ((4 - (len(data) % 4)) % 4)
    total = 0
    for i in range(0, len(padded), 4):
        total = (total + struct.unpack_from(">I", padded, i)[0]) & 0xFFFFFFFF
    return total


def extract_face(data: bytes, index: int) -> bytes:
    if data[:4] != b"ttcf":
        return data
    num_fonts = read_u32(data, 8)
    if index < 0 or index >= num_fonts:
        index = 0
    offset = read_u32(data, 12 + 4 * index)
    sfnt_version = data[offset : offset + 4]
    num_tables = read_u16(data, offset + 4)
    records = []
    for i in range(num_tables):
        rec = offset + 12 + i * 16
        tag = data[rec : rec + 4]
        tbl_offset = read_u32(data, rec + 8)
        length = read_u32(data, rec + 12)
        records.append((tag, data[tbl_offset : tbl_offset + length]))
    return pack_sfnt(sfnt_version, records)


def pack_sfnt(sfnt_version: bytes, records: list[tuple[bytes, bytes]]) -> bytes:
    records = sorted(records, key=lambda r: r[0])
    num_tables = len(records)
    search_range, entry_selector, range_shift = sfnt_search(num_tables)
    header = sfnt_version + be_u16(num_tables) + be_u16(search_range) + be_u16(entry_selector) + be_u16(range_shift)
    offset = 12 + 16 * num_tables
    directory = b""
    packed_tables = b""
    for tag, raw in records:
        pad = b"\x00" * ((4 - (len(raw) % 4)) % 4)
        checksum = table_checksum(raw)
        directory += tag + be_u32(checksum) + be_u32(offset) + be_u32(len(raw))
        packed_tables += raw + pad
        offset += len(raw) + len(pad)
    font = bytearray(header + directory + packed_tables)
    return finalize_head_checksum(font)


def finalize_head_checksum(font: bytearray) -> bytes:
    num_tables = read_u16(bytes(font), 4)
    head_off = None
    for i in range(num_tables):
        rec = 12 + i * 16
        if font[rec : rec + 4] == b"head":
            head_off = read_u32(bytes(font), rec + 8)
            break
    if head_off is None:
        return bytes(font)
    font[head_off + 8 : head_off + 12] = b"\x00\x00\x00\x00"
    checksum = table_checksum(bytes(font))
    adjust = (0xB1B0AFBA - checksum) & 0xFFFFFFFF
    font[head_off + 8 : head_off + 12] = be_u32(adjust)
    return bytes(font)


def decode_name(platform: int, raw: bytes) -> str:
    if platform == 3:
        return raw.decode("utf-16-be", errors="replace")
    return raw.decode("mac_roman", errors="replace")


def encode_name(platform: int, text: str) -> bytes:
    if platform == 3:
        return text.encode("utf-16-be")
    return text.encode("mac_roman", errors="replace")


def rewrite_name_table(raw: bytes) -> bytes:
    if len(raw) < 6:
        return raw
    fmt = read_u16(raw, 0)
    count = read_u16(raw, 2)
    string_off = read_u16(raw, 4)
    wanted = {
        1: FAMILY,
        2: SUBFAMILY,
        3: f"{FAMILY} {SUBFAMILY}",
        4: f"{FAMILY} {SUBFAMILY}",
        6: "OmarchyShellFont-Regular",
    }
    records = []
    for i in range(count):
        rec = 6 + i * 12
        platform, encoding, language, name_id, length, offset = struct.unpack_from(">HHHHHH", raw, rec)
        if name_id in (16, 17, 21, 22):
            continue
        text = wanted.get(name_id)
        payload = encode_name(platform, text) if text is not None else raw[string_off + offset : string_off + offset + length]
        records.append((platform, encoding, language, name_id, payload))
    have = {(p, e, l, n) for p, e, l, n, _ in records}
    for platform, encoding, language in ((3, 1, 0x409), (1, 0, 0)):
        for name_id, text in wanted.items():
            key = (platform, encoding, language, name_id)
            if key in have:
                continue
            records.append((platform, encoding, language, name_id, encode_name(platform, text)))
    records.sort()
    storage = b""
    out_recs = b""
    for platform, encoding, language, name_id, payload in records:
        out_recs += struct.pack(">HHHHHH", platform, encoding, language, name_id, len(payload), len(storage))
        storage += payload
    body = be_u16(fmt if fmt in (0, 1) else 0) + be_u16(len(records)) + be_u16(6 + 12 * len(records)) + out_recs + storage
    return body


def replace_table(font: bytes, tag: bytes, new_raw: bytes) -> bytes:
    sfnt_version = font[:4]
    num_tables = read_u16(font, 4)
    records = []
    replaced = False
    for i in range(num_tables):
        rec = 12 + i * 16
        this_tag = font[rec : rec + 4]
        offset = read_u32(font, rec + 8)
        length = read_u32(font, rec + 12)
        raw = new_raw if this_tag == tag else font[offset : offset + length]
        if this_tag == tag:
            replaced = True
        records.append((this_tag, raw))
    if not replaced:
        records.append((tag, new_raw))
    return pack_sfnt(sfnt_version, records)


STYLE_QUERY = {
    "thin": "Thin",
    "extralight": "Ultralight",
    "light": "Light",
    "regular": "Regular",
    "medium": "Medium",
    "demibold": "Semibold",
    "bold": "Bold",
    "extrabold": "Heavy",
    "black": "Black",
}


def fc_query(query: str) -> tuple[str, int, str]:
    raw = subprocess.check_output(["fc-match", "-f", "%{file}\n%{index}\n%{style}\n", query], text=True)
    lines = [ln.strip() for ln in raw.splitlines()]
    path = lines[0] if lines else ""
    try:
        index = int(lines[1]) if len(lines) > 1 and lines[1] else 0
    except ValueError:
        index = 0
    style = lines[2] if len(lines) > 2 else ""
    if not path:
        raise SystemExit(f"no font matched {query!r}")
    path = os.path.realpath(path)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    except OSError as exc:
        if exc.errno in (errno.ELOOP, errno.EMLINK):
            raise SystemExit("font path is a symlink") from exc
        raise SystemExit(f"font open failed: {exc.errno}") from exc
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise SystemExit("font is not a regular file")
        if st.st_size <= 0 or st.st_size > MAX_FONT_BYTES:
            raise SystemExit("font file too large")
    finally:
        os.close(fd)
    return path, index, style


def fc_match(family: str, weight: str) -> tuple[str, int]:
    style_name = STYLE_QUERY.get(weight)
    if style_name:
        path, index, style = fc_query(f"{family}:style={style_name}:slant=roman")
        if style_name.lower() in style.lower():
            return path, index
    path, index, _ = fc_query(f"{family}:weight={weight}:slant=roman")
    return path, index


def weight_const(weight: str) -> str:
    return {
        "thin": "thin",
        "extralight": "extralight",
        "extra-light": "extralight",
        "light": "light",
        "regular": "regular",
        "normal": "regular",
        "medium": "medium",
        "semibold": "demibold",
        "semi-bold": "demibold",
        "demibold": "demibold",
        "bold": "bold",
        "extrabold": "extrabold",
        "extra-bold": "extrabold",
        "black": "black",
    }.get((weight or "regular").lower(), "regular")


def build(family: str, weight: str, dest: str) -> None:
    src, index = fc_match(family, weight_const(weight))
    fd = os.open(src, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    try:
        raw = os.read(fd, MAX_FONT_BYTES + 1)
    finally:
        os.close(fd)
    if len(raw) > MAX_FONT_BYTES:
        raise SystemExit("font file too large")
    data = extract_face(raw, index)
    num_tables = read_u16(data, 4)
    name_raw = None
    for i in range(num_tables):
        rec = 12 + i * 16
        if data[rec : rec + 4] == b"name":
            offset = read_u32(data, rec + 8)
            length = read_u32(data, rec + 12)
            name_raw = data[offset : offset + length]
            break
    if name_raw is None:
        raise SystemExit("font has no name table")
    data = replace_table(data, b"name", rewrite_name_table(name_raw))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, dest)
    print(f"OK {FAMILY} from {src}#{index} -> {dest} ({len(data)} bytes)")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: build-face.py <family> <weight> <dest.ttf>", file=sys.stderr)
        raise SystemExit(2)
    build(sys.argv[1], sys.argv[2], sys.argv[3])
