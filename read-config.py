#!/usr/bin/env python3
"""Bounded read/write for ~/.config/omarchy/shell-font.json."""
from __future__ import annotations

import json
import os
import stat
import sys
import tempfile

MAX_BYTES = 8192


def config_path() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "omarchy", "shell-font.json")


def check_path(path: str) -> None:
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode):
        raise SystemExit("config is a symlink")
    if not stat.S_ISREG(st.st_mode):
        raise SystemExit("config is not a regular file")
    if st.st_uid != os.getuid():
        raise SystemExit("config not owned by user")
    if st.st_size > MAX_BYTES:
        raise SystemExit("config too large")


def read() -> None:
    path = config_path()
    if not os.path.lexists(path):
        print("{}")
        return
    check_path(path)
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise SystemExit("config too large")
    data = json.loads(raw) if raw.strip() else {}
    if not isinstance(data, dict):
        raise SystemExit("config must be an object")
    out = {}
    if "enabled" in data:
        out["enabled"] = bool(data["enabled"])
    family = data.get("family")
    if isinstance(family, str) and family.strip():
        out["family"] = family.strip()[:128]
    weight = data.get("weight")
    if isinstance(weight, str) and weight.strip():
        out["weight"] = weight.strip()[:32]
    print(json.dumps(out, separators=(",", ":")))


def write() -> None:
    raw = sys.stdin.readline(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise SystemExit("write too large")
    data = json.loads(raw) if raw.strip() else {}
    if not isinstance(data, dict):
        raise SystemExit("config must be an object")
    path = config_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.lexists(path):
        check_path(path)
    payload = (
        json.dumps(
            {
                "enabled": bool(data.get("enabled", False)),
                "family": str(data.get("family") or "monospace").strip()[:128],
                "weight": str(data.get("weight") or "regular").strip()[:32],
            },
            indent=2,
        )
        + "\n"
    ).encode("utf-8")
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".shell-font.", suffix=".tmp")
    try:
        os.write(fd, payload)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(tmp, path)
        tmp = ""
    finally:
        if fd >= 0:
            os.close(fd)
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "write":
        write()
    else:
        read()
