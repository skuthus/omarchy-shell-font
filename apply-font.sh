#!/bin/bash
# Build a real OmarchyShellFont face and point Quickshell at it.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"
CONF="$CONF_DIR/50-omarchy-shell-font.conf"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/omarchy-shell-font"
FACE="$FONT_DIR/OmarchyShellFont.ttf"
BUILD="$HERE/build-face.py"
CONFIG_TOOL="$HERE/read-config.py"
LOG="${XDG_RUNTIME_DIR:-/tmp}/omarchy-shell-font.log"
MAX_LOG=65536

log() {
  if [[ -f $LOG && $(wc -c <"$LOG") -gt $MAX_LOG ]]; then
    : >"$LOG"
  fi
  printf '%s\n' "$*" >>"$LOG"
}

owned_dir() {
  local p=$1
  [[ -e $p ]] || return 0
  [[ ! -L $p ]] || { echo "refusing symlink path: $p" >&2; exit 1; }
  [[ -d $p ]] || { echo "not a directory: $p" >&2; exit 1; }
  [[ -O $p ]] || { echo "unowned directory: $p" >&2; exit 1; }
}

reset_font() {
  owned_dir "$(dirname "$CONF")" || true
  rm -f "$CONF"
  if [[ -e $FONT_DIR ]]; then
    owned_dir "$FONT_DIR"
    find "$FONT_DIR" -mindepth 1 -maxdepth 1 -delete
    rmdir "$FONT_DIR" 2>/dev/null || true
  fi
  fc-cache -f >/dev/null 2>&1 || true
  log "RESET"
}

write_conf() {
  mkdir -p "$CONF_DIR"
  owned_dir "$CONF_DIR"
  local tmp
  tmp=$(mktemp "$CONF_DIR/.omarchy-shell-font.XXXXXX")
  cat >"$tmp" <<'XML'
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
  mv -f "$tmp" "$CONF"
}

apply_font() {
  local family=$1 weight=$2
  mkdir -p "$FONT_DIR"
  owned_dir "$FONT_DIR"
  find "$FONT_DIR" -mindepth 1 -maxdepth 1 -delete
  python3 "$BUILD" "$family" "$weight" "$FACE"
  # Do not remap Quickshell "monospace" — icons need that alias.
  rm -f "$CONF"
  fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  local resolved
  resolved=$(fc-match -f '%{family} %{file}' OmarchyShellFont)
  if [[ $resolved != OmarchyShellFont* || $resolved != *OmarchyShellFont.ttf* ]]; then
    echo "ERROR generated face not visible: $resolved" >&2
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
      if [[ -z $FAMILY ]]; then FAMILY=$arg
      elif [[ -z $WEIGHT ]]; then WEIGHT=$arg
      fi
      ;;
  esac
done

if [[ $RESET -eq 1 ]]; then
  reset_font
  exit 0
fi

if [[ -z $FAMILY ]]; then
  mapfile -t fields < <(python3 "$CONFIG_TOOL" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read() or "{}")
if d.get("enabled") is False:
    raise SystemExit(2)
family=str(d.get("family") or "").strip()
if not family:
    raise SystemExit(1)
print(family)
print(str(d.get("weight") or "regular").strip() or "regular")
') || {
    if [[ $? -eq 2 ]]; then reset_font; exit 0; fi
    echo "ERROR no family" >&2
    exit 1
  }
  FAMILY=${fields[0]}
  WEIGHT=${fields[1]}
fi

apply_font "$FAMILY" "${WEIGHT:-regular}"
