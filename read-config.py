#!/usr/bin/env python3
"""Bounded, race-safe read/write for ~/.config/omarchy/shell-font.json."""
from __future__ import annotations

import errno
import json
import os
import stat
import sys
import tempfile

MAX_BYTES = 8192
OPEN_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK


def config_path() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "omarchy", "shell-font.json")


def open_config_fd(path: str) -> int:
    try:
        return os.open(path, OPEN_FLAGS)
    except OSError as exc:
        if exc.errno in (errno.ENOENT, errno.ENXIO):
            raise SystemExit("missing") from exc
        if exc.errno in (errno.ELOOP, errno.EMLINK):
            raise SystemExit("config is a symlink") from exc
        if exc.errno == errno.EWOULDBLOCK:
            raise SystemExit("config would block") from exc
        raise SystemExit(f"config open failed: {exc.errno}") from exc


def inspect_fd(fd: int) -> None:
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        raise SystemExit("config is not a regular file")
    if st.st_uid != os.getuid():
        raise SystemExit("config not owned by user")
    if st.st_size > MAX_BYTES:
        raise SystemExit("config too large")


def read_fd(fd: int) -> bytes:
    data = bytearray()
    while len(data) <= MAX_BYTES:
        try:
            chunk = os.read(fd, min(4096, MAX_BYTES + 1 - len(data)))
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                break
            raise
        if not chunk:
            break
        data.extend(chunk)
    if len(data) > MAX_BYTES:
        raise SystemExit("config too large")
    return bytes(data)


def sanitize(data: object) -> dict:
    if not isinstance(data, dict):
        raise SystemExit("config must be an object")
    out: dict = {}
    if "enabled" in data:
        out["enabled"] = bool(data["enabled"])
    family = data.get("family")
    if isinstance(family, str) and family.strip():
        out["family"] = family.strip()[:128]
    weight = data.get("weight")
    if isinstance(weight, str) and weight.strip():
        out["weight"] = weight.strip()[:32]
    return out


def read() -> None:
    path = config_path()
    try:
        fd = open_config_fd(path)
    except SystemExit as exc:
        if str(exc) == "missing":
            print("{}")
            return
        raise
    try:
        inspect_fd(fd)
        raw = read_fd(fd).decode("utf-8")
    finally:
        os.close(fd)
    parsed = json.loads(raw) if raw.strip() else {}
    print(json.dumps(sanitize(parsed), separators=(",", ":")), end="")


def write() -> None:
    raw = sys.stdin.readline(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise SystemExit("write too large")
    parsed = json.loads(raw) if raw.strip() else {}
    payload = (json.dumps(sanitize({
        "enabled": bool(parsed.get("enabled", False)) if isinstance(parsed, dict) else False,
        "family": parsed.get("family") if isinstance(parsed, dict) else "monospace",
        "weight": parsed.get("weight") if isinstance(parsed, dict) else "regular",
    }), indent=2) + "\n").encode("utf-8")
    if len(payload) > MAX_BYTES:
        raise SystemExit("write too large")

    path = config_path()
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
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
