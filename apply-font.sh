#!/bin/bash
# Apply or reset the Omarchy shell UI font.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell-font.json"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"
CONF="$CONF_DIR/50-omarchy-shell-font.conf"
OLD_CONF="$CONF_DIR/50-omarchy-bar-inter.conf"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/omarchy-shell-font"
PRIVATE_FAMILY="OmarchyShellFont"
LOG="${XDG_RUNTIME_DIR:-/tmp}/omarchy-shell-font.log"

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

fc_weight() {
  case "${1:-regular}" in
    thin) echo thin ;;
    extralight|extra-light) echo extralight ;;
    light) echo light ;;
    regular|normal) echo regular ;;
    medium) echo medium ;;
    semibold|semi-bold|demibold|demi-bold) echo demibold ;;
    bold) echo bold ;;
    extrabold|extra-bold) echo extrabold ;;
    black) echo black ;;
    *) echo regular ;;
  esac
}

reset_font() {
  rm -f "$CONF" "$OLD_CONF"
  rm -rf "$FONT_DIR"
  fc-cache -f >/dev/null 2>&1 || true
  echo "RESET"
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
  local family_xml="$1"
  local style_xml="$2"
  mkdir -p "$CONF_DIR"
  cat >"$CONF" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="scan">
    <test name="family">
      <string>${family_xml}</string>
    </test>
    <test name="style">
      <string>${style_xml}</string>
    </test>
    <test name="slant" compare="eq">
      <const>roman</const>
    </test>
    <edit name="family" mode="prepend" binding="strong">
      <string>${PRIVATE_FAMILY}</string>
    </edit>
  </match>

  <match target="pattern">
    <test name="prgname">
      <string>quickshell</string>
    </test>
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="assign_replace" binding="strong">
      <string>${PRIVATE_FAMILY}</string>
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
      <string>${PRIVATE_FAMILY}</string>
    </edit>
  </match>
</fontconfig>
XML
  rm -f "$OLD_CONF"
}

apply_font() {
  local family="$1"
  local weight="$2"
  local fcw file style ext dest resolved family_xml style_xml

  fcw=$(fc_weight "$weight")
  file=$(fc-match -f '%{file}' "${family}:weight=${fcw}:slant=roman")
  style=$(fc-match -f '%{style}' "${family}:weight=${fcw}:slant=roman")
  style="${style%%,*}"
  style="${style%% *}"
  # Resolve through any previous apply symlink BEFORE wiping FONT_DIR.
  if [[ -n $file ]]; then
    file=$(readlink -f "$file")
  fi

  if [[ -z $file || ! -e $file ]]; then
    echo "ERROR no font file for $family $weight" >&2
    exit 1
  fi
  if [[ -z $style ]]; then
    style="Regular"
  fi

  mkdir -p "$FONT_DIR"
  find "$FONT_DIR" -mindepth 1 -delete
  ext="${file##*.}"
  dest="$FONT_DIR/ui-font.${ext}"
  ln -sfn "$file" "$dest"

  family_xml=$(xml_escape "$family")
  style_xml=$(xml_escape "$style")
  write_conf "$family_xml" "$style_xml"
  # A directory-only rebuild leaves stale OmarchyShellFont faces in the
  # user cache, so Qt can keep painting the previous (or a fallback) font.
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig"
  fc-cache -f >/dev/null 2>&1 || true

  resolved=$(fc-match -f '%{family}' ":family=${PRIVATE_FAMILY}")
  if [[ $resolved != ${PRIVATE_FAMILY}* ]]; then
    echo "ERROR private family missing after scan (file=$file style=$style resolved=$resolved)" >&2
    exit 1
  fi
  echo "OK ${PRIVATE_FAMILY} ${family} ${weight} style=${style} file=${file}"
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

{
  echo "---- $(date -Iseconds) ----"
  echo "args: $*"

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
      echo "ERROR no family" >&2
      exit 1
    fi
    FAMILY=$(printf '%s\n' "$cfg" | sed -n '1p')
    WEIGHT=$(printf '%s\n' "$cfg" | sed -n '2p')
  fi

  WEIGHT="${WEIGHT:-regular}"
  apply_font "$FAMILY" "$WEIGHT"
} 2>&1 | tee -a "$LOG"
