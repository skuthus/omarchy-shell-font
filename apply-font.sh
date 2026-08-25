#!/bin/bash
# Build a real OmarchyShellFont face and point Quickshell at it.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell-font.json"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"
CONF="$CONF_DIR/50-omarchy-shell-font.conf"
OLD_CONF="$CONF_DIR/50-omarchy-bar-inter.conf"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/omarchy-shell-font"
FACE="$FONT_DIR/OmarchyShellFont.ttf"
BUILD="$HERE/build-face.py"
LOG="${XDG_RUNTIME_DIR:-/tmp}/omarchy-shell-font.log"

log() { printf '%s\n' "$*" | tee -a "$LOG"; }

reset_font() {
  rm -f "$CONF" "$OLD_CONF"
  rm -rf "$FONT_DIR"
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig"
  fc-cache -f >/dev/null 2>&1 || true
  log "RESET"
}

read_config() {
  [[ -f $CONFIG ]] || return 1
  python3 - "$CONFIG" <<'PY'
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text()
data = json.loads(raw) if raw.strip() else {}
if data.get("enabled") is False:
    raise SystemExit(2)
family = str(data.get("family") or "").strip()
weight = str(data.get("weight") or "regular").strip().lower()
if not family:
    raise SystemExit(1)
print(family)
print(weight)
PY
}

write_conf() {
  mkdir -p "$CONF_DIR"
  cat >"$CONF" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="prgname">
      <string>quickshell</string>
    </test>
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="assign_replace" binding="strong">
      <string>OmarchyShellFont</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="prgname">
      <string>omarchy-shell</string>
    </test>
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="assign_replace" binding="strong">
      <string>OmarchyShellFont</string>
    </edit>
  </match>
</fontconfig>
XML
  rm -f "$OLD_CONF"
}

apply_font() {
  local family="$1"
  local weight="$2"
  mkdir -p "$FONT_DIR"
  find "$FONT_DIR" -mindepth 1 -delete
  python3 "$BUILD" "$family" "$weight" "$FACE"
  write_conf
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig"
  fc-cache -f >/dev/null 2>&1 || true
  local resolved
  resolved=$(fc-match -f '%{family} %{file}' OmarchyShellFont)
  if [[ $resolved != OmarchyShellFont* || $resolved != *OmarchyShellFont.ttf* ]]; then
    log "ERROR generated face not visible: $resolved"
    exit 1
  fi
  log "OK $resolved"
}

RESET=0
FAMILY=""
WEIGHT=""

for arg in "$@"; do
  case "$arg" in
    -h|--help) echo "Usage: apply-font.sh [--reset] [family] [weight]"; exit 0 ;;
    --reset) RESET=1 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *)
      if [[ -z $FAMILY ]]; then FAMILY="$arg"
      elif [[ -z $WEIGHT ]]; then WEIGHT="$arg"
      fi
      ;;
  esac
done

echo "---- $(date -Iseconds) $* ----" >>"$LOG"

if [[ $RESET -eq 1 ]]; then
  reset_font
  exit 0
fi

if [[ -z $FAMILY ]]; then
  if ! cfg=$(read_config); then
    if [[ $? -eq 2 ]]; then
      reset_font
      exit 0
    fi
    log "ERROR no family"
    exit 1
  fi
  FAMILY=$(printf '%s\n' "$cfg" | sed -n '1p')
  WEIGHT=$(printf '%s\n' "$cfg" | sed -n '2p')
fi

apply_font "$FAMILY" "${WEIGHT:-regular}"
